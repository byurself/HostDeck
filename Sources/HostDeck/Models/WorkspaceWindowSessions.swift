import Foundation
import Observation

@Observable
@MainActor
final class TerminalWindowSession {
    let id: UUID
    let profile: ServerProfile

    var connectionState = ConnectionState.disconnected
    var terminalEvents: [TerminalEvent] = [
        TerminalEvent(kind: .reset),
        TerminalEvent(kind: .write, data: "HostDeck terminal\r\n")
    ]
    var statusMessage = "Ready"

    private let sshClient: SSHClient
    private let secret: CredentialSecret?

    init(id: UUID, profile: ServerProfile, secret: CredentialSecret?, sshClient: SSHClient) {
        self.id = id
        self.profile = profile
        self.secret = secret
        self.sshClient = sshClient
    }

    func connect() async {
        switch connectionState {
        case .connected, .connecting:
            return
        case .disconnected, .failed:
            break
        }

        connectionState = .connecting(profile.displayName)
        statusMessage = "Connecting to \(profile.host)..."
        terminalEvents = [
            TerminalEvent(kind: .reset),
            TerminalEvent(kind: .write, data: "Opening SSH session to \(profile.username)@\(profile.host):\(profile.port)\r\n")
        ]

        do {
            let session = self
            await sshClient.setOutputHandler { [session] output in
                await MainActor.run {
                    session.writeTerminal(output)
                }
            }
            try await sshClient.connect(profile: profile, secret: secret)
            connectionState = .connected(profile.displayName)
            statusMessage = "Connected to \(profile.displayName)"
        } catch {
            connectionState = .failed(error.localizedDescription)
            statusMessage = "Connection failed"
            writeTerminal("Connection failed: \(error.localizedDescription)\r\n")
        }
    }

    func disconnect() async {
        await sshClient.disconnect()
        await sshClient.setOutputHandler(nil)
        connectionState = .disconnected
        statusMessage = "Disconnected"
        writeTerminal("\r\nSession closed.\r\n")
    }

    func sendTerminalInput(_ text: String) async {
        guard connectionState.isConnected else {
            writeTerminal("Not connected.\r\n")
            return
        }

        do {
            try await sshClient.sendRaw(text)
        } catch {
            writeTerminal("\r\n\(error.localizedDescription)\r\n")
        }
    }

    func resizeTerminal(columns: Int, rows: Int) async {
        await sshClient.resize(columns: columns, rows: rows)
    }

    private func writeTerminal(_ text: String) {
        terminalEvents.append(TerminalEvent(kind: .write, data: text))
        if terminalEvents.count > 1_000 {
            terminalEvents.removeFirst(terminalEvents.count - 1_000)
        }
    }
}

@Observable
@MainActor
final class FileTransferWindowSession {
    let id: UUID
    let profile: ServerProfile

    var connectionState = ConnectionState.disconnected
    var statusMessage = "Ready"
    var localPath = FileManager.default.homeDirectoryForCurrentUser
    var localFiles: [LocalFile] = []
    var localDirectoryError: String?
    var remotePath: String
    var remoteFiles: [RemoteFile] = []

    private let sftpClient: SFTPClient
    private let secret: CredentialSecret?

    init(id: UUID, profile: ServerProfile, secret: CredentialSecret?, sftpClient: SFTPClient) {
        self.id = id
        self.profile = profile
        self.secret = secret
        self.sftpClient = sftpClient
        self.remotePath = profile.defaultPath.isEmpty ? "/" : profile.defaultPath.normalizedRemoteDirectoryPath
    }

    func connect() async {
        refreshLocalDirectory()

        switch connectionState {
        case .connected:
            await refreshRemoteDirectory()
            return
        case .connecting:
            return
        case .disconnected, .failed:
            break
        }

        connectionState = .connecting(profile.displayName)
        statusMessage = "Connecting to \(profile.host)..."

        do {
            try await sftpClient.connect(profile: profile, secret: secret)
            connectionState = .connected(profile.displayName)
            statusMessage = "Connected to \(profile.displayName)"
            if !(await loadRemoteDirectory(at: remotePath)), remotePath != "/" {
                remotePath = "/"
                _ = await loadRemoteDirectory(at: remotePath)
            }
        } catch {
            connectionState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        await sftpClient.disconnect()
        connectionState = .disconnected
        statusMessage = "Disconnected"
        remoteFiles = []
    }

    func refreshLocalDirectory() {
        do {
            localFiles = try LocalFile.listDirectory(at: localPath)
            localDirectoryError = nil
            statusMessage = "Refreshed \(localPath.path)"
        } catch {
            localFiles = []
            localDirectoryError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    func openLocalFile(_ file: LocalFile) {
        guard file.kind == .directory else { return }
        localPath = file.url
        refreshLocalDirectory()
    }

    func openLocalPath(_ path: String) {
        let expandedPath = path.trimmingCharacters(in: .whitespacesAndNewlines).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            statusMessage = "Local folder does not exist: \(path)"
            return
        }

        localPath = url
        refreshLocalDirectory()
    }

    func goUpLocalDirectory() {
        let parent = localPath.deletingLastPathComponent()
        guard parent.path != localPath.path else { return }
        localPath = parent
        refreshLocalDirectory()
    }

    func refreshRemoteDirectory() async {
        guard connectionState.isConnected else {
            remoteFiles = []
            statusMessage = "Connect to browse remote files"
            return
        }

        _ = await loadRemoteDirectory(at: remotePath)
    }

    func openRemoteFile(_ file: RemoteFile) async {
        guard file.kind == .directory else { return }
        if file.name == ".." {
            await goUpRemoteDirectory()
            return
        }
        remotePath = remotePath.appendingPathComponent(file.name)
        await refreshRemoteDirectory()
    }

    func openRemotePath(_ path: String) async {
        guard connectionState.isConnected else {
            statusMessage = "Connect to browse remote files"
            return
        }

        let previousPath = remotePath
        remotePath = path.normalizedRemoteDirectoryPath

        do {
            _ = try await sftpClient.listDirectory(path: remotePath)
            await refreshRemoteDirectory()
            statusMessage = "Refreshed \(remotePath)"
        } catch {
            remotePath = previousPath
            statusMessage = error.localizedDescription
        }
    }

    func goUpRemoteDirectory() async {
        guard remotePath != "/" else { return }
        remotePath = remotePath.deletingLastPathComponent
        await refreshRemoteDirectory()
    }

    @discardableResult
    private func loadRemoteDirectory(at path: String) async -> Bool {
        do {
            remoteFiles = try await sftpClient.listDirectory(path: path)
            statusMessage = "Refreshed \(path)"
            return true
        } catch {
            remoteFiles = []
            statusMessage = error.localizedDescription
            return false
        }
    }
}
