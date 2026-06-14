import Foundation

struct ServerProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var privateKeyPath: String
    var defaultPath: String
    var tags: [String]
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .password,
        privateKeyPath: String = "",
        defaultPath: String = "/home/deploy",
        tags: [String] = [],
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.defaultPath = defaultPath
        self.tags = tags
        self.lastConnectedAt = lastConnectedAt
    }

    var displayName: String {
        name.isEmpty ? host : name
    }

    static let samples: [ServerProfile] = [
        ServerProfile(name: "Production", host: "prod.example.com", username: "deploy", tags: ["prod", "rails"]),
        ServerProfile(name: "Staging", host: "staging.example.com", username: "ubuntu", defaultPath: "/var/www/staging", tags: ["stage"]),
        ServerProfile(name: "Lab NAS", host: "192.168.1.42", username: "admin", authMethod: .password, privateKeyPath: "", defaultPath: "/volume1")
    ]
}
