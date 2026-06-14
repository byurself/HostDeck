import Foundation

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey
    case agent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .password:
            "Password"
        case .privateKey:
            "Private Key"
        case .agent:
            "SSH Agent"
        }
    }
}

enum CredentialSecret: Codable, Equatable {
    case password(String)
    case privateKey(passphrase: String?)
}
