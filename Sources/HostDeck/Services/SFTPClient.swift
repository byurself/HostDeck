import Foundation

protocol SFTPClient: Sendable {
    func connect(profile: ServerProfile, secret: CredentialSecret?) async throws
    func disconnect() async
    func listDirectory(path: String) async throws -> [RemoteFile]
    func upload(
        localURL: URL,
        remotePath: String,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws
    func download(
        remotePath: String,
        localURL: URL,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws
}

actor MockSFTPClient: SFTPClient {
    private var connectedProfile: ServerProfile?

    func connect(profile: ServerProfile, secret: CredentialSecret?) async throws {
        try await Task.sleep(for: .milliseconds(280))
        connectedProfile = profile
    }

    func disconnect() async {
        connectedProfile = nil
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        try await Task.sleep(for: .milliseconds(180))
        guard connectedProfile != nil else {
            return []
        }

        if path == "/" {
            return [
                RemoteFile(name: "run", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-3_000), permissions: "rwxr-xr-x"),
                RemoteFile(name: "tmp", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-4_700), permissions: "rwxrwxrwt"),
                RemoteFile(name: "etc", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-86_000), permissions: "rwxr-xr-x"),
                RemoteFile(name: "home", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-140_000), permissions: "rwxr-xr-x"),
                RemoteFile(name: "var", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-152_000), permissions: "rwxr-xr-x"),
                RemoteFile(name: "usr", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-320_000), permissions: "rwxr-xr-x"),
                RemoteFile(name: "root", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-420_000), permissions: "rwx------"),
                RemoteFile(name: "swap.img", kind: .file, size: 2_080_000_000, modifiedAt: .now.addingTimeInterval(-520_000), permissions: "rw-------"),
                RemoteFile(name: "bin", kind: .symlink, size: 0, modifiedAt: .now.addingTimeInterval(-620_000), permissions: "rwxrwxrwx"),
                RemoteFile(name: "lib", kind: .symlink, size: 0, modifiedAt: .now.addingTimeInterval(-620_000), permissions: "rwxrwxrwx")
            ]
        }

        let suffix = path == "/" ? "root" : path.split(separator: "/").last.map(String.init) ?? "home"
        return [
            RemoteFile(name: "..", kind: .directory, size: 0, modifiedAt: .now, permissions: "drwxr-xr-x"),
            RemoteFile(name: "bin", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-42_000), permissions: "drwxr-xr-x"),
            RemoteFile(name: "config", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-12_000), permissions: "drwxr-xr-x"),
            RemoteFile(name: "\(suffix)-release.tar.gz", kind: .file, size: 24_180_400, modifiedAt: .now.addingTimeInterval(-560), permissions: "-rw-r--r--"),
            RemoteFile(name: "app.log", kind: .file, size: 820_118, modifiedAt: .now.addingTimeInterval(-90), permissions: "-rw-r--r--")
        ]
    }

    func upload(
        localURL: URL,
        remotePath: String,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws {
        if shouldCancel() { throw CancellationError() }
        let size = (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        await progress(size, size)
    }

    func download(
        remotePath: String,
        localURL: URL,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws {
        if shouldCancel() { throw CancellationError() }
        await progress(1, 1)
    }
}
