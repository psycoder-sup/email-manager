import Foundation
import SwiftData
import os.log

final class SyncStateRepository: BaseRepository<SyncState>, SyncStateRepositoryProtocol, @unchecked Sendable {

    func fetch(accountId: UUID, context: ModelContext) async throws -> SyncState? {
        try fetchOne(predicate: #Predicate { $0.accountId == accountId }, context: context)
    }

    func save(_ syncState: SyncState, context: ModelContext) async throws {
        try super.save(syncState, context: context)
    }

    func updateHistoryId(_ historyId: String, for accountId: UUID, context: ModelContext) async throws {
        guard let syncState = try await fetch(accountId: accountId, context: context) else {
            throw DatabaseError.notFound(entityType: "SyncState", identifier: accountId.uuidString)
        }

        syncState.historyId = historyId

        do {
            try context.save()
        } catch {
            Logger.database.error("Failed to update historyId: \(error.localizedDescription)")
            throw DatabaseError.saveFailed(error)
        }
    }
}
