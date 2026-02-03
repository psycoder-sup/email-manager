import Foundation
import SwiftData
import os.log

/// Service for coordinating local and server email search with debouncing.
@Observable
@MainActor
final class SearchService {

    // MARK: - State

    /// Current search query
    var searchQuery: String = ""

    /// Active search filters
    var searchFilters = SearchFilters()

    /// Search results (deduplicated and sorted)
    private(set) var searchResults: [Email] = []

    /// Whether a search is in progress
    private(set) var isSearching: Bool = false

    /// Whether server search has been performed
    private(set) var hasSearchedServer: Bool = false

    /// Whether server search is loading
    private(set) var isLoadingMore: Bool = false

    /// Error message if search failed
    private(set) var errorMessage: String?

    // MARK: - Configuration

    private let debounceDelay: Duration = .milliseconds(300)
    private let maxLocalResults = 100
    private let serverSearchThreshold = 10

    // MARK: - Dependencies

    private let emailRepository: EmailRepository
    private let accountRepository: AccountRepository
    private let gmailAPIService: GmailAPIService
    private let databaseService: DatabaseService
    private let historyService: SearchHistoryService

    // MARK: - Private State

    private var searchTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Returns true if search is active (has query or filters)
    var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || searchFilters.isActive
    }

    // MARK: - Initialization

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
        self.emailRepository = EmailRepository()
        self.accountRepository = AccountRepository()
        self.gmailAPIService = GmailAPIService.shared
        self.historyService = SearchHistoryService.shared
    }

    /// Test initializer with dependency injection
    init(
        databaseService: DatabaseService,
        emailRepository: EmailRepository,
        accountRepository: AccountRepository,
        gmailAPIService: GmailAPIService,
        historyService: SearchHistoryService
    ) {
        self.databaseService = databaseService
        self.emailRepository = emailRepository
        self.accountRepository = accountRepository
        self.gmailAPIService = gmailAPIService
        self.historyService = historyService
    }

    // MARK: - Public Interface

    /// Performs a debounced search with the current query and filters.
    /// - Parameter account: The account to search, or nil for all accounts
    func search(account: Account?) async {
        // Cancel any in-progress search
        searchTask?.cancel()
        searchTask = nil

        // Reset server search flag on new search
        hasSearchedServer = false

        guard isSearchActive else {
            clearSearch()
            return
        }

        searchTask = Task { @MainActor in
            // Debounce
            do {
                try await Task.sleep(for: debounceDelay)
            } catch {
                return // Cancelled
            }

            guard !Task.isCancelled else { return }

            await performSearch(account: account)
        }
    }

    /// Performs search immediately without debouncing.
    /// - Parameter account: The account to search, or nil for all accounts
    func performSearch(account: Account?) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            // Determine accounts to search
            let accounts: [Account]
            if let account {
                accounts = [account]
            } else if let filterAccountIds = searchFilters.accountIds {
                accounts = try await accountRepository.fetchAll(context: databaseService.mainContext)
                    .filter { filterAccountIds.contains($0.id) }
            } else {
                accounts = try await accountRepository.fetchAll(context: databaseService.mainContext)
            }

            // Perform local search
            var localResults = await searchLocal(accounts: accounts)

            // Check if server search should be triggered
            let shouldSearchServer = localResults.count < serverSearchThreshold ||
                                     searchQuery.contains(":") // Has Gmail operators

            if shouldSearchServer && !hasSearchedServer {
                let serverResults = await searchServer(accounts: accounts)
                localResults = mergeResults(local: localResults, server: serverResults)
                hasSearchedServer = true
            }

            searchResults = localResults
            Logger.ui.info("Search completed: \(self.searchResults.count) results")

        } catch {
            Logger.ui.error("Search failed: \(error.localizedDescription)")
            errorMessage = "Search failed. Please try again."
        }
    }

    /// Explicitly loads more results from server.
    /// - Parameter account: The account to search, or nil for all accounts
    func loadMoreFromServer(account: Account?) async {
        guard !isLoadingMore, !hasSearchedServer else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let accounts: [Account]
            if let account {
                accounts = [account]
            } else {
                accounts = try await accountRepository.fetchAll(context: databaseService.mainContext)
            }

            let serverResults = await searchServer(accounts: accounts)
            searchResults = mergeResults(local: searchResults, server: serverResults)
            hasSearchedServer = true

            Logger.ui.info("Server search completed: \(self.searchResults.count) total results")

        } catch {
            Logger.ui.error("Server search failed: \(error.localizedDescription)")
            errorMessage = "Couldn't search server. Check connection."
        }
    }

    /// Clears search state.
    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchFilters.reset()
        searchResults = []
        hasSearchedServer = false
        isSearching = false
        isLoadingMore = false
        errorMessage = nil
    }

    /// Saves the current search to history.
    func saveToHistory() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        historyService.addSearch(searchQuery, filters: searchFilters)
    }

    /// Returns search history, optionally filtered by current query.
    func getHistory(filtered: Bool = false) -> [SearchHistoryItem] {
        if filtered && !searchQuery.isEmpty {
            return historyService.filterHistory(by: searchQuery)
        }
        return historyService.getHistory()
    }

    /// Deletes a search from history.
    func deleteFromHistory(id: UUID) {
        historyService.deleteSearch(id: id)
    }

    /// Clears all search history.
    func clearHistory() {
        historyService.clearHistory()
    }

    // MARK: - Private Methods

    /// Searches local database for matching emails.
    private func searchLocal(accounts: [Account]) async -> [Email] {
        var allResults: [Email] = []

        for account in accounts {
            do {
                let results = try await emailRepository.search(
                    query: searchQuery,
                    account: account,
                    context: databaseService.mainContext
                )
                allResults.append(contentsOf: results)
            } catch {
                Logger.ui.error("Local search failed for account \(account.email): \(error.localizedDescription)")
            }
        }

        // Apply additional filters that weren't handled by repository
        allResults = applyFilters(to: allResults)

        // Deduplicate and sort
        return deduplicateAndSort(allResults)
    }

    /// Searches Gmail API for matching emails.
    /// Uses two-phase approach: parallel API fetches, then serial database operations.
    private func searchServer(accounts: [Account]) async -> [Email] {
        let gmailQuery = searchFilters.toGmailQuery(baseQuery: searchQuery)

        // Phase 1: Parallel API fetches (no database access)
        // Capture account IDs and emails before entering TaskGroup to avoid cross-context issues
        let accountInfos = accounts.map { (id: $0.id, email: $0.email) }

        // Capture API service reference to pass to static method
        let apiService = gmailAPIService

        let apiResults = await withTaskGroup(of: (UUID, [GmailMessageDTO]).self) { group in
            for accountInfo in accountInfos {
                group.addTask {
                    // Use static nonisolated method - completely off MainActor
                    await (accountInfo.id, Self.fetchMessagesFromAPI(
                        apiService: apiService,
                        accountEmail: accountInfo.email,
                        query: gmailQuery
                    ))
                }
            }

            var results: [(UUID, [GmailMessageDTO])] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Phase 2: Serial database operations on MainActor
        return await persistSearchResults(apiResults)
    }

    /// Fetches messages from Gmail API without any database operations.
    /// Static nonisolated to ensure parallel calls run completely off MainActor.
    private nonisolated static func fetchMessagesFromAPI(
        apiService: GmailAPIService,
        accountEmail: String,
        query: String
    ) async -> [GmailMessageDTO] {
        do {
            let (messages, _) = try await apiService.listMessages(
                accountEmail: accountEmail,
                query: query.isEmpty ? nil : query,
                labelIds: nil,
                maxResults: 50,
                pageToken: nil
            )

            guard !messages.isEmpty else { return [] }

            let messageIds = messages.map(\.id)
            let batchResult = try await apiService.batchGetMessages(
                accountEmail: accountEmail,
                messageIds: messageIds
            )

            return batchResult.succeeded
        } catch {
            Logger.api.error("API fetch failed for \(accountEmail): \(error.localizedDescription)")
            return []
        }
    }

    /// Persists search results to database. Must run serially on MainActor.
    /// This ensures all database operations use a consistent context.
    @MainActor
    private func persistSearchResults(_ apiResults: [(UUID, [GmailMessageDTO])]) async -> [Email] {
        var allEmails: [Email] = []

        for (accountId, messageDTOs) in apiResults {
            // Fetch account fresh in this context to ensure proper model binding
            let accountDescriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == accountId })
            guard let account = try? databaseService.mainContext.fetch(accountDescriptor).first else {
                Logger.database.warning("Could not find account with ID \(accountId) for search results")
                continue
            }

            for messageDTO in messageDTOs {
                do {
                    // Check if email already exists in database
                    let descriptor = FetchDescriptor<Email>(predicate: #Predicate { $0.gmailId == messageDTO.id })
                    if let existing = try? databaseService.mainContext.fetch(descriptor).first {
                        // Preserve account relationship (fix for orphaned emails)
                        if existing.account == nil {
                            existing.account = account
                        }
                        allEmails.append(existing)
                    } else {
                        let email = try GmailModelMapper.mapToEmail(messageDTO)
                        email.account = account
                        databaseService.mainContext.insert(email)
                        allEmails.append(email)
                    }
                } catch {
                    Logger.api.error("Failed to map message: \(error.localizedDescription)")
                }
            }
        }

        // Save all persisted emails in a single batch
        if !allEmails.isEmpty {
            do {
                try databaseService.mainContext.save()
            } catch {
                Logger.database.error("Failed to save search results: \(error.localizedDescription)")
            }
        }

        return allEmails
    }

    /// Applies filters to email results.
    private func applyFilters(to emails: [Email]) -> [Email] {
        var filtered = emails

        if let from = searchFilters.from, !from.isEmpty {
            let fromLower = from.lowercased()
            filtered = filtered.filter {
                $0.fromAddress.lowercased().contains(fromLower) ||
                ($0.fromName?.lowercased().contains(fromLower) ?? false)
            }
        }

        if let to = searchFilters.to, !to.isEmpty {
            let toLower = to.lowercased()
            filtered = filtered.filter { email in
                email.toAddresses.contains { $0.lowercased().contains(toLower) }
            }
        }

        if let afterDate = searchFilters.afterDate {
            filtered = filtered.filter { $0.date >= afterDate }
        }

        if let beforeDate = searchFilters.beforeDate {
            filtered = filtered.filter { $0.date <= beforeDate }
        }

        if searchFilters.hasAttachment {
            filtered = filtered.filter { !$0.attachments.isEmpty }
        }

        if searchFilters.isUnread {
            filtered = filtered.filter { !$0.isRead }
        }

        return filtered
    }

    /// Merges local and server results, deduplicating by gmailId.
    private func mergeResults(local: [Email], server: [Email]) -> [Email] {
        var merged = local
        let localIds = Set(local.map(\.gmailId))

        for email in server {
            if !localIds.contains(email.gmailId) {
                merged.append(email)
            }
        }

        return deduplicateAndSort(merged)
    }

    /// Deduplicates emails by gmailId and sorts by date descending.
    private func deduplicateAndSort(_ emails: [Email]) -> [Email] {
        var seen = Set<String>()
        var unique: [Email] = []

        for email in emails {
            if seen.insert(email.gmailId).inserted {
                unique.append(email)
            }
        }

        return unique
            .sorted { $0.date > $1.date }
            .prefix(maxLocalResults)
            .map { $0 }
    }
}
