import Foundation
import Observation

private struct ServerRuntimeSession {
    var connectionState: ConnectionState
    var terminalBuffer: [TerminalLine]
    var terminalEvents: [TerminalEvent]
    var remotePath: String
    var remoteFiles: [RemoteFile]
    var statusMessage: String

    static func fresh() -> ServerRuntimeSession {
        ServerRuntimeSession(
            connectionState: .disconnected,
            terminalBuffer: TerminalLine.welcome,
            terminalEvents: [
                TerminalEvent(kind: .reset),
                TerminalEvent(kind: .write, data: "HostDeck terminal\r\nSelect a server and connect.\r\n")
            ],
            remotePath: "/",
            remoteFiles: [],
            statusMessage: "Ready"
        )
    }

    static let emptyTerminalEvents = [
        TerminalEvent(kind: .reset),
        TerminalEvent(kind: .write, data: "HostDeck terminal\r\nSelect a server and connect.\r\n")
    ]
}

private enum TransferWork {
    case upload(serverID: ServerProfile.ID, localURL: URL, remotePath: String, filename: String)
    case download(serverID: ServerProfile.ID, remotePath: String, localURL: URL, filename: String)

    var serverID: ServerProfile.ID {
        switch self {
        case .upload(let serverID, _, _, _), .download(let serverID, _, _, _):
            serverID
        }
    }

    var filename: String {
        switch self {
        case .upload(_, _, _, let filename), .download(_, _, _, let filename):
            filename
        }
    }
}

struct WorkspaceTab: Identifiable, Hashable {
    enum Kind: Hashable {
        case primary(WorkspaceKind, ServerProfile.ID?)
        case terminal(UUID)
        case files(UUID)
    }

    var id: UUID
    var title: String
    var subtitle: String
    var kind: Kind

    var systemImage: String {
        switch kind {
        case .primary(let workspace, _):
            workspace.systemImage
        case .terminal:
            "terminal"
        case .files:
            "folder"
        }
    }

    var isPrimary: Bool {
        if case .primary = kind {
            return true
        }
        return false
    }

    var serverID: ServerProfile.ID? {
        switch kind {
        case .primary(_, let serverID):
            return serverID
        default:
            return nil
        }
    }
}

@Observable
@MainActor
final class AppModel {
    let profileStore: ServerProfileStore
    let transferStore: TransferQueueStore

    var selectedServerID: ServerProfile.ID? {
        didSet {
            if let selectedServerID {
                ensureSession(for: selectedServerID)
            }
        }
    }

    var selectedWorkspace: WorkspaceKind = .terminal
    var localPath = FileManager.default.homeDirectoryForCurrentUser
    var localFiles: [LocalFile] = []
    var localDirectoryError: String?
    var workspaceTabs: [WorkspaceTab] = []
    var selectedWorkspaceTabID: WorkspaceTab.ID?
    var isPresentingServerEditor = false
    var editingServer: ServerProfile?

    private var sessions: [ServerProfile.ID: ServerRuntimeSession] = [:]
    private var sshClients: [ServerProfile.ID: SSHClient] = [:]
    private var sftpClients: [ServerProfile.ID: SFTPClient] = [:]
    private var pendingTransfers: [TransferJob.ID: TransferWork] = [:]
    private var runningTransferTasks: [TransferJob.ID: Task<Void, Never>] = [:]
    private var credentialCache: [ServerProfile.ID: CredentialSecret] = [:]
    private var didAttemptCredentialMigration = false
    private var terminalWindowSessions: [UUID: TerminalWindowSession] = [:]
    private var fileTransferWindowSessions: [UUID: FileTransferWindowSession] = [:]
    private var generalStatusMessage = "Ready"

    private let makeSSHClient: () -> SSHClient
    private let makeSFTPClient: () -> SFTPClient
    private let keychainStore: KeychainStore
    private let transferManager: TransferManager
    private let connectionTester: ConnectionTester

    init(
        makeSSHClient: @escaping () -> SSHClient = { LibSSH2SSHClient() },
        makeSFTPClient: @escaping () -> SFTPClient = { LibSSH2SFTPClient() },
        keychainStore: KeychainStore = KeychainStore(),
        connectionTester: ConnectionTester = LibSSH2ConnectionTester()
    ) {
        let profileStore = ServerProfileStore()
        let transferStore = TransferQueueStore()

        self.profileStore = profileStore
        self.transferStore = transferStore
        self.makeSSHClient = makeSSHClient
        self.makeSFTPClient = makeSFTPClient
        self.keychainStore = keychainStore
        self.transferManager = TransferManager(store: transferStore)
        self.connectionTester = connectionTester
        refreshLocalDirectory()
    }

    var selectedServer: ServerProfile? {
        get {
            guard let selectedServerID else { return nil }
            return profileStore.profiles.first { $0.id == selectedServerID }
        }
        set {
            selectedServerID = newValue?.id
        }
    }

    var connectionState: ConnectionState {
        guard let selectedServerID else { return .disconnected }
        return connectionState(for: selectedServerID)
    }

    var terminalBuffer: [TerminalLine] {
        guard let selectedServerID else { return TerminalLine.welcome }
        return sessionSnapshot(for: selectedServerID).terminalBuffer
    }

    var terminalEvents: [TerminalEvent] {
        guard let selectedServerID else { return ServerRuntimeSession.emptyTerminalEvents }
        return sessionSnapshot(for: selectedServerID).terminalEvents
    }

    var remotePath: String {
        guard let selectedServerID else { return "/" }
        return sessionSnapshot(for: selectedServerID).remotePath
    }

    var remoteFiles: [RemoteFile] {
        guard let selectedServerID else { return [] }
        return sessionSnapshot(for: selectedServerID).remoteFiles
    }

    var statusMessage: String {
        guard let selectedServerID else { return generalStatusMessage }
        return sessionSnapshot(for: selectedServerID).statusMessage
    }

    var terminalPrompt: String {
        guard connectionState.isConnected, let selectedServer else { return "HostDeck $" }
        return "\(selectedServer.username)@\(selectedServer.host) $"
    }

    var visibleTransferJob: TransferJob? {
        transferStore.jobs.first { $0.status == .running }
            ?? transferStore.jobs.first { $0.status == .queued }
            ?? transferStore.jobs.first
    }

    var visibleTransferJobs: [TransferJob] {
        Array(transferStore.jobs.prefix(4))
    }

    func connectionState(for serverID: ServerProfile.ID) -> ConnectionState {
        sessionSnapshot(for: serverID).connectionState
    }

    var selectedWorkspaceTab: WorkspaceTab? {
        guard let selectedWorkspaceTabID else { return nil }
        return workspaceTabs.first { $0.id == selectedWorkspaceTabID }
    }

    func selectServer(_ serverID: ServerProfile.ID) {
        selectedServerID = serverID
        ensureSession(for: serverID)
    }

    func selectWorkspace(_ workspace: WorkspaceKind) {
        selectedWorkspace = workspace
        ensurePrimaryWorkspaceTab(for: workspace, profile: selectedServer, select: true)
    }

    func selectWorkspaceTab(_ tabID: WorkspaceTab.ID) {
        guard let tab = workspaceTabs.first(where: { $0.id == tabID }) else { return }
        selectedWorkspaceTabID = tabID

        switch tab.kind {
        case .primary(let workspace, let serverID):
            selectedWorkspace = workspace
            if let serverID {
                selectedServerID = serverID
            }
        case .terminal:
            selectedWorkspace = .terminal
            if case .terminal(let sessionID) = tab.kind,
               let session = terminalWindowSessions[sessionID] {
                selectedServerID = session.profile.id
            }
        case .files:
            selectedWorkspace = .files
            if case .files(let sessionID) = tab.kind,
               let session = fileTransferWindowSessions[sessionID] {
                selectedServerID = session.profile.id
            }
        }
    }

    func createTerminalTabForSelectedServer() {
        guard let profile = selectedServer else { return }

        let id = UUID()
        let session = TerminalWindowSession(
            id: id,
            profile: profile,
            secret: try? loadCachedSecret(for: profile.id),
            sshClient: makeSSHClient()
        )
        terminalWindowSessions[id] = session
        let tab = WorkspaceTab(
            id: id,
            title: "Terminal",
            subtitle: profile.displayName,
            kind: .terminal(id)
        )
        workspaceTabs.append(tab)
        selectedWorkspace = .terminal
        selectedWorkspaceTabID = tab.id
    }

    func terminalWindowSession(for id: UUID) -> TerminalWindowSession? {
        terminalWindowSessions[id]
    }

    func createFileTransferTabForSelectedServer() {
        guard let profile = selectedServer else { return }

        let id = UUID()
        let session = FileTransferWindowSession(
            id: id,
            profile: profile,
            secret: try? loadCachedSecret(for: profile.id),
            sftpClient: makeSFTPClient()
        )
        fileTransferWindowSessions[id] = session
        let tab = WorkspaceTab(
            id: id,
            title: "SFTP",
            subtitle: profile.displayName,
            kind: .files(id)
        )
        workspaceTabs.append(tab)
        selectedWorkspace = .files
        selectedWorkspaceTabID = tab.id
    }

    func fileTransferWindowSession(for id: UUID) -> FileTransferWindowSession? {
        fileTransferWindowSessions[id]
    }

    func closeWorkspaceTab(_ tabID: WorkspaceTab.ID) {
        guard let tab = workspaceTabs.first(where: { $0.id == tabID }) else { return }
        let affectedServerID = serverID(for: tab)

        switch tab.kind {
        case .primary:
            break
        case .terminal(let sessionID):
            let session = terminalWindowSessions.removeValue(forKey: sessionID)
            Task { await session?.disconnect() }
        case .files(let sessionID):
            let session = fileTransferWindowSessions.removeValue(forKey: sessionID)
            Task { await session?.disconnect() }
        }

        workspaceTabs.removeAll { $0.id == tabID }
        if selectedWorkspaceTabID == tabID {
            selectedWorkspaceTabID = workspaceTabs.last?.id
            if let selectedWorkspaceTabID {
                selectWorkspaceTab(selectedWorkspaceTabID)
            }
        }

        if let affectedServerID, !hasOpenSSHOrSFTPTab(for: affectedServerID) {
            Task { await disconnectServer(affectedServerID) }
        }
    }

    private func ensurePrimaryWorkspaceTab(for workspace: WorkspaceKind, profile: ServerProfile?, select: Bool) {
        if workspace != .transfers, profile == nil {
            if select {
                selectedWorkspaceTabID = nil
            }
            return
        }

        let serverID = workspace == .transfers ? nil : profile?.id
        if let existingID = primaryWorkspaceTabID(for: workspace, serverID: serverID) {
            if select {
                selectWorkspaceTab(existingID)
            }
            return
        }

        let tab = WorkspaceTab(
            id: UUID(),
            title: workspace.label,
            subtitle: profile?.displayName ?? "Main",
            kind: .primary(workspace, serverID)
        )
        workspaceTabs.append(tab)
        if select {
            selectWorkspaceTab(tab.id)
        }
    }

    private func primaryWorkspaceTabID(for workspace: WorkspaceKind, serverID: ServerProfile.ID?) -> WorkspaceTab.ID? {
        workspaceTabs.first {
            if case .primary(let tabWorkspace, let tabServerID) = $0.kind {
                return tabWorkspace == workspace && tabServerID == serverID
            }
            return false
        }?.id
    }

    private func serverID(for tab: WorkspaceTab) -> ServerProfile.ID? {
        switch tab.kind {
        case .primary(_, let serverID):
            serverID
        case .terminal(let sessionID):
            terminalWindowSessions[sessionID]?.profile.id
        case .files(let sessionID):
            fileTransferWindowSessions[sessionID]?.profile.id
        }
    }

    private func hasOpenSSHOrSFTPTab(for serverID: ServerProfile.ID) -> Bool {
        workspaceTabs.contains { tab in
            switch tab.kind {
            case .primary(let workspace, let tabServerID):
                return tabServerID == serverID && (workspace == .terminal || workspace == .files)
            case .terminal(let sessionID):
                return terminalWindowSessions[sessionID]?.profile.id == serverID
            case .files(let sessionID):
                return fileTransferWindowSessions[sessionID]?.profile.id == serverID
            }
        }
    }

    func saveProfile(_ profile: ServerProfile, secret: CredentialSecret?) {
        profileStore.upsert(profile)
        selectedServerID = profile.id
        ensureSession(for: profile.id)

        if let secret {
            try? keychainStore.save(secret, for: profile.id.uuidString)
            credentialCache[profile.id] = secret
        }
    }

    func testConnection(profile: ServerProfile, secret: CredentialSecret?) async -> ConnectionTestResult {
        await connectionTester.test(profile: profile, secret: secret)
    }

    func deleteSelectedProfile() {
        guard let selectedServerID else { return }
        let sshClient = sshClients.removeValue(forKey: selectedServerID)
        let sftpClient = sftpClients.removeValue(forKey: selectedServerID)

        Task {
            await sshClient?.disconnect()
            await sshClient?.setOutputHandler(nil)
            await sftpClient?.disconnect()
        }

        sessions.removeValue(forKey: selectedServerID)
        credentialCache.removeValue(forKey: selectedServerID)
        profileStore.delete(id: selectedServerID)
        try? keychainStore.deleteSecret(for: selectedServerID.uuidString)
        self.selectedServerID = profileStore.profiles.first?.id
    }

    func connectSelectedServer() async {
        guard let profile = selectedServer else { return }
        let serverID = profile.id
        ensureSession(for: serverID)
        ensurePrimaryWorkspaceTab(for: .terminal, profile: profile, select: true)

        switch connectionState(for: serverID) {
        case .connected:
            setStatus("Already connected to \(profile.displayName)", for: serverID)
            return
        case .connecting:
            return
        case .disconnected, .failed:
            break
        }

        updateSession(for: serverID) { session in
            session.connectionState = .connecting(profile.displayName)
            session.statusMessage = "Connecting to \(profile.host)..."
            session.terminalBuffer = TerminalLine.welcome
            session.terminalEvents = [
                TerminalEvent(kind: .reset),
                TerminalEvent(kind: .write, data: "HostDeck terminal\r\nSelect a server and connect.\r\n"),
                TerminalEvent(kind: .write, data: "Opening SSH session to \(profile.username)@\(profile.host):\(profile.port)\r\n")
            ]
            session.remotePath = "/"
            session.remoteFiles = []
        }

        do {
            let secret = try? loadCachedSecret(for: serverID)
            let sshClient = sshClient(for: serverID)
            let sftpClient = sftpClient(for: serverID)
            let appModel = self

            await sshClient.setOutputHandler { [appModel, serverID] output in
                await MainActor.run {
                    appModel.writeTerminal(output, for: serverID)
                }
            }

            try await sshClient.connect(profile: profile, secret: secret)
            try await sftpClient.connect(profile: profile, secret: secret)
            let files = try await sftpClient.listDirectory(path: "/")

            updateSession(for: serverID) { session in
                session.connectionState = .connected(profile.displayName)
                session.statusMessage = "Connected to \(profile.displayName)"
                session.remotePath = "/"
                session.remoteFiles = files
            }
        } catch {
            updateSession(for: serverID) { session in
                session.connectionState = .failed(error.localizedDescription)
                session.statusMessage = "Connection failed"
            }
            writeTerminal("Connection failed: \(error.localizedDescription)\r\n", for: serverID)
        }
    }

    func disconnect() async {
        guard let serverID = selectedServerID else { return }
        await disconnectServer(serverID)
    }

    private func disconnectServer(_ serverID: ServerProfile.ID) async {
        let sshClient = sshClients[serverID]
        let sftpClient = sftpClients[serverID]

        await sshClient?.disconnect()
        await sshClient?.setOutputHandler(nil)
        await sftpClient?.disconnect()

        updateSession(for: serverID) { session in
            session.connectionState = .disconnected
            session.statusMessage = "Disconnected"
            session.remoteFiles = []
        }
        writeTerminal("\r\nSession closed.\r\n", for: serverID)
    }

    func sendTerminalDraft() async {
    }

    func sendTerminalInput(_ text: String) async {
        guard let serverID = selectedServerID else { return }
        guard connectionState(for: serverID).isConnected else {
            writeTerminal("Not connected. Double-click a server to connect.\r\n", for: serverID)
            return
        }

        do {
            try await sshClient(for: serverID).sendRaw(text)
        } catch {
            writeTerminal("\r\n\(error.localizedDescription)\r\n", for: serverID)
        }
    }

    func resizeTerminal(columns: Int, rows: Int) async {
        guard let serverID = selectedServerID else { return }
        await sshClient(for: serverID).resize(columns: columns, rows: rows)
    }

    func insertTerminalText(_ text: String) {
    }

    func deleteBackwardInTerminal() {
    }

    func refreshRemoteDirectory() async {
        guard let serverID = selectedServerID else { return }
        await refreshRemoteDirectory(for: serverID)
    }

    func prepareFileTransferWorkspace() async {
        refreshLocalDirectory()

        guard let serverID = selectedServerID else {
            generalStatusMessage = "Select a server to browse remote files"
            return
        }

        if !connectionState(for: serverID).isConnected {
            updateSession(for: serverID) { session in
                session.remoteFiles = []
                if session.remotePath.isEmpty {
                    session.remotePath = "/"
                }
                session.statusMessage = "Connect to browse remote files"
            }
            return
        }

        if sessionSnapshot(for: serverID).remotePath.isEmpty {
            updateSession(for: serverID) { $0.remotePath = "/" }
        }
        await refreshRemoteDirectory(for: serverID)
    }

    func refreshLocalDirectory() {
        do {
            localFiles = try LocalFile.listDirectory(at: localPath)
            localDirectoryError = nil
            setStatus("Refreshed \(localPath.path)")
        } catch {
            localFiles = []
            localDirectoryError = error.localizedDescription
            setStatus(error.localizedDescription)
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
            setStatus("Local folder does not exist: \(path)")
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

    func openRemoteFile(_ file: RemoteFile) async {
        guard let serverID = selectedServerID else { return }
        guard file.kind == .directory else { return }

        if file.name == ".." {
            await goUpRemoteDirectory()
            return
        }

        let nextPath = sessionSnapshot(for: serverID).remotePath.appendingPathComponent(file.name)
        updateSession(for: serverID) { $0.remotePath = nextPath }
        await refreshRemoteDirectory(for: serverID)
    }

    func openRemotePath(_ path: String) async {
        guard let serverID = selectedServerID else { return }
        guard connectionState(for: serverID).isConnected else {
            setStatus("Connect to browse remote files", for: serverID)
            return
        }

        let previousPath = sessionSnapshot(for: serverID).remotePath
        let nextPath = path.normalizedRemoteDirectoryPath
        updateSession(for: serverID) { $0.remotePath = nextPath }

        do {
            let files = try await sftpClient(for: serverID).listDirectory(path: nextPath)
            updateSession(for: serverID) { session in
                session.remoteFiles = files
                session.statusMessage = "Refreshed \(nextPath)"
            }
        } catch {
            updateSession(for: serverID) { session in
                session.remotePath = previousPath
                session.statusMessage = error.localizedDescription
            }
        }
    }

    func goUpRemoteDirectory() async {
        guard let serverID = selectedServerID else { return }
        let currentPath = sessionSnapshot(for: serverID).remotePath
        guard currentPath != "/" else { return }
        updateSession(for: serverID) { $0.remotePath = currentPath.deletingLastPathComponent }
        await refreshRemoteDirectory(for: serverID)
    }

    func queueUpload(_ file: LocalFile?, remoteName: String? = nil) {
        guard let file, let serverID = selectedServerID else { return }
        queueUpload(
            file,
            serverID: serverID,
            remoteDirectory: sessionSnapshot(for: serverID).remotePath,
            remoteName: remoteName
        )
    }

    func queueUpload(
        _ file: LocalFile?,
        serverID: ServerProfile.ID,
        remoteDirectory: String,
        remoteName: String? = nil
    ) {
        guard let file else { return }
        let destinationName = remoteName ?? file.name
        let remoteFilePath = remoteDirectory.appendingPathComponent(destinationName)
        let totalBytes = LocalFile.totalBytes(at: file.url)
        let job = TransferJob(
            direction: .upload,
            filename: destinationName,
            sourcePath: file.url.path,
            destinationPath: remoteFilePath,
            totalBytes: totalBytes,
            status: .queued
        )

        transferStore.enqueue(job)
        pendingTransfers[job.id] = .upload(
            serverID: serverID,
            localURL: file.url,
            remotePath: remoteFilePath,
            filename: destinationName
        )
        setStatus("Queued upload \(destinationName)", for: serverID)
        startNextTransferIfNeeded()
    }

    func queueDownload(_ file: RemoteFile?, localName: String? = nil) {
        guard let file, file.name != "..", let serverID = selectedServerID else { return }
        queueDownload(
            file,
            serverID: serverID,
            remoteDirectory: sessionSnapshot(for: serverID).remotePath,
            localDirectory: localPath,
            localName: localName
        )
    }

    func queueDownload(
        _ file: RemoteFile?,
        serverID: ServerProfile.ID,
        remoteDirectory: String,
        localDirectory: URL,
        localName: String? = nil
    ) {
        guard let file, file.name != ".." else { return }
        let destinationName = localName ?? file.name
        let remoteFilePath = remoteDirectory.appendingPathComponent(file.name)
        let localURL = localDirectory.appending(path: destinationName)
        let job = TransferJob(
            direction: .download,
            filename: destinationName,
            sourcePath: remoteFilePath,
            destinationPath: localURL.path,
            totalBytes: file.size,
            status: .queued
        )

        transferStore.enqueue(job)
        pendingTransfers[job.id] = .download(
            serverID: serverID,
            remotePath: remoteFilePath,
            localURL: localURL,
            filename: destinationName
        )
        setStatus("Queued download \(destinationName)", for: serverID)
        startNextTransferIfNeeded()
    }

    func noteTransferSkipped(_ filename: String) {
        setStatus("Skipped \(filename)")
    }

    func cancelTransfer(_ jobID: TransferJob.ID) {
        if let task = runningTransferTasks[jobID] {
            transferStore.markCancelled(jobID)
            task.cancel()
            setStatus("Cancelling transfer...")
            return
        }

        if let work = pendingTransfers.removeValue(forKey: jobID) {
            transferStore.markCancelled(jobID)
            setStatus("Cancelled \(work.filename)", for: work.serverID)
            startNextTransferIfNeeded()
        }
    }

    private func refreshRemoteDirectory(for serverID: ServerProfile.ID) async {
        let path = sessionSnapshot(for: serverID).remotePath
        do {
            let files = try await sftpClient(for: serverID).listDirectory(path: path)
            updateSession(for: serverID) { session in
                session.remoteFiles = files
                session.statusMessage = "Refreshed \(path)"
            }
        } catch {
            setStatus(error.localizedDescription, for: serverID)
        }
    }

    private func startNextTransferIfNeeded() {
        while runningTransferTasks.count < maxConcurrentTransferLimit {
            guard let job = transferStore.nextQueuedJob(), let work = pendingTransfers[job.id] else {
                return
            }

            transferStore.markRunning(job.id)
            setStatus("\(workStatusVerb(work)) \(work.filename)...", for: work.serverID)

            let task = Task { @MainActor in
                await runTransfer(jobID: job.id, work: work)
            }
            runningTransferTasks[job.id] = task
        }
    }

    private var maxConcurrentTransferLimit: Int {
        let storedValue = UserDefaults.standard.integer(forKey: HostDeckPreferenceKeys.maxConcurrentTransfers)
        let value = storedValue == 0 ? HostDeckPreferenceDefaults.maxConcurrentTransfers : storedValue
        return min(max(value, 1), 8)
    }

    private func runTransfer(jobID: TransferJob.ID, work: TransferWork) async {
        defer {
            pendingTransfers.removeValue(forKey: jobID)
            runningTransferTasks.removeValue(forKey: jobID)
            startNextTransferIfNeeded()
        }

        do {
            let sftpClient = try await connectedTransferClient(for: work.serverID)
            defer {
                Task {
                    await sftpClient.disconnect()
                }
            }

            switch work {
            case .upload(_, let localURL, let remotePath, let filename):
                try await sftpClient.upload(
                    localURL: localURL,
                    remotePath: remotePath,
                    shouldCancel: { Task.isCancelled }
                ) { sent, total in
                    await MainActor.run {
                        self.transferStore.updateProgress(jobID, transferredBytes: sent, totalBytes: total)
                    }
                }
                transferStore.markCompleted(jobID)
                setStatus("Uploaded \(filename)", for: work.serverID)
                await refreshRemoteDirectory(for: work.serverID)

            case .download(_, let remotePath, let localURL, let filename):
                try await sftpClient.download(
                    remotePath: remotePath,
                    localURL: localURL,
                    shouldCancel: { Task.isCancelled }
                ) { received, total in
                    await MainActor.run {
                        self.transferStore.updateProgress(jobID, transferredBytes: received, totalBytes: total)
                    }
                }
                transferStore.markCompleted(jobID)
                setStatus("Downloaded \(filename)", for: work.serverID)
                refreshLocalDirectory()
            }
        } catch is CancellationError {
            transferStore.markCancelled(jobID)
            setStatus("Cancelled \(work.filename)", for: work.serverID)
        } catch {
            transferStore.markFailed(jobID, message: error.localizedDescription)
            setStatus(error.localizedDescription, for: work.serverID)
        }
    }

    private func connectedTransferClient(for serverID: ServerProfile.ID) async throws -> SFTPClient {
        guard let profile = profileStore.profiles.first(where: { $0.id == serverID }) else {
            throw SSHClientError.notConnected
        }

        let secret = try? loadCachedSecret(for: serverID)
        let client = makeSFTPClient()
        try await client.connect(profile: profile, secret: secret)
        return client
    }

    private func loadCachedSecret(for serverID: ServerProfile.ID) throws -> CredentialSecret? {
        if let secret = credentialCache[serverID] {
            return secret
        }

        if !didAttemptCredentialMigration {
            didAttemptCredentialMigration = true
            let accountIDs = profileStore.profiles.map { $0.id.uuidString }
            if let migrated = try? keychainStore.migrateLegacySecrets(for: accountIDs) {
                for (account, secret) in migrated {
                    if let id = UUID(uuidString: account) {
                        credentialCache[id] = secret
                    }
                }
            }
        }

        let secret = try keychainStore.loadSecret(for: serverID.uuidString)
        if let secret {
            credentialCache[serverID] = secret
        }
        return secret
    }

    private func workStatusVerb(_ work: TransferWork) -> String {
        switch work {
        case .upload:
            "Uploading"
        case .download:
            "Downloading"
        }
    }

    private func appendTerminal(_ line: TerminalLine, for serverID: ServerProfile.ID) {
        updateSession(for: serverID) { session in
            session.terminalBuffer.append(line)
            if session.terminalBuffer.count > 300 {
                session.terminalBuffer.removeFirst(session.terminalBuffer.count - 300)
            }
        }
    }

    private func writeTerminal(_ text: String, for serverID: ServerProfile.ID) {
        updateSession(for: serverID) { session in
            session.terminalEvents.append(TerminalEvent(kind: .write, data: text))
            if session.terminalEvents.count > 1_000 {
                session.terminalEvents.removeFirst(session.terminalEvents.count - 1_000)
            }
        }
    }

    private func resetTerminal(for serverID: ServerProfile.ID) {
        updateSession(for: serverID) { session in
            session.terminalEvents.append(TerminalEvent(kind: .reset))
        }
    }

    private func setStatus(_ message: String, for serverID: ServerProfile.ID? = nil) {
        if let serverID {
            updateSession(for: serverID) { $0.statusMessage = message }
        } else if let selectedServerID {
            updateSession(for: selectedServerID) { $0.statusMessage = message }
        } else {
            generalStatusMessage = message
        }
    }

    @discardableResult
    private func ensureSession(for serverID: ServerProfile.ID) -> ServerRuntimeSession {
        if let session = sessions[serverID] {
            return session
        }

        let session = ServerRuntimeSession.fresh()
        sessions[serverID] = session
        return session
    }

    private func sessionSnapshot(for serverID: ServerProfile.ID) -> ServerRuntimeSession {
        sessions[serverID] ?? ServerRuntimeSession.fresh()
    }

    private func updateSession(for serverID: ServerProfile.ID, _ update: (inout ServerRuntimeSession) -> Void) {
        var session = sessions[serverID] ?? ServerRuntimeSession.fresh()
        update(&session)
        sessions[serverID] = session
    }

    private func sshClient(for serverID: ServerProfile.ID) -> SSHClient {
        if let client = sshClients[serverID] {
            return client
        }

        let client = makeSSHClient()
        sshClients[serverID] = client
        return client
    }

    private func sftpClient(for serverID: ServerProfile.ID) -> SFTPClient {
        if let client = sftpClients[serverID] {
            return client
        }

        let client = makeSFTPClient()
        sftpClients[serverID] = client
        return client
    }
}
