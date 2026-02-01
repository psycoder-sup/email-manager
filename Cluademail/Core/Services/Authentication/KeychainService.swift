import Foundation
import Security
import os.log

/// Service for securely storing and retrieving Codable items in the macOS Keychain.
/// Thread-safe using OSAllocatedUnfairLock for synchronization.
final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {

    /// Shared singleton instance
    static let shared = KeychainService()

    /// Service identifier used for all Keychain items
    private let serviceIdentifier = "com.cluademail.tokens"

    /// Lock for thread-safe access
    private let lock = NSLock()

    private init() {}

    // MARK: - Public Methods

    /// Saves a Codable item to the Keychain.
    /// Uses upsert behavior: deletes existing item before saving new one.
    /// - Parameters:
    ///   - item: The item to save
    ///   - key: The key to store the item under
    func save<T: Codable>(_ item: T, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        // Encode item to JSON
        let data: Data
        do {
            data = try JSONEncoder().encode(item)
        } catch {
            Logger.auth.error("Failed to encode item for Keychain: \(error.localizedDescription)")
            throw KeychainError.encodingError(error)
        }

        // Delete existing item first (upsert behavior) - silent mode ignores errors
        try? performDelete(forKey: key, silent: true)

        // Build query for new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Add item to Keychain
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Logger.auth.error("Keychain save failed with status: \(status)")

            if status == errSecDuplicateItem {
                throw KeychainError.duplicateItem
            }
            throw KeychainError.unexpectedStatus(status)
        }

        Logger.auth.debug("Successfully saved item to Keychain for key: \(key, privacy: .private(mask: .hash))")
    }

    /// Retrieves a Codable item from the Keychain.
    /// - Parameters:
    ///   - type: The type of item to retrieve
    ///   - key: The key the item is stored under
    /// - Returns: The retrieved and decoded item
    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        // Build query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Execute query
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                Logger.auth.debug("Keychain item not found for key: \(key, privacy: .private(mask: .hash))")
                throw KeychainError.itemNotFound
            }
            Logger.auth.error("Keychain retrieve failed with status: \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            Logger.auth.error("Keychain returned unexpected data type")
            throw KeychainError.unexpectedStatus(errSecInternalError)
        }

        // Decode item
        do {
            let item = try JSONDecoder().decode(type, from: data)
            Logger.auth.debug("Successfully retrieved item from Keychain for key: \(key, privacy: .private(mask: .hash))")
            return item
        } catch {
            Logger.auth.error("Failed to decode Keychain item: \(error.localizedDescription)")
            throw KeychainError.decodingError(error)
        }
    }

    /// Deletes an item from the Keychain.
    /// Does not throw if the item doesn't exist.
    /// - Parameter key: The key of the item to delete
    func delete(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try performDelete(forKey: key, silent: false)
    }

    // MARK: - Private Methods

    /// Performs the actual Keychain delete operation.
    /// - Parameters:
    ///   - key: The key of the item to delete
    ///   - silent: If true, silently ignores all errors (used for upsert behavior in save)
    private func performDelete(forKey key: String, silent: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Success or item not found are both acceptable
        if status == errSecSuccess {
            Logger.auth.debug("Deleted item from Keychain for key: \(key, privacy: .private(mask: .hash))")
            return
        }

        if status == errSecItemNotFound {
            return
        }

        // Unexpected error
        if silent {
            Logger.auth.warning("Keychain delete failed with status \(status), continuing with save")
            return
        }

        Logger.auth.error("Keychain delete failed with status: \(status)")
        throw KeychainError.unexpectedStatus(status)
    }
}
