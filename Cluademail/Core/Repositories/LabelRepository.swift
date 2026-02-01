import Foundation
import SwiftData

final class LabelRepository: BaseRepository<Label>, LabelRepositoryProtocol {

    func fetchAll(account: Account, context: ModelContext) async throws -> [Label] {
        let accountId = account.id
        return try fetch(
            predicate: #Predicate<Label> { $0.account?.id == accountId },
            sortBy: [SortDescriptor(\.name)],
            context: context
        )
    }

    func fetch(byGmailId gmailLabelId: String, account: Account, context: ModelContext) async throws -> Label? {
        let accountId = account.id
        return try fetchOne(
            predicate: #Predicate<Label> { $0.gmailLabelId == gmailLabelId && $0.account?.id == accountId },
            context: context
        )
    }

    func save(_ label: Label, context: ModelContext) async throws {
        try super.save(label, context: context)
    }

    func saveAll(_ labels: [Label], context: ModelContext) async throws {
        try super.saveAll(labels, context: context)
    }
}
