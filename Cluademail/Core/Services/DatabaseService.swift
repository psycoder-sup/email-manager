import Foundation
import SwiftData
import os.log

@Observable
@MainActor
final class DatabaseService {
    let container: ModelContainer

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
}
