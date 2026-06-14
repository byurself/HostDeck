import Foundation

enum AppInfo {
    static let name = "HostDeck"
    static let fallbackVersion = "0.1.0"
    static let fallbackBuild = "1"
    static let tagline = "A focused macOS workspace for SSH terminals and SFTP file management."
    static let copyright = "Copyright © 2026 byu_rself. Released under the MIT License."
    static let repositoryPath = "byurself/HostDeck"

    static var repositoryURL: URL {
        URL(string: "https://github.com/\(repositoryPath)")!
    }

    static var releasesURL: URL {
        URL(string: "https://github.com/\(repositoryPath)/releases/latest")!
    }

    static var documentationURL: URL {
        URL(string: "https://github.com/\(repositoryPath)#readme")!
    }

    static var licenseURL: URL {
        URL(string: "https://github.com/\(repositoryPath)/blob/main/LICENSE")!
    }

    static var newIssueURL: URL {
        var components = URLComponents(string: "https://github.com/\(repositoryPath)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: "HostDeck issue report"),
            URLQueryItem(
                name: "body",
                value: """
                ## Summary

                ## Steps to Reproduce

                ## Expected Behavior

                ## Actual Behavior

                ## Environment
                - HostDeck \(version) (\(build))
                - macOS:
                """
            )
        ]
        return components.url!
    }

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
