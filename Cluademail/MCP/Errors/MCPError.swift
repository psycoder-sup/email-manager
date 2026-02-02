import Foundation

/// MCP-specific errors with JSON-RPC error codes.
struct MCPError: Error, Sendable {
    let code: Int
    let message: String

    // MARK: - Standard JSON-RPC Errors

    /// Parse error (-32700)
    static func parseError(_ details: String? = nil) -> MCPError {
        MCPError(code: -32700, message: "Parse error\(details.map { ": \($0)" } ?? "")")
    }

    /// Invalid request (-32600)
    static func invalidRequest(_ details: String? = nil) -> MCPError {
        MCPError(code: -32600, message: "Invalid request\(details.map { ": \($0)" } ?? "")")
    }

    /// Method not found (-32601)
    static func methodNotFound(_ method: String) -> MCPError {
        MCPError(code: -32601, message: "Method not found: \(method)")
    }

    /// Invalid params (-32602)
    static func invalidParameter(_ param: String) -> MCPError {
        MCPError(code: -32602, message: "Missing or invalid parameter: \(param)")
    }

    /// Internal error (-32603)
    static func internalError(_ details: String? = nil) -> MCPError {
        MCPError(code: -32603, message: "Internal error\(details.map { ": \($0)" } ?? "")")
    }

    // MARK: - Application-Specific Errors

    /// Database not found (-32001)
    static var databaseNotFound: MCPError {
        MCPError(
            code: -32001,
            message: "Cluademail database not found. Please launch the Cluademail app first to set up your accounts."
        )
    }

    /// Account not found (-32001)
    static func accountNotFound(_ email: String) -> MCPError {
        MCPError(code: -32001, message: "Account not found: \(email)")
    }

    /// Email not found (-32001)
    static func emailNotFound(_ id: String) -> MCPError {
        MCPError(code: -32001, message: "Email not found: \(id)")
    }

    /// Attachment not found (-32001)
    static func attachmentNotFound(_ id: String) -> MCPError {
        MCPError(code: -32001, message: "Attachment not found: \(id)")
    }

    /// No accounts configured (-32002)
    static var noAccountsConfigured: MCPError {
        MCPError(
            code: -32002,
            message: "No accounts configured. Please add an account in the Cluademail app."
        )
    }

    /// Authentication required (-32002)
    static func authenticationRequired(_ email: String) -> MCPError {
        MCPError(
            code: -32002,
            message: "Authentication required for \(email). Please open Cluademail and sign in."
        )
    }

    /// Schema version mismatch (-32003)
    static func incompatibleVersion(current: Int, supported: ClosedRange<Int>) -> MCPError {
        MCPError(
            code: -32003,
            message: "Database schema version \(current) is not compatible. Supported: \(supported.lowerBound)-\(supported.upperBound). Please update Cluademail."
        )
    }

    /// Rate limit exceeded (-32029)
    static func rateLimitExceeded(retryAfter: Int) -> MCPError {
        MCPError(code: -32029, message: "Rate limit exceeded. Try again in \(retryAfter) seconds.")
    }

    /// Attachment too large (-32004)
    static func attachmentTooLarge(size: Int64, maxSize: Int64) -> MCPError {
        MCPError(
            code: -32004,
            message: "Attachment too large (\(formatSize(size))). Maximum size is \(formatSize(maxSize))."
        )
    }

    /// Connection limit reached (-32000)
    static var connectionLimitReached: MCPError {
        MCPError(code: -32000, message: "Maximum connections reached. Please try again later.")
    }

    // MARK: - Helper

    private static func formatSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}
