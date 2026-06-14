import Foundation

extension FileManager {
    var applicationSupportDirectory: URL {
        let base = urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "HostDeck", directoryHint: .isDirectory)
    }
}
