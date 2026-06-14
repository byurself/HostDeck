import Foundation

protocol ConnectionTester: Sendable {
    func test(profile: ServerProfile, secret: CredentialSecret?) async -> ConnectionTestResult
}

struct ConnectionTestResult: Equatable {
    var isSuccess: Bool
    var message: String

    static func success(_ message: String) -> ConnectionTestResult {
        ConnectionTestResult(isSuccess: true, message: message)
    }

    static func failure(_ message: String) -> ConnectionTestResult {
        ConnectionTestResult(isSuccess: false, message: message)
    }
}

struct MockConnectionTester: ConnectionTester {
    func test(profile: ServerProfile, secret: CredentialSecret?) async -> ConnectionTestResult {
        let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return .failure("Host is required.")
        }

        guard (1...65_535).contains(profile.port) else {
            return .failure("Port must be between 1 and 65535.")
        }

        try? await Task.sleep(for: .milliseconds(700))

        if host.localizedCaseInsensitiveContains("fail") {
            return .failure("Unable to reach \(host):\(profile.port).")
        }

        return .success("Connection test passed for \(profile.username)@\(host):\(profile.port).")
    }
}

struct LibSSH2ConnectionTester: ConnectionTester {
    func test(profile: ServerProfile, secret: CredentialSecret?) async -> ConnectionTestResult {
        let client = LibSSH2SFTPClient()
        do {
            try await client.connect(profile: profile, secret: secret)
            _ = try await client.listDirectory(path: "/")
            await client.disconnect()
            return .success("Connected to \(profile.username)@\(profile.host):\(profile.port).")
        } catch {
            await client.disconnect()
            return .failure(error.localizedDescription)
        }
    }
}
