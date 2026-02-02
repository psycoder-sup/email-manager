import Foundation
import os.log

/// Main MCP server that handles JSON-RPC requests over stdio.
final class MCPServer: Sendable {

    private let transport: StdioTransport
    private let toolRegistry: MCPToolRegistry
    private let rateLimiter: MCPRateLimiter

    /// Atomic flag for graceful shutdown, accessible from signal handlers
    private static let shutdownRequested = OSAllocatedUnfairLock(initialState: false)

    init(transport: StdioTransport, toolRegistry: MCPToolRegistry, rateLimiter: MCPRateLimiter) {
        self.transport = transport
        self.toolRegistry = toolRegistry
        self.rateLimiter = rateLimiter
    }

    /// Runs the server loop until the client disconnects.
    func run() async throws {
        Logger.mcp.info("MCP server starting")

        // Handle signals for graceful shutdown
        setupSignalHandlers()

        while !Self.shutdownRequested.withLock({ $0 }) {
            do {
                // Read message
                guard let data = try await transport.readMessage() else {
                    Logger.mcp.info("Client disconnected (EOF)")
                    break
                }

                // Parse request
                let request: JSONRPCRequest
                do {
                    request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
                } catch {
                    Logger.mcp.error("Failed to parse request: \(error.localizedDescription)")
                    await sendError(id: .null, error: MCPError.parseError(error.localizedDescription))
                    continue
                }

                // Validate JSON-RPC version
                guard request.jsonrpc == "2.0" else {
                    Logger.mcp.warning("Invalid JSON-RPC version: \(request.jsonrpc)")
                    await sendError(id: request.id ?? .null, error: MCPError.invalidRequest("jsonrpc must be 2.0"))
                    continue
                }

                // Handle request
                await handleRequest(request)

            } catch let error as MCPError {
                await sendError(id: .null, error: error)
            } catch {
                Logger.mcp.error("Unexpected error: \(error.localizedDescription)")
                await sendError(id: .null, error: MCPError.internalError(error.localizedDescription))
            }
        }

        Logger.mcp.info("MCP server stopped")
    }

    // MARK: - Request Handling

    private func handleRequest(_ request: JSONRPCRequest) async {
        let requestId = request.id ?? .null

        Logger.mcp.debug("Handling request: \(request.method) [id: \(requestId)]")

        // Check rate limit for tool calls
        if request.method == "tools/call" {
            do {
                try await rateLimiter.checkLimit()
            } catch let error as MCPError {
                await sendError(id: requestId, error: error)
                return
            } catch {
                await sendError(id: requestId, error: MCPError.internalError())
                return
            }
        }

        // Route to handler
        switch request.method {
        case "initialize":
            await handleInitialize(request)

        case "initialized":
            // Notification, no response needed
            Logger.mcp.info("Client initialized")

        case "tools/list":
            await handleToolsList(request)

        case "tools/call":
            await handleToolCall(request)

        case "shutdown":
            await handleShutdown(request)

        default:
            await sendError(id: requestId, error: MCPError.methodNotFound(request.method))
        }
    }

    // MARK: - Handlers

    private func handleInitialize(_ request: JSONRPCRequest) async {
        let result = InitializeResult(
            protocolVersion: MCPConfiguration.protocolVersion,
            capabilities: .init(tools: .init()),
            serverInfo: .init(
                name: MCPConfiguration.serverName,
                version: MCPConfiguration.serverVersion
            )
        )

        await sendResult(id: request.id ?? .null, result: result)
        Logger.mcp.info("Sent initialize response")
    }

    private func handleToolsList(_ request: JSONRPCRequest) async {
        let schemas = toolRegistry.listToolSchemas()
        let result = ToolsListResult(tools: schemas)

        await sendResult(id: request.id ?? .null, result: result)
        Logger.mcp.info("Sent tools list (\(schemas.count) tools)")
    }

    private func handleToolCall(_ request: JSONRPCRequest) async {
        guard let params = request.params else {
            await sendError(id: request.id ?? .null, error: MCPError.invalidParameter("params"))
            return
        }

        // Decode tool call params
        let toolName: String
        let arguments: [String: AnyCodable]?

        if let name = params["name"]?.stringValue {
            toolName = name
            // Arguments can be nested or at top level
            if let args = params["arguments"]?.dictionaryValue {
                arguments = args.mapValues { AnyCodable($0) }
            } else {
                arguments = nil
            }
        } else {
            await sendError(id: request.id ?? .null, error: MCPError.invalidParameter("name"))
            return
        }

        // Find tool
        guard let tool = toolRegistry.getTool(name: toolName) else {
            await sendError(id: request.id ?? .null, error: MCPError.methodNotFound(toolName))
            return
        }

        // Execute tool
        do {
            let startTime = Date()
            let resultText = try await tool.execute(arguments: arguments)
            let duration = Date().timeIntervalSince(startTime)

            let result = ToolCallResult(text: resultText)
            await sendResult(id: request.id ?? .null, result: result)

            Logger.mcp.info("Tool '\(toolName)' completed in \(String(format: "%.2f", duration * 1000))ms")

        } catch let error as MCPError {
            await sendError(id: request.id ?? .null, error: error)
            Logger.mcp.warning("Tool '\(toolName)' failed: \(error.message)")

        } catch {
            await sendError(id: request.id ?? .null, error: MCPError.internalError(error.localizedDescription))
            Logger.mcp.error("Tool '\(toolName)' error: \(error.localizedDescription)")
        }
    }

    private func handleShutdown(_ request: JSONRPCRequest) async {
        Logger.mcp.info("Shutdown requested")
        await sendResult(id: request.id ?? .null, result: AnyCodable([:] as [String: Any]))
        await transport.close()
    }

    // MARK: - Response Helpers

    private func sendResult<T: Encodable>(id: JSONRPCId, result: T) async {
        do {
            let encodedResult = try JSONEncoder().encode(result)
            let anyResult = try JSONDecoder().decode(AnyCodable.self, from: encodedResult)
            let response = JSONRPCResponse(result: anyResult, id: id)
            try await transport.writeResponse(response)
        } catch {
            Logger.mcp.error("Failed to send response: \(error.localizedDescription)")
        }
    }

    private func sendError(id: JSONRPCId, error: MCPError) async {
        do {
            let errorResponse = JSONRPCErrorResponse(
                error: JSONRPCError(code: error.code, message: error.message),
                id: id
            )
            try await transport.writeError(errorResponse)
        } catch {
            Logger.mcp.error("Failed to send error response: \(error.localizedDescription)")
        }
    }

    // MARK: - Signal Handling

    private func setupSignalHandlers() {
        signal(SIGTERM) { _ in
            Logger.mcp.info("Received SIGTERM")
            MCPServer.shutdownRequested.withLock { $0 = true }
        }

        signal(SIGINT) { _ in
            Logger.mcp.info("Received SIGINT")
            MCPServer.shutdownRequested.withLock { $0 = true }
        }
    }
}
