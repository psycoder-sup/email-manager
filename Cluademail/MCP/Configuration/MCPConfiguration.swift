import Foundation

/// Configuration for the MCP server.
enum MCPConfiguration {

    // MARK: - Paths

    /// Application Support directory
    static var applicationSupportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// SwiftData store URL (SwiftData uses default.store in Application Support)
    static var databaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("default.store")
    }

    /// Cluademail-specific directory for tokens and other files
    static var cluademailDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Cluademail")
    }

    /// OAuth tokens JSON file URL
    static var tokensFileURL: URL {
        cluademailDirectory.appendingPathComponent("tokens.json")
    }

    /// Log directory
    static var logDirectory: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
            .appendingPathComponent("Cluademail")
    }

    /// MCP server log file URL
    static var logFileURL: URL {
        logDirectory.appendingPathComponent("mcp-server.log")
    }

    /// Temporary directory for large attachments
    static var attachmentTempDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cluademail-attachments")
    }

    // MARK: - Server Info

    /// MCP server name
    static let serverName = "cluademail-mcp"

    /// MCP server version (matches app version)
    static let serverVersion = "1.0.0"

    /// MCP protocol version
    static let protocolVersion = "2024-11-05"

    // MARK: - Limits

    /// Maximum requests per minute
    static let maxRequestsPerMinute = 60

    /// Maximum requests per hour
    static let maxRequestsPerHour = 500

    /// Maximum attachment size to return inline (1 MB)
    static let maxInlineAttachmentSize: Int64 = 1 * 1024 * 1024

    /// Maximum attachment size to download (10 MB)
    static let maxAttachmentSize: Int64 = 10 * 1024 * 1024

    /// Attachment temp file expiry (1 hour)
    static let attachmentTempFileExpiry: TimeInterval = 3600

    /// Default email list limit
    static let defaultEmailListLimit = 20

    /// Maximum email list limit
    static let maxEmailListLimit = 100

    /// Default search result limit
    static let defaultSearchLimit = 20

    /// Maximum search result limit
    static let maxSearchLimit = 50

    // MARK: - Validation

    /// Validates that the database exists.
    /// - Throws: MCPError.databaseNotFound if database doesn't exist
    static func validateDatabaseExists() throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw MCPError.databaseNotFound
        }
    }

    /// Ensures the log directory exists.
    static func ensureLogDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Ensures the attachment temp directory exists.
    static func ensureAttachmentTempDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: attachmentTempDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Cleans up expired attachment temp files.
    static func cleanupExpiredAttachments() {
        let fileManager = FileManager.default
        let cutoffDate = Date().addingTimeInterval(-attachmentTempFileExpiry)

        guard let files = try? fileManager.contentsOfDirectory(
            at: attachmentTempDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for file in files {
            guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                  let creationDate = attributes[.creationDate] as? Date,
                  creationDate < cutoffDate else { continue }

            try? fileManager.removeItem(at: file)
        }
    }
}
