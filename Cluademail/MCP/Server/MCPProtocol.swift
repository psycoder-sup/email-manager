import Foundation

// MARK: - JSON-RPC 2.0 Types

/// JSON-RPC ID can be string, integer, or null.
enum JSONRPCId: Codable, Equatable, Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case null

    var description: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .null: return "null"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                JSONRPCId.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected string, integer, or null"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):
            try container.encode(s)
        case .int(let i):
            try container.encode(i)
        case .null:
            try container.encodeNil()
        }
    }
}

/// JSON-RPC 2.0 Request
struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let method: String
    let params: [String: AnyCodable]?
    let id: JSONRPCId?

    init(jsonrpc: String = "2.0", method: String, params: [String: AnyCodable]? = nil, id: JSONRPCId?) {
        self.jsonrpc = jsonrpc
        self.method = method
        self.params = params
        self.id = id
    }
}

/// JSON-RPC 2.0 Success Response
struct JSONRPCResponse: Encodable, Sendable {
    let jsonrpc: String
    let result: AnyCodable
    let id: JSONRPCId

    init(result: AnyCodable, id: JSONRPCId) {
        self.jsonrpc = "2.0"
        self.result = result
        self.id = id
    }
}

/// JSON-RPC 2.0 Error Object
struct JSONRPCError: Codable, Sendable {
    let code: Int
    let message: String
    let data: AnyCodable?

    init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// JSON-RPC 2.0 Error Response
struct JSONRPCErrorResponse: Encodable, Sendable {
    let jsonrpc: String
    let error: JSONRPCError
    let id: JSONRPCId

    init(error: JSONRPCError, id: JSONRPCId) {
        self.jsonrpc = "2.0"
        self.error = error
        self.id = id
    }
}

// MARK: - MCP Protocol Types

/// MCP Initialize Request Parameters
struct InitializeParams: Codable, Sendable {
    let protocolVersion: String
    let capabilities: ClientCapabilities
    let clientInfo: ClientInfo

    struct ClientCapabilities: Codable, Sendable {
        // Client capabilities (currently empty)
    }

    struct ClientInfo: Codable, Sendable {
        let name: String
        let version: String
    }
}

/// MCP Initialize Response Result
struct InitializeResult: Codable, Sendable {
    let protocolVersion: String
    let capabilities: ServerCapabilities
    let serverInfo: ServerInfo

    struct ServerCapabilities: Codable, Sendable {
        let tools: ToolsCapability

        struct ToolsCapability: Codable, Sendable {
            // Empty object for basic tools support
        }
    }

    struct ServerInfo: Codable, Sendable {
        let name: String
        let version: String
    }
}

/// MCP Tool Schema
struct ToolSchema: Codable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONSchema
}

/// JSON Schema for tool input
struct JSONSchema: Codable, Sendable {
    let type: String
    let properties: [String: PropertySchema]
    let required: [String]

    init(type: String = "object", properties: [String: PropertySchema], required: [String]) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

/// Property schema for JSON Schema
struct PropertySchema: Codable, Sendable {
    let type: String
    let description: String
    let items: ItemSchema?

    init(type: String, description: String, items: ItemSchema? = nil) {
        self.type = type
        self.description = description
        self.items = items
    }

    /// Creates a string property schema
    static func string(_ description: String) -> PropertySchema {
        PropertySchema(type: "string", description: description)
    }

    /// Creates a boolean property schema
    static func boolean(_ description: String) -> PropertySchema {
        PropertySchema(type: "boolean", description: description)
    }

    /// Creates an integer property schema
    static func integer(_ description: String) -> PropertySchema {
        PropertySchema(type: "integer", description: description)
    }

    /// Creates a string array property schema
    static func stringArray(_ description: String) -> PropertySchema {
        PropertySchema(type: "array", description: description, items: ItemSchema(type: "string"))
    }
}

/// Item schema for array properties
struct ItemSchema: Codable, Sendable {
    let type: String
}

/// MCP Tool Call Parameters
struct ToolCallParams: Codable, Sendable {
    let name: String
    let arguments: [String: AnyCodable]?
}

/// MCP Tool Call Result
struct ToolCallResult: Codable, Sendable {
    let content: [ContentBlock]

    struct ContentBlock: Codable, Sendable {
        let type: String
        let text: String

        init(text: String) {
            self.type = "text"
            self.text = text
        }
    }

    init(text: String) {
        self.content = [ContentBlock(text: text)]
    }
}

/// MCP Tools List Result
struct ToolsListResult: Codable, Sendable {
    let tools: [ToolSchema]
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for dynamic JSON values.
struct AnyCodable: Codable, Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Unable to encode value of type \(type(of: value))"
                )
            )
        }
    }

    // MARK: - Value Extraction

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
    var arrayValue: [Any]? { value as? [Any] }
    var dictionaryValue: [String: Any]? { value as? [String: Any] }

    var stringArrayValue: [String]? {
        guard let array = value as? [Any] else { return nil }
        return array.compactMap { $0 as? String }
    }
}
