import Foundation
import Security

struct KeychainStore {
    private let service = "com.hostdeck.credentials"
    private let bundledCredentialsAccount = "__hostdeck_credentials_v2__"

    func save(_ secret: CredentialSecret, for account: String) throws {
        var secrets = try loadBundledSecrets() ?? [:]
        secrets[account] = secret
        try saveBundledSecrets(secrets)
        try? deleteKeychainItem(for: account)
    }

    func migrateLegacySecrets(for accounts: [String]) throws -> [String: CredentialSecret] {
        let accountSet = Set(accounts)
        guard !accountSet.isEmpty else { return [:] }

        var migrated: [String: CredentialSecret] = [:]
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        let items = result as? [[String: Any]] ?? []
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  accountSet.contains(account),
                  account != bundledCredentialsAccount,
                  let data = item[kSecValueData as String] as? Data,
                  let secret = try? JSONDecoder.hostDeck.decode(CredentialSecret.self, from: data) else {
                continue
            }
            migrated[account] = secret
        }

        if !migrated.isEmpty {
            var bundled = try loadBundledSecrets() ?? [:]
            for (account, secret) in migrated {
                bundled[account] = secret
            }
            try saveBundledSecrets(bundled)

            for account in migrated.keys {
                try? deleteKeychainItem(for: account)
            }
        }

        return migrated
    }

    func loadSecret(for account: String) throws -> CredentialSecret? {
        if let secret = try loadBundledSecrets()?[account] {
            return secret
        }

        guard let legacySecret = try loadLegacySecret(for: account) else {
            return nil
        }

        try save(legacySecret, for: account)
        return legacySecret
    }

    func deleteSecret(for account: String) throws {
        if var secrets = try loadBundledSecrets(), secrets.removeValue(forKey: account) != nil {
            try saveBundledSecrets(secrets)
        }

        try deleteKeychainItem(for: account)
    }

    private func saveBundledSecrets(_ secrets: [String: CredentialSecret]) throws {
        let data = try JSONEncoder.hostDeck.encode(secrets)
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: bundledCredentialsAccount
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: bundledCredentialsAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func loadBundledSecrets() throws -> [String: CredentialSecret]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: bundledCredentialsAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }

        return try JSONDecoder.hostDeck.decode([String: CredentialSecret].self, from: data)
    }

    private func loadLegacySecret(for account: String) throws -> CredentialSecret? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }

        return try JSONDecoder.hostDeck.decode(CredentialSecret.self, from: data)
    }

    private func deleteKeychainItem(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            "Keychain returned status \(status)."
        }
    }
}
