import Foundation

struct LocalFile: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var name: String
    var kind: RemoteFile.Kind
    var size: Int64
    var modifiedAt: Date

    static func listDirectory(at url: URL) throws -> [LocalFile] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedNameKey
        ]

        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { fileURL in
            guard let values = try? fileURL.resourceValues(forKeys: keys) else { return nil }
            let kind: RemoteFile.Kind
            if values.isSymbolicLink == true {
                kind = .symlink
            } else if values.isDirectory == true {
                kind = .directory
            } else {
                kind = .file
            }

            return LocalFile(
                url: fileURL,
                name: values.localizedName ?? fileURL.lastPathComponent,
                kind: kind,
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
        .sorted { lhs, rhs in
            if lhs.kind == .directory && rhs.kind != .directory { return true }
            if lhs.kind != .directory && rhs.kind == .directory { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func totalBytes(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }

        if values.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else {
                return 0
            }

            return enumerator.compactMap { item -> Int64? in
                guard let fileURL = item as? URL,
                      let fileValues = try? fileURL.resourceValues(forKeys: keys),
                      fileValues.isDirectory != true else {
                    return nil
                }
                return Int64(fileValues.fileSize ?? 0)
            }
            .reduce(0, +)
        }

        return Int64(values.fileSize ?? 0)
    }
}
