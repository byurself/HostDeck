import Foundation

extension String {
    func appendingPathComponent(_ component: String) -> String {
        guard component != ".." else { return deletingLastPathComponent }
        guard self != "/" else { return "/" + component }
        return (self as NSString).appendingPathComponent(component)
    }

    var deletingLastPathComponent: String {
        let value = (self as NSString).deletingLastPathComponent
        return value.isEmpty ? "/" : value
    }

    var normalizedRemoteDirectoryPath: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }

        let absolute = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        let normalized = (absolute as NSString).standardizingPath
        return normalized.isEmpty ? "/" : normalized
    }

    var expandingTildeInPath: String {
        if self == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }

        if hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appending(path: String(dropFirst(2)))
                .path
        }

        return self
    }
}
