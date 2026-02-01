import Foundation
import SwiftData
import os.log

class BaseRepository<T: PersistentModel>: @unchecked Sendable {

    func fetch(
        predicate: Predicate<T>? = nil,
        sortBy: [SortDescriptor<T>] = [],
        limit: Int? = nil,
        offset: Int? = nil,
        context: ModelContext
    ) throws -> [T] {
        var descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
        if let limit { descriptor.fetchLimit = limit }
        if let offset { descriptor.fetchOffset = offset }

        do {
            return try context.fetch(descriptor)
        } catch {
            Logger.database.error("Fetch failed for \(String(describing: T.self)): \(error.localizedDescription)")
            throw DatabaseError.fetchFailed(error)
        }
    }

    func fetchOne(predicate: Predicate<T>, context: ModelContext) throws -> T? {
        try fetch(predicate: predicate, limit: 1, context: context).first
    }

    func count(predicate: Predicate<T>? = nil, context: ModelContext) throws -> Int {
        do {
            return try context.fetchCount(FetchDescriptor<T>(predicate: predicate))
        } catch {
            Logger.database.error("Count failed for \(String(describing: T.self)): \(error.localizedDescription)")
            throw DatabaseError.fetchFailed(error)
        }
    }

    func save(_ model: T, context: ModelContext) throws {
        do {
            context.insert(model)
            try context.save()
        } catch {
            Logger.database.error("Save failed for \(String(describing: T.self)): \(error.localizedDescription)")
            throw DatabaseError.saveFailed(error)
        }
    }

    func saveAll(_ models: [T], context: ModelContext) throws {
        guard !models.isEmpty else { return }

        do {
            models.forEach { context.insert($0) }
            try context.save()
        } catch {
            Logger.database.error("Batch save failed for \(String(describing: T.self)): \(error.localizedDescription)")
            throw DatabaseError.saveFailed(error)
        }
    }

    func delete(_ model: T, context: ModelContext) throws {
        do {
            context.delete(model)
            try context.save()
        } catch {
            Logger.database.error("Delete failed for \(String(describing: T.self)): \(error.localizedDescription)")
            throw DatabaseError.deleteFailed(error)
        }
    }
}
