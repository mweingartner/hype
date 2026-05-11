import Foundation
import Security

// MARK: - KeychainStore

/// Errors thrown by `KeychainStore` operations.
public enum KeychainStoreError: Error, Sendable {
    case unhandledStatus(OSStatus)
    case itemNotFound
    case encodingFailed
}

/// A thin, type-safe wrapper around `SecItem*` for storing user-provided API keys.
///
/// All items are stored under `kSecClassGenericPassword` with the service
/// identifier `"com.hype.webAssets"` and accessibility class
/// `kSecAttrAccessibleWhenUnlocked`. The `WhenUnlocked` accessibility class
/// is the tightest class that still supports silent reads while the device
/// is unlocked — required because provider keys are read automatically for
/// user-initiated AI and asset-search requests without prompting each time.
public enum KeychainStore {

    /// Keychain service identifier shared by all web-asset keys.
    public static let service = "com.hype.webAssets"

    /// Store or update a secret string in the Keychain.
    ///
    /// - Parameters:
    ///   - value: The secret string to store as UTF-8 data.
    ///   - account: The account identifier (key name) within this service.
    /// - Throws: `KeychainStoreError.encodingFailed` if the value cannot be
    ///   UTF-8 encoded, or `KeychainStoreError.unhandledStatus` for any
    ///   unexpected Keychain status.
    public static func setSecret(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainStoreError.encodingFailed
        }

        // Try updating an existing item first.
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String:         data,
            kSecAttrAccessible as String:    kSecAttrAccessibleWhenUnlocked,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist — add it.
            var addQuery: [String: Any] = query
            addQuery[kSecValueData as String]      = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainStoreError.unhandledStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainStoreError.unhandledStatus(updateStatus)
        }
    }

    /// Retrieve a secret string from the Keychain.
    ///
    /// - Parameter account: The account identifier to look up.
    /// - Returns: The stored secret string.
    /// - Throws: `KeychainStoreError.itemNotFound` if no item exists for the
    ///   given account, or `KeychainStoreError.unhandledStatus` for unexpected
    ///   Keychain errors.
    public static func getSecret(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw KeychainStoreError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.encodingFailed
        }
        return string
    }

    /// Delete a secret from the Keychain.
    ///
    /// - Parameter account: The account identifier to delete.
    /// - Throws: `KeychainStoreError.itemNotFound` if no item exists,
    ///   or `KeychainStoreError.unhandledStatus` for unexpected errors.
    public static func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound {
            throw KeychainStoreError.itemNotFound
        }
        if status != errSecSuccess {
            throw KeychainStoreError.unhandledStatus(status)
        }
    }

    /// Returns `true` when a secret exists in the Keychain for the given account.
    /// Performs a silent check — no throws; errors map to `false`.
    public static func hasSecret(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

// MARK: - Well-known accounts

public extension KeychainStore {
    /// Account identifier for the Pexels API key.
    static let pexelsAPIKeyAccount = "pexels.apiKey"

    /// Account identifier for the OpenAI API key.
    static let openAIAPIKeyAccount = "openai.apiKey"

    /// Account identifier for the Meshy.ai API key. Stored under the
    /// shared `KeychainStore.service` ("com.hype.webAssets") so it
    /// lives next to the existing AI-provider keys.
    static let meshyAPIKeyAccount = "meshy.apiKey"
}
