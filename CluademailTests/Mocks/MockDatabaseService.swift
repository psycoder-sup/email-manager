import Foundation
import SwiftData
@testable import Cluademail

/// Mock database service for testing with in-memory storage.
/// Provides isolated database contexts for unit tests.
@MainActor
final class MockDatabaseService {

    // MARK: - Properties

    /// The in-memory model container
    let container: ModelContainer

    /// The main context for database operations
    var mainContext: ModelContext {
        container.mainContext
    }

    // MARK: - Initialization

    /// Creates a new mock database service with in-memory storage.
    init() {
        let schema = Schema([
            Account.self,
            Email.self,
            EmailThread.self,
            Attachment.self,
            Label.self,
            SyncState.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create mock ModelContainer: \(error)")
        }
    }

    // MARK: - Methods

    /// Creates a new background context for async operations.
    /// - Returns: A new ModelContext with autosave disabled
    func newBackgroundContext() -> ModelContext {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        return ctx
    }

    /// Clears all data from the database.
    /// Useful for resetting state between tests.
    func clearAll() throws {
        try mainContext.delete(model: Email.self)
        try mainContext.delete(model: EmailThread.self)
        try mainContext.delete(model: Attachment.self)
        try mainContext.delete(model: Label.self)
        try mainContext.delete(model: SyncState.self)
        try mainContext.delete(model: Account.self)
        try mainContext.save()
    }
}
