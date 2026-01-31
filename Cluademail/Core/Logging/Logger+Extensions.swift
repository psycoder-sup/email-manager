import os.log
import Foundation

// MARK: - Category-based Loggers

extension Logger {
    private static let subsystem = AppConfiguration.loggingSubsystem

    /// Logger for general application events
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Logger for authentication operations
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Logger for sync operations
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Logger for API calls
    static let api = Logger(subsystem: subsystem, category: "api")

    /// Logger for database operations
    static let database = Logger(subsystem: subsystem, category: "database")

    /// Logger for MCP server operations
    static let mcp = Logger(subsystem: subsystem, category: "mcp")

    /// Logger for UI events
    static let ui = Logger(subsystem: subsystem, category: "ui")
}

// MARK: - Privacy-Aware Logging Helpers

extension Logger {
    /// Logs a message with a sensitive value that should be redacted in release builds.
    /// - Parameters:
    ///   - message: The log message
    ///   - sensitiveValue: The sensitive value to log (will be redacted)
    ///   - level: The log level (default: .debug)
    func logSensitive(
        _ message: String,
        sensitiveValue: String,
        level: OSLogType = .debug
    ) {
        self.log(level: level, "\(message): \(sensitiveValue, privacy: .private)")
    }

    /// Logs an email address with privacy protection.
    /// - Parameters:
    ///   - message: The log message
    ///   - email: The email address (will be redacted in release)
    func logEmail(_ message: String, email: String) {
        self.debug("\(message): \(email, privacy: .private(mask: .hash))")
    }

    /// Logs a request with URL and optional body preview.
    /// - Parameters:
    ///   - method: HTTP method
    ///   - url: Request URL
    ///   - hasBody: Whether the request has a body
    func logRequest(method: String, url: String, hasBody: Bool = false) {
        let bodyInfo = hasBody ? " (with body)" : ""
        self.debug("Request: \(method) \(url)\(bodyInfo)")
    }

    /// Logs a response with status code.
    /// - Parameters:
    ///   - statusCode: HTTP status code
    ///   - url: Response URL
    ///   - duration: Request duration in seconds
    func logResponse(statusCode: Int, url: String, duration: TimeInterval? = nil) {
        if let duration = duration {
            self.debug("Response: \(statusCode) \(url) (\(String(format: "%.2f", duration))s)")
        } else {
            self.debug("Response: \(statusCode) \(url)")
        }
    }
}

// MARK: - Conditional Logging

extension Logger {
    /// Logs only when verbose logging is enabled.
    /// Use for detailed debugging that would be too noisy in production.
    /// - Parameters:
    ///   - message: The message to log
    func verbose(_ message: String) {
        guard AppConfiguration.verboseLoggingEnabled else { return }
        self.debug("\(message)")
    }
}
