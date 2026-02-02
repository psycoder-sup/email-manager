import Foundation
import SwiftData
import os.log

/// View model for the email list, managing data loading, selection, and actions.
@Observable
@MainActor
final class EmailListViewModel {

    // MARK: - Display State

    /// Emails to display (filtered by search if applicable)
    private(set) var emails: [Email] = []

    /// Threads to display when in thread mode
    private(set) var threads: [EmailThread] = []

    /// Whether data is currently loading
    private(set) var isLoading: Bool = false

    /// Whether more data is loading (pagination)
    private(set) var isLoadingMore: Bool = false

    /// Error message to display
    private(set) var errorMessage: String?

    /// Whether there are more emails to load
    private(set) var hasMoreEmails: Bool = true

    // MARK: - View Settings

    /// Current display mode (emails or threads)
    var displayMode: DisplayMode = .emails

    /// Current sort order
    var sortOrder: SortOrder = .dateNewest

    /// Search query for local filtering
    var searchQuery: String = "" {
        didSet {
            applyLocalFilter()
        }
    }

    /// Active search filters
    var searchFilters = SearchFilters()

    // MARK: - Search State

    /// Search service for coordinating local and server search
    private(set) var searchService: SearchService?

    /// Whether server search has been performed for current query
    private(set) var hasSearchedServer: Bool = false

    /// Whether server search is in progress
    private(set) var isLoadingFromServer: Bool = false

    /// Whether search is currently active
    var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || searchFilters.isActive
    }

    // MARK: - Selection State

    /// Currently selected email/thread IDs
    var selectedIds: Set<String> = []

    /// Whether multi-select mode is active.
    var isMultiSelectMode: Bool {
        selectedIds.count > 1
    }

    /// IDs of currently displayed items (emails or threads).
    var displayedItemIds: [String] {
        switch displayMode {
        case .emails: emails.map(\.gmailId)
        case .threads: threads.map(\.threadId)
        }
    }

    /// Whether there are any items to display.
    var displayedItems: [Any] {
        switch displayMode {
        case .emails: emails
        case .threads: threads
        }
    }

    /// Last selected ID for range selection.
    private var lastSelectedId: String?

    // MARK: - Pagination

    private let pageSize = 50
    private let maxEmails = 1000
    private var currentOffset = 0

    // MARK: - Private State

    /// Unfiltered emails (before search filter)
    private var allEmails: [Email] = []

    /// Unfiltered threads
    private var allThreads: [EmailThread] = []

    /// Current account for actions
    private var currentAccount: Account?

    // MARK: - Dependencies

    private let emailRepository: EmailRepository
    private let databaseService: DatabaseService
    private let gmailAPIService: GmailAPIService
    private let appState: AppState

    // MARK: - Initialization

    init(databaseService: DatabaseService, appState: AppState) {
        self.databaseService = databaseService
        self.appState = appState
        self.emailRepository = EmailRepository()
        self.gmailAPIService = GmailAPIService.shared
        self.searchService = SearchService(databaseService: databaseService)
    }

    // MARK: - Data Loading

    /// Loads emails or threads for the specified account and folder.
    func loadData(account: Account?, folder: Folder) async {
        isLoading = true
        errorMessage = nil
        currentOffset = 0
        hasMoreEmails = true
        currentAccount = account
        selectedIds.removeAll()
        defer { isLoading = false }

        do {
            switch displayMode {
            case .emails:
                allEmails = try await emailRepository.fetch(
                    account: account,
                    folder: folder.rawValue,
                    isRead: nil,
                    limit: pageSize,
                    offset: 0,
                    context: databaseService.mainContext
                )
                hasMoreEmails = allEmails.count == pageSize
                applyLocalFilter()
                Logger.ui.info("Loaded \(self.allEmails.count) emails for \(folder.displayName)")

            case .threads:
                allThreads = try await emailRepository.fetchThreads(
                    account: account,
                    folder: folder.rawValue,
                    limit: pageSize,
                    context: databaseService.mainContext
                )
                threads = allThreads
                hasMoreEmails = allThreads.count == pageSize
                Logger.ui.info("Loaded \(self.allThreads.count) threads for \(folder.displayName)")
            }
        } catch {
            Logger.ui.error("Failed to load data: \(error.localizedDescription)")
            errorMessage = "Failed to load emails"
        }
    }

    /// Loads more emails (pagination).
    func loadMore(account: Account?, folder: Folder) async {
        guard !isLoadingMore, hasMoreEmails, currentOffset < maxEmails else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        currentOffset += pageSize

        do {
            switch displayMode {
            case .emails:
                let moreEmails = try await emailRepository.fetch(
                    account: account,
                    folder: folder.rawValue,
                    isRead: nil,
                    limit: pageSize,
                    offset: currentOffset,
                    context: databaseService.mainContext
                )
                allEmails.append(contentsOf: moreEmails)
                hasMoreEmails = moreEmails.count == pageSize && currentOffset + pageSize < maxEmails
                applyLocalFilter()
                Logger.ui.info("Loaded \(moreEmails.count) more emails, total: \(self.allEmails.count)")

            case .threads:
                let moreThreads = try await emailRepository.fetchThreads(
                    account: account,
                    folder: folder.rawValue,
                    limit: pageSize,
                    context: databaseService.mainContext
                )
                // Note: EmailRepository.fetchThreads doesn't support offset yet
                hasMoreEmails = false
                threads = allThreads
            }
        } catch {
            Logger.ui.error("Failed to load more: \(error.localizedDescription)")
            // Don't show error for pagination failures, just stop loading
            hasMoreEmails = false
        }
    }

    // MARK: - Local Filtering

    private func applyLocalFilter() {
        if searchQuery.isEmpty && !searchFilters.isActive {
            emails = allEmails
        } else {
            let query = searchQuery.lowercased()
            emails = allEmails.filter { email in
                // Text query filter
                let matchesQuery = query.isEmpty || (
                    email.subject.lowercased().contains(query) ||
                    email.fromAddress.lowercased().contains(query) ||
                    (email.fromName?.lowercased().contains(query) ?? false) ||
                    email.snippet.lowercased().contains(query)
                )

                // Additional filters
                let matchesFilters = applySearchFilters(to: email)

                return matchesQuery && matchesFilters
            }
        }
    }

    /// Applies search filters to a single email.
    private func applySearchFilters(to email: Email) -> Bool {
        if let from = searchFilters.from, !from.isEmpty {
            let fromLower = from.lowercased()
            guard email.fromAddress.lowercased().contains(fromLower) ||
                  (email.fromName?.lowercased().contains(fromLower) ?? false) else {
                return false
            }
        }

        if let to = searchFilters.to, !to.isEmpty {
            let toLower = to.lowercased()
            guard email.toAddresses.contains(where: { $0.lowercased().contains(toLower) }) else {
                return false
            }
        }

        if let afterDate = searchFilters.afterDate {
            guard email.date >= afterDate else { return false }
        }

        if let beforeDate = searchFilters.beforeDate {
            guard email.date <= beforeDate else { return false }
        }

        if searchFilters.hasAttachment {
            guard !email.attachments.isEmpty else { return false }
        }

        if searchFilters.isUnread {
            guard !email.isRead else { return false }
        }

        if !searchFilters.labelIds.isEmpty {
            guard searchFilters.labelIds.allSatisfy({ email.labelIds.contains($0) }) else {
                return false
            }
        }

        return true
    }

    // MARK: - Server Search

    /// Loads more results from the server for the current search query.
    func loadMoreFromServer() async {
        guard isSearchActive, !hasSearchedServer, !isLoadingFromServer else { return }
        guard let account = currentAccount else { return }

        isLoadingFromServer = true
        defer { isLoadingFromServer = false }

        do {
            let gmailQuery = searchFilters.toGmailQuery(baseQuery: searchQuery)

            // Get message IDs from server search
            let (messages, _) = try await gmailAPIService.listMessages(
                accountEmail: account.email,
                query: gmailQuery.isEmpty ? searchQuery : gmailQuery,
                labelIds: nil,
                maxResults: 50,
                pageToken: nil
            )

            guard !messages.isEmpty else {
                hasSearchedServer = true
                return
            }

            // Batch fetch full message details
            let messageIds = messages.map(\.id)
            let batchResult = try await gmailAPIService.batchGetMessages(
                accountEmail: account.email,
                messageIds: messageIds
            )

            // Map to Email models and merge with local results
            var serverEmails: [Email] = []
            let existingIds = Set(emails.map(\.gmailId))

            for messageDTO in batchResult.succeeded {
                // Skip if already in local results
                guard !existingIds.contains(messageDTO.id) else { continue }

                do {
                    // Check if email already exists in database
                    let descriptor = FetchDescriptor<Email>(predicate: #Predicate { $0.gmailId == messageDTO.id })
                    if let existing = try? databaseService.mainContext.fetch(descriptor).first {
                        // Preserve account relationship (fix for orphaned emails)
                        if existing.account == nil {
                            existing.account = account
                        }
                        serverEmails.append(existing)
                    } else {
                        let email = try GmailModelMapper.mapToEmail(messageDTO, account: account)
                        databaseService.mainContext.insert(email)
                        serverEmails.append(email)
                    }
                } catch {
                    Logger.api.error("Failed to map message: \(error.localizedDescription)")
                }
            }

            // Save persisted emails to database
            if !serverEmails.isEmpty {
                saveContext()
            }

            // Merge with existing results
            emails.append(contentsOf: serverEmails)
            emails.sort { $0.date > $1.date }

            hasSearchedServer = true
            Logger.ui.info("Server search completed: \(serverEmails.count) new results")

        } catch {
            Logger.ui.error("Server search failed: \(error.localizedDescription)")
        }
    }

    /// Clears the search state.
    func clearSearch() {
        searchQuery = ""
        searchFilters.reset()
        hasSearchedServer = false
        isLoadingFromServer = false
        applyLocalFilter()
    }

    /// Saves the current search to history.
    func saveSearchToHistory() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        SearchHistoryService.shared.addSearch(searchQuery, filters: searchFilters)
    }

    /// Gets search history.
    func getSearchHistory() -> [SearchHistoryItem] {
        SearchHistoryService.shared.getHistory()
    }

    /// Deletes a search from history.
    func deleteSearchFromHistory(id: UUID) {
        SearchHistoryService.shared.deleteSearch(id: id)
    }

    /// Clears all search history.
    func clearSearchHistory() {
        SearchHistoryService.shared.clearHistory()
    }

    // MARK: - Selection

    /// Handles selection with modifier keys for multi-select.
    func handleSelection(id: String, modifiers: SelectionModifiers) {
        switch modifiers {
        case .command:
            if selectedIds.contains(id) {
                selectedIds.remove(id)
            } else {
                selectedIds.insert(id)
            }
            lastSelectedId = id

        case .shift:
            let ids = displayedItemIds
            if let lastId = lastSelectedId,
               let lastIndex = ids.firstIndex(of: lastId),
               let currentIndex = ids.firstIndex(of: id) {
                let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
                for index in range {
                    selectedIds.insert(ids[index])
                }
            } else {
                selectedIds = [id]
                lastSelectedId = id
            }

        case .none:
            selectedIds = [id]
            lastSelectedId = id
        }
    }

    /// Selects all visible items.
    func selectAll() {
        selectedIds = Set(displayedItemIds)
    }

    /// Clears selection.
    func clearSelection() {
        selectedIds.removeAll()
        lastSelectedId = nil
    }

    /// Selects the next item in the list.
    func selectNextItem() {
        let ids = displayedItemIds
        guard !ids.isEmpty else { return }

        if let currentId = selectedIds.first,
           let currentIndex = ids.firstIndex(of: currentId),
           currentIndex + 1 < ids.count {
            selectedIds = [ids[currentIndex + 1]]
        } else if selectedIds.isEmpty {
            selectedIds = [ids[0]]
        }
    }

    /// Selects the previous item in the list.
    func selectPreviousItem() {
        let ids = displayedItemIds
        guard !ids.isEmpty else { return }

        if let currentId = selectedIds.first,
           let currentIndex = ids.firstIndex(of: currentId),
           currentIndex > 0 {
            selectedIds = [ids[currentIndex - 1]]
        } else if selectedIds.isEmpty, let lastId = ids.last {
            selectedIds = [lastId]
        }
    }

    // MARK: - UI Refresh

    /// Triggers UI refresh by reassigning the emails array.
    /// This forces SwiftUI to re-render rows with updated isRead values.
    func triggerUIRefresh() {
        // Reassigning triggers @Observable change notification
        let current = emails
        emails = current
    }

    // MARK: - Email Actions

    /// Toggles the star status for the specified email IDs.
    func toggleStar(emailIds: Set<String>) async {
        guard let account = currentAccount else { return }

        for emailId in emailIds {
            guard let email = allEmails.first(where: { $0.gmailId == emailId }) else { continue }

            do {
                let addLabels = email.isStarred ? [] : ["STARRED"]
                let removeLabels = email.isStarred ? ["STARRED"] : []

                _ = try await gmailAPIService.modifyMessage(
                    accountEmail: account.email,
                    messageId: emailId,
                    addLabelIds: addLabels,
                    removeLabelIds: removeLabels
                )

                // Update local state
                email.isStarred.toggle()
                if email.isStarred {
                    if !email.labelIds.contains("STARRED") {
                        email.labelIds.append("STARRED")
                    }
                } else {
                    email.labelIds.removeAll { $0 == "STARRED" }
                }
                saveContext()

                Logger.ui.info("Toggled star for email: \(emailId)")
            } catch {
                Logger.ui.error("Failed to toggle star: \(error.localizedDescription)")
            }
        }
    }

    /// Marks the specified emails as read.
    func markAsRead(emailIds: Set<String>) async {
        await modifyLabels(emailIds: emailIds, addLabels: [], removeLabels: ["UNREAD"]) { email in
            email.isRead = true
        }
    }

    /// Marks the specified emails as unread.
    func markAsUnread(emailIds: Set<String>) async {
        await modifyLabels(emailIds: emailIds, addLabels: ["UNREAD"], removeLabels: []) { email in
            email.isRead = false
        }
    }

    /// Archives the specified emails (removes from inbox).
    func archive(emailIds: Set<String>) async {
        await modifyLabels(emailIds: emailIds, addLabels: [], removeLabels: ["INBOX"]) { email in
            email.labelIds.removeAll { $0 == "INBOX" }
        }
        // Remove from current list if viewing inbox
        allEmails.removeAll { emailIds.contains($0.gmailId) }
        applyLocalFilter()
    }

    /// Moves the specified emails to trash.
    func moveToTrash(emailIds: Set<String>) async {
        guard let account = currentAccount else { return }

        for emailId in emailIds {
            do {
                try await gmailAPIService.trashMessage(
                    accountEmail: account.email,
                    messageId: emailId
                )
                Logger.ui.info("Moved to trash: \(emailId)")
            } catch {
                Logger.ui.error("Failed to trash: \(error.localizedDescription)")
            }
        }

        // Remove from current list
        allEmails.removeAll { emailIds.contains($0.gmailId) }
        applyLocalFilter()
        clearSelection()
    }

    // MARK: - Public Helpers

    /// Toggles read status for the specified emails based on the first email's state.
    func toggleReadStatus(emailIds: Set<String>) async {
        guard let firstId = emailIds.first,
              let email = allEmails.first(where: { $0.gmailId == firstId }) else { return }

        if email.isRead {
            await markAsUnread(emailIds: emailIds)
        } else {
            await markAsRead(emailIds: emailIds)
        }
    }

    // MARK: - Private Helpers

    /// Saves the ModelContext to persist changes.
    private func saveContext() {
        do {
            try databaseService.mainContext.save()
        } catch {
            Logger.database.error("Failed to save context: \(error.localizedDescription)")
        }
    }

    private func modifyLabels(
        emailIds: Set<String>,
        addLabels: [String],
        removeLabels: [String],
        localUpdate: (Email) -> Void
    ) async {
        guard let account = currentAccount else {
            Logger.ui.warning("modifyLabels called with no current account")
            return
        }

        for emailId in emailIds {
            guard let email = allEmails.first(where: { $0.gmailId == emailId }) else { continue }

            guard email.account != nil else {
                Logger.ui.warning("Skipping email \(emailId): no account relationship")
                continue
            }

            do {
                _ = try await gmailAPIService.modifyMessage(
                    accountEmail: account.email,
                    messageId: emailId,
                    addLabelIds: addLabels,
                    removeLabelIds: removeLabels
                )
                localUpdate(email)
                saveContext()
                appState.incrementUnreadCountVersion()
                Logger.ui.info("Modified labels for: \(emailId)")
            } catch {
                Logger.ui.error("Failed to modify labels: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Supporting Types

/// Display mode for the email list.
enum DisplayMode: String, CaseIterable {
    case emails = "Messages"
    case threads = "Conversations"
}

/// Sort order for emails.
enum SortOrder: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case sender = "Sender"
    case subject = "Subject"
}

/// Modifier keys for selection.
enum SelectionModifiers {
    case none
    case command
    case shift
}
