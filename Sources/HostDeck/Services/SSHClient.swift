import Foundation

protocol SSHClient: Sendable {
    func connect(profile: ServerProfile, secret: CredentialSecret?) async throws
    func disconnect() async
    func send(command: String) async throws -> String
    func sendRaw(_ text: String) async throws
    func resize(columns: Int, rows: Int) async
    func setOutputHandler(_ handler: (@Sendable (String) async -> Void)?) async
}

actor MockSSHClient: SSHClient {
    private var connectedProfile: ServerProfile?

    func connect(profile: ServerProfile, secret: CredentialSecret?) async throws {
        try await Task.sleep(for: .milliseconds(360))
        connectedProfile = profile
    }

    func disconnect() async {
        connectedProfile = nil
    }

    func send(command: String) async throws -> String {
        guard let profile = connectedProfile else {
            throw SSHClientError.notConnected
        }

        try await Task.sleep(for: .milliseconds(160))
        switch command {
        case "pwd":
            return profile.defaultPath
        case "whoami":
            return profile.username
        case "ls", "ll":
            return "releases\nshared\napp.log\ndeploy.yml"
        case "hostname":
            return profile.host
        default:
            return "mock: \(command)\n\nThe SSH client boundary is ready for libssh2 channel execution and PTY streaming."
        }
    }

    func sendRaw(_ text: String) async throws {}

    func resize(columns: Int, rows: Int) async {}

    func setOutputHandler(_ handler: (@Sendable (String) async -> Void)?) async {}
}

enum SSHClientError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "No SSH session is connected."
        }
    }
}
