import Foundation

/// Protocol that all MCP tools must implement.
protocol MCPToolProtocol: Sendable {
    /// Tool name (e.g., "list_emails")
    var name: String { get }

    /// Tool description for MCP clients
    var description: String { get }

    /// JSON Schema for the tool
    var schema: ToolSchema { get }

    /// Executes the tool with the given arguments.
    /// - Parameter arguments: Tool arguments from the MCP request
    /// - Returns: Result text to return to the client
    func execute(arguments: [String: AnyCodable]?) async throws -> String
}

// MARK: - Parameter Extraction Helpers

extension MCPToolProtocol {

    /// Gets a required string parameter.
    func getString(_ key: String, from args: [String: AnyCodable]?) throws -> String {
        guard let args = args,
              let value = args[key]?.stringValue else {
            throw MCPError.invalidParameter(key)
        }
        return value
    }

    /// Gets an optional string parameter.
    func getOptionalString(_ key: String, from args: [String: AnyCodable]?) -> String? {
        args?[key]?.stringValue
    }

    /// Gets a boolean parameter with default value.
    func getBool(_ key: String, from args: [String: AnyCodable]?, default defaultValue: Bool = false) -> Bool {
        args?[key]?.boolValue ?? defaultValue
    }

    /// Gets an optional integer parameter.
    func getInt(_ key: String, from args: [String: AnyCodable]?) -> Int? {
        args?[key]?.intValue
    }

    /// Gets an integer parameter with default value.
    func getInt(_ key: String, from args: [String: AnyCodable]?, default defaultValue: Int) -> Int {
        args?[key]?.intValue ?? defaultValue
    }

    /// Gets a string array parameter.
    func getStringArray(_ key: String, from args: [String: AnyCodable]?) -> [String] {
        args?[key]?.stringArrayValue ?? []
    }
}

// MARK: - Output Formatting Helpers

extension MCPToolProtocol {

    /// Formats a sender for display.
    func formatSender(_ email: Email) -> String {
        if let name = email.fromName, !name.isEmpty {
            return "\(name) <\(email.fromAddress)>"
        }
        return email.fromAddress
    }

    /// Formats a date for display.
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Formats a file size for display.
    func formatSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1f GB", gb)
    }

    /// Strips HTML tags from a string (simple implementation).
    func stripHtml(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
