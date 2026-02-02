import Foundation
import os.log

/// Stores and retrieves OAuth tokens from a JSON file.
/// This enables the MCP CLI tool to access tokens without Keychain sharing.
final class FileTokenStorage: @unchecked Sendable {

    /// Shared singleton instance
    static let shared = FileTokenStorage()

    /// Lock for thread-safe file access
    private let lock = NSLock()

    /// File URL for token storage
    private let fileURL: URL

    private init() {
        self.fileURL = MCPConfiguration.tokensFileURL
    }

    /// Creates a FileTokenStorage with a custom file URL (for testing).
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Token Storage

    /// Token data stored in the JSON file.
    struct StoredToken: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let scope: String
    }

    /// Saves tokens for an account.
    /// - Parameters:
    ///   - tokens: The tokens to save
    ///   - accountEmail: The account email
    func saveTokens(_ tokens: OAuthTokens, for accountEmail: String) throws {
        lock.lock()
        defer { lock.unlock() }

        // Load existing tokens
        var allTokens = loadAllTokens()

        // Add/update tokens for this account
        allTokens[accountEmail] = StoredToken(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt,
            scope: tokens.scope
        )

        // Write back to file
        try writeTokens(allTokens)

        Logger.auth.debug("Saved tokens to file for: \(accountEmail, privacy: .private(mask: .hash))")
    }

    /// Retrieves tokens for an account.
    /// - Parameter accountEmail: The account email
    /// - Returns: The stored tokens
    /// - Throws: If tokens are not found
    func getTokens(for accountEmail: String) throws -> OAuthTokens {
        lock.lock()
        defer { lock.unlock() }

        let allTokens = loadAllTokens()

        guard let stored = allTokens[accountEmail] else {
            throw MCPError.authenticationRequired(accountEmail)
        }

        return OAuthTokens(
            accessToken: stored.accessToken,
            refreshToken: stored.refreshToken,
            expiresAt: stored.expiresAt,
            scope: stored.scope
        )
    }

    /// Deletes tokens for an account.
    /// - Parameter accountEmail: The account email
    func deleteTokens(for accountEmail: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var allTokens = loadAllTokens()
        allTokens.removeValue(forKey: accountEmail)
        try writeTokens(allTokens)

        Logger.auth.debug("Deleted tokens from file for: \(accountEmail, privacy: .private(mask: .hash))")
    }

    /// Checks if tokens exist for an account.
    /// - Parameter accountEmail: The account email
    /// - Returns: True if tokens exist
    func hasTokens(for accountEmail: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let allTokens = loadAllTokens()
        return allTokens[accountEmail] != nil
    }

    /// Lists all account emails with stored tokens.
    /// - Returns: Array of account emails
    func listAccounts() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let allTokens = loadAllTokens()
        return Array(allTokens.keys)
    }

    // MARK: - Private

    private func loadAllTokens() -> [String: StoredToken] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([String: StoredToken].self, from: data)
        } catch {
            Logger.auth.error("Failed to load tokens file: \(error.localizedDescription)")
            return [:]
        }
    }

    private func writeTokens(_ tokens: [String: StoredToken]) throws {
        // Ensure directory exists
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // Encode and write
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(tokens)
        try data.write(to: fileURL, options: .atomic)

        // Set restrictive permissions (owner read/write only)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
