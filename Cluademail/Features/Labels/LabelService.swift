import Foundation
import SwiftData
import os.log

/// Service for label fetching, caching, and management.
@Observable
@MainActor
final class LabelService {

    // MARK: - Cache

    /// Per-account label cache
    private var labelsCache: [UUID: [Label]] = [:]

    /// Per-account display items cache (for UserLabelsSection)
    private var displayItemsCache: [UUID: [DisplayItem]] = [:]

    /// Accounts currently loading display items
    private var loadingAccounts: Set<UUID> = []

    /// Display item for labels (breaks SwiftData observation chain)
    struct DisplayItem: Identifiable {
        let id: String
        let name: String
        let backgroundColor: String?

        init(from label: Label) {
            self.id = label.gmailLabelId
            self.name = label.name
            self.backgroundColor = label.backgroundColor
        }
    }

    // MARK: - Dependencies

    private let labelRepository: LabelRepository
    private let gmailAPIService: GmailAPIService
    private let databaseService: DatabaseService

    // MARK: - Initialization

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
        self.labelRepository = LabelRepository()
        self.gmailAPIService = GmailAPIService.shared
    }

    /// Test initializer with dependency injection
    init(
        databaseService: DatabaseService,
        labelRepository: LabelRepository,
        gmailAPIService: GmailAPIService
    ) {
        self.databaseService = databaseService
        self.labelRepository = labelRepository
        self.gmailAPIService = gmailAPIService
    }

    // MARK: - Public Interface

    /// Fetches all labels for an account (cached).
    /// - Parameter account: The account to fetch labels for
    /// - Returns: Sorted array of labels
    func getLabels(for account: Account) async throws -> [Label] {
        // Check cache first
        if let cached = labelsCache[account.id] {
            return cached
        }

        // Fetch from repository
        let labels = try await labelRepository.fetchAll(account: account, context: databaseService.mainContext)

        if labels.isEmpty {
            // If no local labels, try fetching from API
            try await refreshLabels(for: account)
            return labelsCache[account.id] ?? []
        }

        let sorted = sortLabels(labels)
        labelsCache[account.id] = sorted
        return sorted
    }

    /// Fetches only user-created labels for an account.
    /// - Parameter account: The account to fetch labels for
    /// - Returns: Array of user labels sorted alphabetically
    func getUserLabels(for account: Account) async throws -> [Label] {
        let allLabels = try await getLabels(for: account)
        return allLabels.filter { $0.type == .user }
    }

    /// Fetches only system labels for an account.
    /// - Parameter account: The account to fetch labels for
    /// - Returns: Array of system labels in standard order
    func getSystemLabels(for account: Account) async throws -> [Label] {
        let allLabels = try await getLabels(for: account)
        return allLabels.filter { $0.type == .system }
    }

    /// Applies a label to an email.
    /// - Parameters:
    ///   - labelId: The Gmail label ID to apply
    ///   - emailId: The Gmail message ID
    ///   - account: The account the email belongs to
    func applyLabel(_ labelId: String, to emailId: String, account: Account) async throws {
        // Call Gmail API
        _ = try await gmailAPIService.modifyMessage(
            accountEmail: account.email,
            messageId: emailId,
            addLabelIds: [labelId],
            removeLabelIds: []
        )

        // Update local email
        if let email = try await findEmail(gmailId: emailId) {
            if !email.labelIds.contains(labelId) {
                email.labelIds.append(labelId)
                try databaseService.mainContext.save()
            }
        }

        Logger.ui.info("Applied label \(labelId) to email \(emailId)")
    }

    /// Removes a label from an email.
    /// - Parameters:
    ///   - labelId: The Gmail label ID to remove
    ///   - emailId: The Gmail message ID
    ///   - account: The account the email belongs to
    func removeLabel(_ labelId: String, from emailId: String, account: Account) async throws {
        // Call Gmail API
        _ = try await gmailAPIService.modifyMessage(
            accountEmail: account.email,
            messageId: emailId,
            addLabelIds: [],
            removeLabelIds: [labelId]
        )

        // Update local email
        if let email = try await findEmail(gmailId: emailId) {
            email.labelIds.removeAll { $0 == labelId }
            try databaseService.mainContext.save()
        }

        Logger.ui.info("Removed label \(labelId) from email \(emailId)")
    }

    /// Refreshes labels from Gmail API for an account.
    /// - Parameter account: The account to refresh labels for
    func refreshLabels(for account: Account) async throws {
        // Fetch from Gmail API
        let labelDTOs = try await gmailAPIService.listLabels(accountEmail: account.email)

        // Map to models and save
        var labels: [Label] = []
        for dto in labelDTOs {
            let label = GmailModelMapper.mapToLabel(dto, account: account)
            labels.append(label)

            // Check if exists and update or insert
            if let existing = try await labelRepository.fetch(
                byGmailId: dto.id,
                account: account,
                context: databaseService.mainContext
            ) {
                existing.name = label.name
                existing.textColor = label.textColor
                existing.backgroundColor = label.backgroundColor
                existing.messageListVisibility = label.messageListVisibility
                existing.labelListVisibility = label.labelListVisibility
            } else {
                try await labelRepository.save(label, context: databaseService.mainContext)
            }
        }

        try databaseService.mainContext.save()

        // Update cache
        labelsCache[account.id] = sortLabels(labels)

        Logger.ui.info("Refreshed \(labels.count) labels for account \(account.email)")
    }

    /// Clears the label cache for an account.
    /// - Parameter account: The account to clear cache for
    func invalidateCache(for account: Account) {
        labelsCache.removeValue(forKey: account.id)
        displayItemsCache.removeValue(forKey: account.id)
    }

    /// Clears all label caches.
    func invalidateAllCaches() {
        labelsCache.removeAll()
        displayItemsCache.removeAll()
    }

    // MARK: - Display Items Cache (for UserLabelsSection)

    /// Gets cached display items for an account.
    /// - Parameter accountId: The account UUID
    /// - Returns: Cached display items or nil if not cached
    func getDisplayItems(for accountId: UUID) -> [DisplayItem]? {
        displayItemsCache[accountId]
    }

    /// Caches display items for an account.
    /// - Parameters:
    ///   - items: The display items to cache
    ///   - accountId: The account UUID
    func setDisplayItems(_ items: [DisplayItem], for accountId: UUID) {
        displayItemsCache[accountId] = items
    }

    /// Checks if an account is currently loading display items.
    /// - Parameter accountId: The account UUID
    /// - Returns: True if loading
    func isLoadingDisplayItems(for accountId: UUID) -> Bool {
        loadingAccounts.contains(accountId)
    }

    /// Marks an account as loading display items.
    /// - Parameter accountId: The account UUID
    func startLoadingDisplayItems(for accountId: UUID) {
        loadingAccounts.insert(accountId)
    }

    /// Marks an account as finished loading display items.
    /// - Parameter accountId: The account UUID
    func finishLoadingDisplayItems(for accountId: UUID) {
        loadingAccounts.remove(accountId)
    }

    // MARK: - Sorting

    /// Sorts labels with system labels first (in standard order), then user labels alphabetically.
    /// - Parameter labels: The labels to sort
    /// - Returns: Sorted array of labels
    func sortLabels(_ labels: [Label]) -> [Label] {
        let systemOrder = ["INBOX", "STARRED", "SENT", "DRAFT", "SPAM", "TRASH"]

        let systemLabels = labels
            .filter { $0.type == .system }
            .sorted { label1, label2 in
                let index1 = systemOrder.firstIndex(of: label1.gmailLabelId) ?? Int.max
                let index2 = systemOrder.firstIndex(of: label2.gmailLabelId) ?? Int.max
                return index1 < index2
            }

        let userLabels = labels
            .filter { $0.type == .user }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return systemLabels + userLabels
    }

    /// Parses nested label name (e.g., "Work/Projects/Alpha" -> ["Work", "Projects", "Alpha"]).
    /// - Parameter name: The label name
    /// - Returns: Array of name components
    func parseNestedLabelName(_ name: String) -> [String] {
        name.components(separatedBy: "/")
    }

    /// Returns the display name (last component) of a potentially nested label.
    /// - Parameter name: The full label name
    /// - Returns: The display name
    func displayName(for name: String) -> String {
        parseNestedLabelName(name).last ?? name
    }

    /// Returns the indentation level for a nested label.
    /// - Parameter name: The label name
    /// - Returns: Indentation level (0 for top-level)
    func indentLevel(for name: String) -> Int {
        max(0, parseNestedLabelName(name).count - 1)
    }

    // MARK: - Private

    private func findEmail(gmailId: String) async throws -> Email? {
        let emailRepository = EmailRepository()
        return try await emailRepository.fetch(byGmailId: gmailId, context: databaseService.mainContext)
    }
}
