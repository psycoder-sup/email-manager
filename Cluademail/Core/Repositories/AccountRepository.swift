import Foundation
import SwiftData

final class AccountRepository: BaseRepository<Account>, AccountRepositoryProtocol {

    func fetchAll(context: ModelContext) async throws -> [Account] {
        try fetch(sortBy: [SortDescriptor(\.email)], context: context)
    }

    func fetch(byId id: UUID, context: ModelContext) async throws -> Account? {
        try fetchOne(predicate: #Predicate { $0.id == id }, context: context)
    }

    func fetch(byEmail email: String, context: ModelContext) async throws -> Account? {
        try fetchOne(predicate: #Predicate { $0.email == email }, context: context)
    }

    func save(_ account: Account, context: ModelContext) async throws {
        try super.save(account, context: context)
    }

    func delete(_ account: Account, context: ModelContext) async throws {
        try super.delete(account, context: context)
    }
}
