import Foundation
import SwiftData
import os.log

/// Actor for database access in the MCP CLI tool.
/// Provides read-only access to the shared SwiftData store.
actor MCPDatabaseService {

    private let container: ModelContainer

    /// Creates a database service connected to the shared database.
    /// - Throws: If the database cannot be opened
    init() throws {
        let schema = Schema([
            Account.self,
            Email.self,
            EmailThread.self,
            Attachment.self,
            SyncState.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            url: MCPConfiguration.databaseURL,
            allowsSave: true // Needed for draft creation
        )

        self.container = try ModelContainer(for: schema, configurations: [config])
        Logger.mcp.info("Database connected: \(MCPConfiguration.databaseURL.path)")
    }

    /// Creates a database service with a custom container (for testing).
    init(container: ModelContainer) {
        self.container = container
    }

    /// Performs a read operation on the database.
    /// - Parameter operation: The operation to perform with a ModelContext
    /// - Returns: The result of the operation
    func performRead<T: Sendable>(_ operation: @Sendable (ModelContext) throws -> T) throws -> T {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try operation(context)
    }

    /// Performs a write operation on the database.
    /// - Parameter operation: The operation to perform with a ModelContext
    /// - Returns: The result of the operation
    func performWrite<T: Sendable>(_ operation: @Sendable (ModelContext) throws -> T) throws -> T {
        let context = ModelContext(container)
        let result = try operation(context)
        try context.save()
        return result
    }

    /// Fetches all accounts.
    func fetchAccounts() throws -> [Account] {
        try performRead { context in
            let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.email)])
            return try context.fetch(descriptor)
        }
    }

    /// Fetches an account by email.
    func fetchAccount(byEmail email: String) throws -> Account? {
        try performRead { context in
            let predicate = #Predicate<Account> { $0.email == email }
            var descriptor = FetchDescriptor<Account>(predicate: predicate)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        }
    }

    /// Fetches an email by Gmail ID.
    func fetchEmail(byGmailId gmailId: String) throws -> Email? {
        try performRead { context in
            let predicate = #Predicate<Email> { $0.gmailId == gmailId }
            var descriptor = FetchDescriptor<Email>(predicate: predicate)
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        }
    }
}
