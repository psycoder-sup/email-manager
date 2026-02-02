import Foundation
import SwiftData
import os.log

/// Entry point for the MCP CLI tool.
@main
struct MCPMain {

    static func main() async {
        // Setup logging
        setupLogging()

        // Output startup message to stderr (some MCP clients wait for this)
        FileHandle.standardError.write("cluademail-mcp v\(MCPConfiguration.serverVersion) running on stdio\n".data(using: .utf8)!)

        Logger.mcp.info("cluademail-mcp starting...")

        do {
            // Validate database exists
            try MCPConfiguration.validateDatabaseExists()

            // Create database service
            let databaseService = try MCPDatabaseService()

            // Check for accounts
            let accounts = try await databaseService.fetchAccounts()

            guard !accounts.isEmpty else {
                throw MCPError.noAccountsConfigured
            }

            Logger.mcp.info("Found \(accounts.count) account(s)")

            // Validate at least one account has tokens
            let tokenStorage = FileTokenStorage.shared
            let accountsWithTokens = accounts.filter { tokenStorage.hasTokens(for: $0.email) }

            if accountsWithTokens.isEmpty {
                Logger.mcp.warning("No accounts have valid tokens")
                // We'll still start - tools will return auth errors as needed
            }

            // Create dependencies
            let transport = StdioTransport()
            let rateLimiter = MCPRateLimiter()
            let gmailAPI = GmailAPIService.shared

            // Create tools
            let tools: [any MCPToolProtocol] = [
                ListAccountsTool(databaseService: databaseService),
                ListEmailsTool(databaseService: databaseService),
                ReadEmailTool(databaseService: databaseService),
                SearchEmailsTool(databaseService: databaseService),
                CreateDraftTool(databaseService: databaseService, gmailAPI: gmailAPI, tokenStorage: tokenStorage),
                GetAttachmentTool(databaseService: databaseService, gmailAPI: gmailAPI, tokenStorage: tokenStorage)
            ]

            let registry = MCPToolRegistry(tools: tools)

            Logger.mcp.info("Registered \(registry.count) tools")

            // Create and run server
            let server = MCPServer(transport: transport, toolRegistry: registry, rateLimiter: rateLimiter)

            // Clean up old temp files
            MCPConfiguration.cleanupExpiredAttachments()

            try await server.run()

        } catch let error as MCPError {
            // Send JSON-RPC error to stdout
            sendFatalError(error)
            exit(1)

        } catch {
            Logger.mcp.fault("Fatal error: \(error.localizedDescription)")
            sendFatalError(MCPError.internalError(error.localizedDescription))
            exit(1)
        }
    }

    // MARK: - Private

    /// Sets up logging for the MCP server.
    private static func setupLogging() {
        // In debug mode, also log to stderr
        if ProcessInfo.processInfo.environment["CLUADEMAIL_MCP_DEBUG"] != nil {
            // Debug logging is enabled via Logger subsystem
            Logger.mcp.info("Debug mode enabled")
        }

        // Create log directory if needed
        do {
            try MCPConfiguration.ensureLogDirectoryExists()
        } catch {
            // Logging directory creation failed - continue anyway
        }
    }

    /// Sends a fatal error as JSON-RPC response (newline-delimited per MCP spec).
    private static func sendFatalError(_ error: MCPError) {
        let errorResponse = JSONRPCErrorResponse(
            error: JSONRPCError(code: error.code, message: error.message),
            id: .null
        )

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(errorResponse)

            // MCP stdio uses newline-delimited JSON
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        } catch {
            // Last resort - write plain error to stderr
            FileHandle.standardError.write("Fatal error: \(error.localizedDescription)\n".data(using: .utf8)!)
        }
    }
}
