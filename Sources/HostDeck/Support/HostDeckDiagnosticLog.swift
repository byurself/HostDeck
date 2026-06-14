import Foundation

enum HostDeckDiagnosticLog {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library")
        .appending(path: "Logs")
        .appending(path: "HostDeck")
        .appending(path: "diagnostic.log")

    private static let lock = NSLock()

    static func write(category: String, _ message: String) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let line = "\(timestamp()) pid=\(ProcessInfo.processInfo.processIdentifier) main=\(Thread.isMainThread) [\(category)] \(message)\n"
            let data = Data(line.utf8)

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Diagnostics must never affect app behavior.
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
