import Foundation

/// Registry for MCP tools.
final class MCPToolRegistry: Sendable {

    private let tools: [String: any MCPToolProtocol]

    /// Creates a registry with the given tools.
    /// - Parameter tools: Array of tools to register
    init(tools: [any MCPToolProtocol]) {
        var registry: [String: any MCPToolProtocol] = [:]
        for tool in tools {
            registry[tool.name] = tool
        }
        self.tools = registry
    }

    /// Returns all registered tools.
    func listTools() -> [any MCPToolProtocol] {
        Array(tools.values).sorted { $0.name < $1.name }
    }

    /// Returns the tool schemas for MCP tools/list response.
    func listToolSchemas() -> [ToolSchema] {
        listTools().map { $0.schema }
    }

    /// Gets a tool by name.
    /// - Parameter name: The tool name
    /// - Returns: The tool, or nil if not found
    func getTool(name: String) -> (any MCPToolProtocol)? {
        tools[name]
    }

    /// Returns the number of registered tools.
    var count: Int {
        tools.count
    }
}
