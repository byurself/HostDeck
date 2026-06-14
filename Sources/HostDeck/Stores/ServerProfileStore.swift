import Foundation
import Observation

@Observable
@MainActor
final class ServerProfileStore {
    private let fileURL: URL
    var profiles: [ServerProfile] = []

    init(fileURL: URL = FileManager.default.applicationSupportDirectory.appending(path: "servers.json")) {
        self.fileURL = fileURL
        load()
    }

    func upsert(_ profile: ServerProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        save()
    }

    func delete(id: ServerProfile.ID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            profiles = try JSONDecoder.hostDeck.decode([ServerProfile].self, from: data)
        } catch {
            profiles = ServerProfile.samples
            save()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.hostDeck.encode(profiles)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save server profiles: \(error)")
        }
    }
}
