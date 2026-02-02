import Foundation
import SwiftData
import os.log

final class EmailRepository: BaseRepository<Email>, EmailRepositoryProtocol, @unchecked Sendable {

    func fetch(byGmailId gmailId: String, context: ModelContext) async throws -> Email? {
        try fetchOne(predicate: #Predicate { $0.gmailId == gmailId }, context: context)
    }

    /// Fetches emails with folder filtering.
    /// - Important: This method performs in-memory filtering and must be called from the MainActor.
    @MainActor
    func fetch(
        account: Account?,
        folder: String,
        isRead: Bool?,
        limit: Int?,
        offset: Int?,
        context: ModelContext
    ) async throws -> [Email] {
        // Fetch without folder filter (SwiftData can't translate array.contains() to SQLite)
        var emails = try fetch(
            predicate: buildPredicate(account: account, isRead: isRead),
            sortBy: [SortDescriptor(\.date, order: .reverse)],
            context: context
        )

        // Force relationship resolution and repair orphans
        resolveAccountRelationships(emails, expectedAccount: account, context: context)

        // Apply folder filter in-memory (must be on main actor for mainContext models)
        emails = emails.filter { $0.labelIds.contains(folder) }

        // Apply offset and limit after folder filtering
        if let offset, offset > 0 {
            emails = Array(emails.dropFirst(offset))
        }
        if let limit {
            emails = Array(emails.prefix(limit))
        }

        return emails
    }

    /// Fetches emails without folder filtering.
    @MainActor
    func fetch(
        account: Account?,
        isRead: Bool?,
        limit: Int?,
        offset: Int?,
        context: ModelContext
    ) async throws -> [Email] {
        let emails = try fetch(
            predicate: buildPredicate(account: account, isRead: isRead),
            sortBy: [SortDescriptor(\.date, order: .reverse)],
            limit: limit,
            offset: offset,
            context: context
        )

        // Force relationship resolution and repair orphans
        resolveAccountRelationships(emails, expectedAccount: account, context: context)

        return emails
    }

    func fetchThreads(
        account: Account?,
        folder: String?,
        limit: Int,
        context: ModelContext
    ) async throws -> [EmailThread] {
        var predicate: Predicate<EmailThread>?
        if let account {
            let accountId = account.id
            predicate = #Predicate<EmailThread> { $0.account?.id == accountId }
        }

        var descriptor = FetchDescriptor<EmailThread>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.lastMessageDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try context.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch threads: \(error.localizedDescription)")
            throw DatabaseError.fetchFailed(error)
        }
    }

    func search(query: String, account: Account?, context: ModelContext) async throws -> [Email] {
        let predicate: Predicate<Email>
        if let account {
            let accountId = account.id
            predicate = #Predicate<Email> {
                $0.account?.id == accountId &&
                ($0.subject.localizedStandardContains(query) ||
                 $0.fromAddress.localizedStandardContains(query) ||
                 $0.snippet.localizedStandardContains(query))
            }
        } else {
            predicate = #Predicate<Email> {
                $0.subject.localizedStandardContains(query) ||
                $0.fromAddress.localizedStandardContains(query) ||
                $0.snippet.localizedStandardContains(query)
            }
        }

        return try fetch(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)],
            limit: 100,
            context: context
        )
    }

    func save(_ email: Email, context: ModelContext) async throws {
        try super.save(email, context: context)
    }

    func saveAll(_ emails: [Email], context: ModelContext) async throws {
        try super.saveAll(emails, context: context)
    }

    func delete(_ email: Email, context: ModelContext) async throws {
        try super.delete(email, context: context)
    }

    func deleteOldest(account: Account, keepCount: Int, context: ModelContext) async throws {
        let accountId = account.id
        let allEmails = try fetch(
            predicate: #Predicate<Email> { $0.account?.id == accountId },
            sortBy: [SortDescriptor(\.date, order: .reverse)],
            context: context
        )

        guard allEmails.count > keepCount else { return }

        let emailsToDelete = Array(allEmails.dropFirst(keepCount))
        do {
            emailsToDelete.forEach { context.delete($0) }
            try context.save()
            Logger.database.info("Deleted \(emailsToDelete.count) oldest emails for account")
        } catch {
            Logger.database.error("Failed to delete oldest emails: \(error.localizedDescription)")
            throw DatabaseError.deleteFailed(error)
        }
    }

    /// Counts emails with folder filtering.
    /// - Important: This method performs in-memory filtering and must be called from the MainActor.
    @MainActor
    func count(account: Account?, folder: String, context: ModelContext) async throws -> Int {
        let emails = try fetch(
            predicate: buildPredicate(account: account, isRead: nil),
            sortBy: [],
            context: context
        )
        return emails.filter { $0.labelIds.contains(folder) }.count
    }

    /// Counts all emails without folder filtering.
    func count(account: Account, context: ModelContext) async throws -> Int {
        let accountId = account.id
        return try count(predicate: #Predicate<Email> { $0.account?.id == accountId }, context: context)
    }

    /// Counts unread emails with folder filtering.
    /// - Important: This method performs in-memory filtering and must be called from the MainActor.
    @MainActor
    func unreadCount(account: Account?, folder: String, context: ModelContext) async throws -> Int {
        let emails = try fetch(
            predicate: buildPredicate(account: account, isRead: false),
            sortBy: [],
            context: context
        )
        return emails.filter { $0.labelIds.contains(folder) }.count
    }

    // MARK: - Private

    /// Builds a predicate for account and isRead filters only.
    /// Folder filtering is handled in-memory because SwiftData cannot translate
    /// array.contains() to SQLite queries.
    private func buildPredicate(account: Account?, isRead: Bool?) -> Predicate<Email>? {
        switch (account, isRead) {
        case (.some(let acc), .some(let read)):
            let accountId = acc.id
            return #Predicate<Email> { $0.account?.id == accountId && $0.isRead == read }
        case (.some(let acc), .none):
            let accountId = acc.id
            return #Predicate<Email> { $0.account?.id == accountId }
        case (.none, .some(let read)):
            return #Predicate<Email> { $0.isRead == read }
        case (.none, .none):
            return nil
        }
    }

    /// Forces SwiftData to resolve account relationships from persistent store.
    /// Repairs orphaned emails by assigning the expected account if relationship is nil.
    @MainActor
    private func resolveAccountRelationships(_ emails: [Email], expectedAccount: Account?, context: ModelContext) {
        var repairedCount = 0
        for email in emails {
            // Touch relationship to force fault resolution
            if email.account != nil {
                let _ = email.account?.id
            } else if let account = expectedAccount {
                // Repair orphaned relationship
                email.account = account
                repairedCount += 1
            }
        }

        if repairedCount > 0 {
            try? context.save()
            Logger.database.debug("Repaired \(repairedCount) orphaned emails at fetch time")
        }
    }
}
