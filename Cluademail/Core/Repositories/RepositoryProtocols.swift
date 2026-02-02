import Foundation
import SwiftData

// MARK: - AccountRepositoryProtocol

protocol AccountRepositoryProtocol: Sendable {
    func fetchAll(context: ModelContext) async throws -> [Account]
    func fetch(byId id: UUID, context: ModelContext) async throws -> Account?
    func fetch(byEmail email: String, context: ModelContext) async throws -> Account?
    func save(_ account: Account, context: ModelContext) async throws
    func delete(_ account: Account, context: ModelContext) async throws
}

// MARK: - EmailRepositoryProtocol

protocol EmailRepositoryProtocol: Sendable {
    func fetch(byGmailId gmailId: String, context: ModelContext) async throws -> Email?

    /// Fetches emails with folder filtering (requires MainActor).
    @MainActor
    func fetch(
        account: Account?,
        folder: String,
        isRead: Bool?,
        limit: Int?,
        offset: Int?,
        context: ModelContext
    ) async throws -> [Email]

    /// Fetches emails without folder filtering.
    func fetch(
        account: Account?,
        isRead: Bool?,
        limit: Int?,
        offset: Int?,
        context: ModelContext
    ) async throws -> [Email]

    func fetchThreads(
        account: Account?,
        folder: String?,
        limit: Int,
        context: ModelContext
    ) async throws -> [EmailThread]

    func search(query: String, account: Account?, context: ModelContext) async throws -> [Email]
    func save(_ email: Email, context: ModelContext) async throws
    func saveAll(_ emails: [Email], context: ModelContext) async throws
    func delete(_ email: Email, context: ModelContext) async throws
    func deleteOldest(account: Account, keepCount: Int, context: ModelContext) async throws

    /// Counts emails with folder filtering (requires MainActor).
    @MainActor
    func count(account: Account?, folder: String, context: ModelContext) async throws -> Int

    /// Counts all emails for an account.
    func count(account: Account, context: ModelContext) async throws -> Int

    /// Counts unread emails with folder filtering (requires MainActor).
    @MainActor
    func unreadCount(account: Account?, folder: String, context: ModelContext) async throws -> Int
}

// MARK: - SyncStateRepositoryProtocol

protocol SyncStateRepositoryProtocol: Sendable {
    func fetch(accountId: UUID, context: ModelContext) async throws -> SyncState?
    func save(_ syncState: SyncState, context: ModelContext) async throws
    func updateHistoryId(_ historyId: String, for accountId: UUID, context: ModelContext) async throws
}
