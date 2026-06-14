import Foundation

struct RemoteFile: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case directory
        case file
        case symlink
    }

    var id: String { "\(kind.rawValue):\(name)" }
    var name: String
    var kind: Kind
    var size: Int64
    var modifiedAt: Date
    var permissions: String

    static let sampleDirectory: [RemoteFile] = [
        RemoteFile(name: "releases", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-8_600), permissions: "drwxr-xr-x"),
        RemoteFile(name: "shared", kind: .directory, size: 0, modifiedAt: .now.addingTimeInterval(-42_000), permissions: "drwxr-xr-x"),
        RemoteFile(name: "app.log", kind: .file, size: 1_280_340, modifiedAt: .now.addingTimeInterval(-260), permissions: "-rw-r--r--"),
        RemoteFile(name: "deploy.yml", kind: .file, size: 3_812, modifiedAt: .now.addingTimeInterval(-7_200), permissions: "-rw-r--r--"),
        RemoteFile(name: "current", kind: .symlink, size: 0, modifiedAt: .now.addingTimeInterval(-12_600), permissions: "lrwxr-xr-x")
    ]
}
