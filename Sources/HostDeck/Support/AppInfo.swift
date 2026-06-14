import Foundation

enum AppInfo {
    static let name = "HostDeck"
    static let fallbackVersion = "0.1.0"
    static let fallbackBuild = "1"
    static let tagline = "A focused macOS workspace for SSH terminals and SFTP file management."
    static let copyright = "Copyright © 2026 byu_rself. Released under the MIT License."

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? fallbackBuild
    }

    static var logsDirectory: URL {
        FileManager.default.applicationSupportDirectory
            .appending(path: "Logs", directoryHint: .isDirectory)
    }
}
