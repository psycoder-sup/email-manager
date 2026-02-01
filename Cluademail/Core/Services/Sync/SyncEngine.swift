import Foundation
import SwiftData
import os.log

// MARK: - Sync Engine

/// Actor-based sync engine for a single Gmail account.
/// Handles full sync, incremental sync, and progressive initial sync.
actor SyncEngine: SyncEngineProtocol {

    // MARK: - Constants

    /// Maximum emails to keep per account
    private let maxEmailsPerAccount = 1000

    /// Number of emails to fetch in Phase 1 of progressive sync
    private let quickSyncCount = 100

    /// Batch size for fetching messages
    private let batchSize = 50

    // MARK: - Dependencies

    private let account: Account
    private let apiService: any GmailAPIServiceProtocol
    private let databaseService: DatabaseService
    private let emailRepository: EmailRepository
    private let labelRepository: LabelRepository
    private let syncStateRepository: SyncStateRepository

    // MARK: - State

    private var isCancelled = false

    // MARK: - Initialization

    init(
        account: Account,
        apiService: any GmailAPIServiceProtocol,
        databaseService: DatabaseService
    ) {
        self.account = account
        self.apiService = apiService
        self.databaseService = databaseService
        self.emailRepository = EmailRepository()
        self.labelRepository = LabelRepository()
        self.syncStateRepository = SyncStateRepository()
    }

    // MARK: - SyncEngineProtocol

    func sync() async throws -> SyncResult {
        isCancelled = false

        Logger.sync.info("Starting sync for account: \(self.account.email, privacy: .private(mask: .hash))")

        let context = await databaseService.newBackgroundContext()

        // Fetch the account from the background context to avoid cross-context issues
        let accountRepository = AccountRepository()
        guard let contextAccount = try await accountRepository.fetch(byId: account.id, context: context) else {
            Logger.sync.error("Account not found in background context")
            throw SyncError.databaseError(NSError(domain: "SyncEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Account not found"]))
        }

        // Get or create sync state (avoid force unwrapping)
        let syncState: SyncState
        if let existing = try await syncStateRepository.fetch(accountId: contextAccount.id, context: context) {
            syncState = existing
        } else {
            let newState = SyncState(accountId: contextAccount.id)
            try await syncStateRepository.save(newState, context: context)
            syncState = newState
        }

        // Update sync status
        syncState.syncStatus = .syncing
        try context.save()

        do {
            // Sync labels first
            try await syncLabels(account: contextAccount, context: context)

            // Determine sync strategy
            let result: SyncResult
            if let historyId = syncState.historyId {
                // Try incremental sync
                do {
                    result = try await performIncrementalSync(
                        account: contextAccount,
                        startHistoryId: historyId,
                        context: context
                    )
                } catch APIError.notFound {
                    // History expired, fall back to full sync
                    Logger.sync.warning("History expired, falling back to full sync")
                    result = try await performFullSync(account: contextAccount, context: context)
                }
            } else {
                // No history ID, perform full sync (progressive)
                result = try await performFullSync(account: contextAccount, context: context)
            }

            // Update sync state on success
            syncState.syncStatus = .completed
            syncState.errorMessage = nil
            if case .success = result {
                if syncState.lastFullSyncDate == nil {
                    syncState.lastFullSyncDate = Date()
                } else {
                    syncState.lastIncrementalSyncDate = Date()
                }
            }
            try context.save()

            Logger.sync.info("Sync completed for account: \(self.account.email, privacy: .private(mask: .hash))")
            return result

        } catch {
            // Update sync state on failure
            syncState.syncStatus = .error
            syncState.errorMessage = error.localizedDescription
            try? context.save()

            Logger.sync.error("Sync failed for account: \(self.account.email, privacy: .private(mask: .hash)), error: \(error)")
            throw error
        }
    }

    func cancelSync() async {
        isCancelled = true
        Logger.sync.info("Sync cancelled for account: \(self.account.email, privacy: .private(mask: .hash))")
    }

    // MARK: - Full Sync

    private func performFullSync(context: ModelContext) async throws -> SyncResult {
        Logger.sync.debug("Performing full sync")

        var totalNewCount = 0
        var totalUpdatedCount = 0
        var allEmails: [Email] = []
        var pageToken: String?

        // Phase 1: Fetch first batch quickly (100 emails)
        let phase1Result = try await fetchEmailBatch(
            maxCount: quickSyncCount,
            pageToken: nil,
            context: context
        )
        allEmails.append(contentsOf: phase1Result.emails)
        totalNewCount += phase1Result.newCount
        totalUpdatedCount += phase1Result.updatedCount
        pageToken = phase1Result.nextPageToken

        Logger.sync.debug("Phase 1 complete: \(allEmails.count) emails")

        // Phase 2: Continue to max limit in background
        while !isCancelled,
              allEmails.count < maxEmailsPerAccount,
              pageToken != nil {

            let remaining = maxEmailsPerAccount - allEmails.count
            let batchResult = try await fetchEmailBatch(
                maxCount: min(100, remaining),
                pageToken: pageToken,
                context: context
            )

            allEmails.append(contentsOf: batchResult.emails)
            totalNewCount += batchResult.newCount
            totalUpdatedCount += batchResult.updatedCount
            pageToken = batchResult.nextPageToken

            Logger.sync.debug("Fetched batch: total \(allEmails.count) emails")
        }

        // Enforce email limit
        try await enforceEmailLimit(context: context)

        // Derive threads from synced emails
        try await deriveThreads(from: allEmails, context: context)

        // Update history ID from profile
        let profile = try await apiService.getProfile(accountEmail: account.email)
        if let historyId = profile.historyId {
            try await syncStateRepository.updateHistoryId(historyId, for: account.id, context: context)
        }

        // Update email count in sync state (use actual count after limit enforcement)
        if let syncState = try await syncStateRepository.fetch(accountId: account.id, context: context) {
            let actualCount = try await emailRepository.count(account: account, folder: nil, context: context)
            syncState.emailCount = actualCount
            try context.save()
        }

        return .success(newEmails: totalNewCount, updatedEmails: totalUpdatedCount, deletedEmails: 0)
    }

    // MARK: - Incremental Sync

    private func performIncrementalSync(
        startHistoryId: String,
        context: ModelContext
    ) async throws -> SyncResult {
        Logger.sync.debug("Performing incremental sync from history: \(startHistoryId)")

        // Fetch history records
        // Note: Gmail History API pagination is not currently implemented in GmailAPIService.
        // In practice, history responses are typically small enough to fit in one response.
        // If very large history is encountered, we'll process what we get and update historyId.
        var allHistory: [GmailHistoryDTO] = []
        var latestHistoryId = startHistoryId

        let historyList = try await apiService.getHistory(
            accountEmail: account.email,
            startHistoryId: startHistoryId,
            historyTypes: ["messageAdded", "messageDeleted", "labelsAdded", "labelsRemoved"]
        )

        if let history = historyList.history {
            allHistory.append(contentsOf: history)
        }

        if let newHistoryId = historyList.historyId {
            latestHistoryId = newHistoryId
        }

        // Log if pagination was truncated (future enhancement)
        if historyList.nextPageToken != nil {
            Logger.sync.warning("History response truncated - pagination not yet supported")
        }

        // Deduplicate history records into message deltas
        var messageDeltas: [String: MessageDelta] = [:]

        for historyRecord in allHistory {
            // Process messagesAdded
            for msg in historyRecord.messagesAdded ?? [] {
                var delta = messageDeltas[msg.message.id] ?? MessageDelta(messageId: msg.message.id)
                delta.needsFullFetch = true
                messageDeltas[msg.message.id] = delta
            }

            // Process messagesDeleted
            for msg in historyRecord.messagesDeleted ?? [] {
                var delta = messageDeltas[msg.message.id] ?? MessageDelta(messageId: msg.message.id)
                delta.isDeleted = true
                messageDeltas[msg.message.id] = delta
            }

            // Process labelsAdded
            for labelChange in historyRecord.labelsAdded ?? [] {
                var delta = messageDeltas[labelChange.message.id] ?? MessageDelta(messageId: labelChange.message.id)
                delta.labelsToAdd.formUnion(labelChange.labelIds)
                messageDeltas[labelChange.message.id] = delta
            }

            // Process labelsRemoved
            for labelChange in historyRecord.labelsRemoved ?? [] {
                var delta = messageDeltas[labelChange.message.id] ?? MessageDelta(messageId: labelChange.message.id)
                delta.labelsToRemove.formUnion(labelChange.labelIds)
                messageDeltas[labelChange.message.id] = delta
            }
        }

        // Apply deltas
        var newCount = 0
        var updatedCount = 0
        var deletedCount = 0
        var affectedEmails: [Email] = []

        for delta in messageDeltas.values {
            guard !isCancelled else { break }

            if delta.isDeleted {
                // Delete email
                if let email = try await emailRepository.fetch(byGmailId: delta.messageId, context: context) {
                    try await emailRepository.delete(email, context: context)
                    deletedCount += 1
                }
            } else if delta.needsFullFetch {
                // Fetch and save new email
                let msgDTO = try await apiService.getMessage(
                    accountEmail: account.email,
                    messageId: delta.messageId
                )
                let email = try GmailModelMapper.mapToEmail(msgDTO, account: account)
                try await emailRepository.save(email, context: context)
                affectedEmails.append(email)
                newCount += 1
            } else if !delta.labelsToAdd.isEmpty || !delta.labelsToRemove.isEmpty {
                // Update labels only
                if let email = try await emailRepository.fetch(byGmailId: delta.messageId, context: context) {
                    var labelIds = Set(email.labelIds)
                    labelIds.formUnion(delta.labelsToAdd)
                    labelIds.subtract(delta.labelsToRemove)
                    email.labelIds = Array(labelIds)
                    email.isRead = !labelIds.contains("UNREAD")
                    email.isStarred = labelIds.contains("STARRED")
                    try context.save()
                    affectedEmails.append(email)
                    updatedCount += 1
                }
            }
        }

        // Enforce email limit
        try await enforceEmailLimit(context: context)

        // Update threads for affected emails
        if !affectedEmails.isEmpty {
            try await deriveThreads(from: affectedEmails, context: context)
        }

        // Update history ID
        try await syncStateRepository.updateHistoryId(latestHistoryId, for: account.id, context: context)

        Logger.sync.debug("Incremental sync complete: \(newCount) new, \(updatedCount) updated, \(deletedCount) deleted")

        return .success(newEmails: newCount, updatedEmails: updatedCount, deletedEmails: deletedCount)
    }

    // MARK: - Label Sync

    private func syncLabels(context: ModelContext) async throws {
        Logger.sync.debug("Syncing labels")

        let labelDTOs = try await apiService.listLabels(accountEmail: account.email)

        for dto in labelDTOs {
            let label = GmailModelMapper.mapToLabel(dto, account: account)

            // Check if label exists
            if let existing = try await labelRepository.fetch(
                byGmailId: dto.id,
                account: account,
                context: context
            ) {
                // Update existing label
                existing.name = label.name
                existing.type = label.type
                existing.messageListVisibility = label.messageListVisibility
                existing.labelListVisibility = label.labelListVisibility
                existing.textColor = label.textColor
                existing.backgroundColor = label.backgroundColor
            } else {
                // Insert new label
                try await labelRepository.save(label, context: context)
            }
        }

        try context.save()
        Logger.sync.debug("Synced \(labelDTOs.count) labels")
    }

    // MARK: - Thread Derivation

    private func deriveThreads(from emails: [Email], context: ModelContext) async throws {
        guard !emails.isEmpty else { return }

        Logger.sync.debug("Deriving threads from \(emails.count) emails")

        // Get unique thread IDs from affected emails
        let affectedThreadIds = Set(emails.map { $0.threadId })

        for threadId in affectedThreadIds {
            // Fetch ALL emails for this thread from database (not just the passed ones)
            // This ensures accurate counts and state derivation
            let accountId = account.id
            let emailPredicate = #Predicate<Email> {
                $0.threadId == threadId && $0.account?.id == accountId
            }
            var emailDescriptor = FetchDescriptor<Email>(predicate: emailPredicate)
            emailDescriptor.sortBy = [SortDescriptor(\.date)]
            let allThreadEmails = try context.fetch(emailDescriptor)

            guard !allThreadEmails.isEmpty,
                  let firstEmail = allThreadEmails.first,
                  let latestEmail = allThreadEmails.last else { continue }

            // Collect unique participants
            var participants = Set<String>()
            for email in allThreadEmails {
                participants.insert(email.fromAddress)
                participants.formUnion(email.toAddresses)
            }

            // Check if thread exists
            let threadPredicate = #Predicate<EmailThread> { $0.threadId == threadId }
            var threadDescriptor = FetchDescriptor<EmailThread>(predicate: threadPredicate)
            threadDescriptor.fetchLimit = 1

            if let existingThread = try context.fetch(threadDescriptor).first {
                // Update existing thread with data from ALL emails
                existingThread.subject = firstEmail.subject
                existingThread.snippet = latestEmail.snippet
                existingThread.lastMessageDate = latestEmail.date
                existingThread.messageCount = allThreadEmails.count
                existingThread.isRead = allThreadEmails.allSatisfy(\.isRead)
                existingThread.isStarred = allThreadEmails.contains(where: \.isStarred)
                existingThread.participantEmails = Array(participants)
            } else {
                // Create new thread
                let thread = EmailThread(
                    threadId: threadId,
                    subject: firstEmail.subject,
                    snippet: latestEmail.snippet,
                    lastMessageDate: latestEmail.date,
                    messageCount: allThreadEmails.count,
                    isRead: allThreadEmails.allSatisfy(\.isRead),
                    isStarred: allThreadEmails.contains(where: \.isStarred),
                    participantEmails: Array(participants)
                )
                thread.account = account
                context.insert(thread)
            }
        }

        try context.save()
        Logger.sync.debug("Derived \(affectedThreadIds.count) threads")
    }

    // MARK: - Email Limit Enforcement

    private func enforceEmailLimit(context: ModelContext) async throws {
        try await emailRepository.deleteOldest(
            account: account,
            keepCount: maxEmailsPerAccount,
            context: context
        )
    }

    // MARK: - Helpers

    private struct BatchResult {
        let emails: [Email]
        let newCount: Int
        let updatedCount: Int
        let nextPageToken: String?
    }

    private func fetchEmailBatch(
        maxCount: Int,
        pageToken: String?,
        context: ModelContext
    ) async throws -> BatchResult {
        // List messages
        let (messageSummaries, nextToken) = try await apiService.listMessages(
            accountEmail: account.email,
            query: nil,
            labelIds: nil,
            maxResults: maxCount,
            pageToken: pageToken
        )

        guard !messageSummaries.isEmpty else {
            return BatchResult(emails: [], newCount: 0, updatedCount: 0, nextPageToken: nil)
        }

        // Batch fetch full messages
        let messageIds = messageSummaries.map(\.id)
        let batchResult = try await apiService.batchGetMessages(
            accountEmail: account.email,
            messageIds: messageIds
        )

        // Process succeeded messages
        var emails: [Email] = []
        var newCount = 0
        var updatedCount = 0

        for dto in batchResult.succeeded {
            let email = try GmailModelMapper.mapToEmail(dto, account: account)

            // Check if email exists
            if let existing = try await emailRepository.fetch(byGmailId: dto.id, context: context) {
                // Update existing email
                existing.labelIds = email.labelIds
                existing.isRead = email.isRead
                existing.isStarred = email.isStarred
                existing.snippet = email.snippet
                updatedCount += 1
                emails.append(existing)
            } else {
                // Save new email
                try await emailRepository.save(email, context: context)
                newCount += 1
                emails.append(email)
            }
        }

        // Log any failures
        if batchResult.hasFailures {
            Logger.sync.warning("Batch fetch had \(batchResult.failureCount) failures")
        }

        return BatchResult(
            emails: emails,
            newCount: newCount,
            updatedCount: updatedCount,
            nextPageToken: nextToken
        )
    }
}
