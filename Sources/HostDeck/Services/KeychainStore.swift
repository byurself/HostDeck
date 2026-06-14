import Foundation
import os
import Security

struct KeychainStore {
    private let service = "com.hostdeck.credentials"
    private let activeService = "com.hostdeck.credentials.servers"
    private let bundledCredentialsAccount = "__hostdeck_credentials_v2__"
    private static let cacheLock = NSLock()
    private static var cachedBundledSecrets: [String: CredentialSecret]?
    private static var didAttemptBundledSecretLoad = false

    func save(_ secret: CredentialSecret, for account: String) throws {
        try saveActiveSecret(secret, for: account)
        if var cachedSecrets = cachedBundledSecrets() {
            cachedSecrets[account] = secret
            cacheBundledSecrets(cachedSecrets)
        }
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
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        KeychainTrace.log("migrateLegacySecrets copyMatching attributes begin")
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        KeychainTrace.log("migrateLegacySecrets copyMatching attributes status \(status)")
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        let items = result as? [[String: Any]] ?? []
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  accountSet.contains(account),
                  account != bundledCredentialsAccount,
                  let secret = try? loadLegacySecret(for: account) else {
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
            cacheBundledSecrets(bundled)

            for account in migrated.keys {
                try? deleteKeychainItem(for: account)
            }
        }

        return migrated
    }

    func loadSecrets(for accounts: [String]) throws -> [String: CredentialSecret] {
        let accountSet = Set(accounts)
        guard !accountSet.isEmpty, let bundledSecrets = try loadBundledSecrets() else { return [:] }

        return bundledSecrets.filter { account, _ in
            accountSet.contains(account)
        }
    }

    func loadSecretsMigratingLegacyItems(for accounts: [String]) throws -> [String: CredentialSecret] {
        let accountSet = Set(accounts)
        guard !accountSet.isEmpty else { return [:] }

        var secrets: [String: CredentialSecret] = [:]
        for account in accountSet {
            if let secret = try loadActiveSecret(for: account) {
                secrets[account] = secret
            }
        }

        let missingAccounts = accountSet.subtracting(secrets.keys)
        guard !missingAccounts.isEmpty else {
            return secrets
        }

        if let bundledSecrets = try loadBundledSecrets() {
            for account in missingAccounts {
                if let secret = bundledSecrets[account] {
                    secrets[account] = secret
                    try? saveActiveSecret(secret, for: account)
                }
            }
            return secrets
        }

        let legacySecrets = try loadLegacySecrets(for: missingAccounts)
        if !legacySecrets.isEmpty {
            for (account, secret) in legacySecrets {
                secrets[account] = secret
                try? saveActiveSecret(secret, for: account)
            }
        }

        return secrets
    }

    func loadSecret(for account: String) throws -> CredentialSecret? {
        if let secret = try loadActiveSecret(for: account) {
            return secret
        }

        if let secret = try loadBundledSecrets()?[account] {
            try? saveActiveSecret(secret, for: account)
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
            cacheBundledSecrets(secrets)
        }

        try deleteActiveSecret(for: account)
        try deleteKeychainItem(for: account)
    }

    private func saveActiveSecret(_ secret: CredentialSecret, for account: String) throws {
        try saveSecret(secret, for: account, serviceName: activeService, traceName: "saveActiveSecret")
    }

    private func loadActiveSecret(for account: String) throws -> CredentialSecret? {
        try loadSecret(for: account, serviceName: activeService, traceName: "loadActiveSecret")
    }

    private func deleteActiveSecret(for account: String) throws {
        try deleteSecret(for: account, serviceName: activeService, traceName: "deleteActiveSecret")
    }

    private func saveSecret(_ secret: CredentialSecret, for account: String, serviceName: String, traceName: String) throws {
        let data = try JSONEncoder.hostDeck.encode(secret)
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        KeychainTrace.log("\(traceName) update begin")
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        KeychainTrace.log("\(traceName) update status \(updateStatus)")
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        KeychainTrace.log("\(traceName) add begin")
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        KeychainTrace.log("\(traceName) add status \(status)")
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func loadSecret(for account: String, serviceName: String, traceName: String) throws -> CredentialSecret? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        KeychainTrace.log("\(traceName) copyMatching data begin")
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        KeychainTrace.log("\(traceName) copyMatching data status \(status)")
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }

        return try JSONDecoder.hostDeck.decode(CredentialSecret.self, from: data)
    }

    private func deleteSecret(for account: String, serviceName: String, traceName: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        KeychainTrace.log("\(traceName) begin")
        let status = SecItemDelete(query as CFDictionary)
        KeychainTrace.log("\(traceName) status \(status)")
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
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

        KeychainTrace.log("saveBundledSecrets update begin")
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        KeychainTrace.log("saveBundledSecrets update status \(updateStatus)")
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

        KeychainTrace.log("saveBundledSecrets add begin")
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        KeychainTrace.log("saveBundledSecrets add status \(status)")
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func loadBundledSecrets() throws -> [String: CredentialSecret]? {
        if let cachedSecrets = cachedBundledSecrets() {
            KeychainTrace.log("loadBundledSecrets memory cache hit")
            return cachedSecrets
        }

        if didAttemptCachedBundledSecretLoad() {
            KeychainTrace.log("loadBundledSecrets memory cache miss after prior attempt")
            return nil
        }

        markDidAttemptBundledSecretLoad()
        KeychainTrace.log("loadBundledSecrets copyMatching data begin")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: bundledCredentialsAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        KeychainTrace.log("loadBundledSecrets copyMatching data status \(status)")
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }

        let secrets = try JSONDecoder.hostDeck.decode([String: CredentialSecret].self, from: data)
        cacheBundledSecrets(secrets)
        return secrets
    }

    private func cachedBundledSecrets() -> [String: CredentialSecret]? {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        return Self.cachedBundledSecrets
    }

    private func didAttemptCachedBundledSecretLoad() -> Bool {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        return Self.didAttemptBundledSecretLoad
    }

    private func markDidAttemptBundledSecretLoad() {
        Self.cacheLock.lock()
        Self.didAttemptBundledSecretLoad = true
        Self.cacheLock.unlock()
    }

    private func cacheBundledSecrets(_ secrets: [String: CredentialSecret]) {
        Self.cacheLock.lock()
        Self.cachedBundledSecrets = secrets
        Self.didAttemptBundledSecretLoad = true
        Self.cacheLock.unlock()
    }

    private func loadLegacySecrets(for accounts: Set<String>) throws -> [String: CredentialSecret] {
        guard !accounts.isEmpty else { return [:] }

        var legacySecrets: [String: CredentialSecret] = [:]
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        KeychainTrace.log("loadLegacySecrets copyMatching attributes begin")
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        KeychainTrace.log("loadLegacySecrets copyMatching attributes status \(status)")
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        let items = result as? [[String: Any]] ?? []
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  accounts.contains(account),
                  account != bundledCredentialsAccount,
                  let secret = try? loadLegacySecret(for: account) else {
                continue
            }
            legacySecrets[account] = secret
        }

        return legacySecrets
    }

    private func loadLegacySecret(for account: String) throws -> CredentialSecret? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        KeychainTrace.log("loadLegacySecret copyMatching data begin")
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        KeychainTrace.log("loadLegacySecret copyMatching data status \(status)")
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

        KeychainTrace.log("deleteKeychainItem begin")
        let status = SecItemDelete(query as CFDictionary)
        KeychainTrace.log("deleteKeychainItem status \(status)")
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

private enum KeychainTrace {
    private static let logger = Logger(subsystem: "com.hostdeck.app", category: "Keychain")

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
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
