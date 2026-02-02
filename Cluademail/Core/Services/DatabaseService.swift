import Foundation
import SwiftData
import os.log

@Observable
@MainActor
final class DatabaseService {
    let container: ModelContainer

    /// Version counter to signal data changes for debugging
    private var refreshVersion: Int = 0

    var mainContext: ModelContext {
        container.mainContext
    }

    init(isStoredInMemoryOnly: Bool = false) {
        let schema = Schema([
            Account.self,
            Email.self,
            EmailThread.self,
            Attachment.self,
            Label.self,
            SyncState.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )

        do {
            self.container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            Logger.database.info("DatabaseService initialized successfully")
        } catch {
            Logger.database.fault("Failed to create ModelContainer: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    func newBackgroundContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    // MARK: - Context Refresh

    /// Refreshes the main context to pick up changes from background contexts.
    /// Call this after a background sync saves to ensure UI sees updated data.
    func refreshMainContext() {
        mainContext.processPendingChanges()
        refreshVersion += 1
        Logger.database.debug("Main context refreshed, version: \(self.refreshVersion)")
    }

    // MARK: - Data Repair

    /// Repairs orphaned emails by reassigning them to their correct accounts.
    ///
    /// Orphaned emails (those with `account == nil`) are matched to accounts by:
    /// - For received emails: checking if account's email is in `toAddresses`
    /// - For sent emails: checking if account's email matches `fromAddress`
    func repairOrphanedEmails() throws {
        let accounts = try mainContext.fetch(FetchDescriptor<Account>())

        guard !accounts.isEmpty else {
            Logger.database.info("No accounts found, skipping orphan repair")
            return
        }

        let orphanedEmails = try mainContext.fetch(
            FetchDescriptor<Email>(predicate: #Predicate { $0.account == nil })
        )

        guard !orphanedEmails.isEmpty else {
            Logger.database.debug("No orphaned emails found")
            return
        }

        var repairedCount = 0

        for email in orphanedEmails {
            for account in accounts {
                let accountEmailLower = account.email.lowercased()

                // Check if this account sent the email
                if email.fromAddress.lowercased() == accountEmailLower {
                    email.account = account
                    repairedCount += 1
                    break
                }

                // Check if this account received the email
                let toAddressesLower = email.toAddresses.map { $0.lowercased() }
                if toAddressesLower.contains(accountEmailLower) {
                    email.account = account
                    repairedCount += 1
                    break
                }

                // Also check CC addresses
                let ccAddressesLower = email.ccAddresses.map { $0.lowercased() }
                if ccAddressesLower.contains(accountEmailLower) {
                    email.account = account
                    repairedCount += 1
                    break
                }
            }
        }

        if repairedCount > 0 {
            try mainContext.save()
            Logger.database.info("Repaired \(repairedCount) orphaned emails out of \(orphanedEmails.count) total")
        } else {
            Logger.database.warning("Found \(orphanedEmails.count) orphaned emails but could not match any to accounts")
        }
    }
}
