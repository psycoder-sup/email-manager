import Foundation
import SwiftData

/// MCP tool for listing all configured email accounts.
final class ListAccountsTool: MCPToolProtocol, @unchecked Sendable {

    let name = "list_accounts"
    let description = "List all configured email accounts with their sync status"

    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            inputSchema: JSONSchema(
                properties: [:],
                required: []
            )
        )
    }

    private let databaseService: MCPDatabaseService

    init(databaseService: MCPDatabaseService) {
        self.databaseService = databaseService
    }

    func execute(arguments: [String: AnyCodable]?) async throws -> String {
        let accounts = try await databaseService.performRead { context in
            let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.email)])
            return try context.fetch(descriptor)
        }

        return formatAccountList(accounts)
    }

    // MARK: - Private

    private func formatAccountList(_ accounts: [Account]) -> String {
        guard !accounts.isEmpty else {
            return "No accounts configured."
        }

        var output = "Found \(accounts.count) account\(accounts.count == 1 ? "" : "s"):\n\n"

        for (index, account) in accounts.enumerated() {
            output += "\(index + 1). \(account.email)\n"
            output += "   Name: \(account.displayName)\n"
            output += "   Status: \(account.isEnabled ? "Enabled" : "Disabled")\n"
            output += "   Last Sync: \(formatLastSync(account.lastSyncDate))\n"
            output += "   Emails: \(formatCount(account.emails.count))\n"

            if index < accounts.count - 1 {
                output += "\n"
            }
        }

        return output
    }

    private func formatLastSync(_ date: Date?) -> String {
        guard let date = date else {
            return "Never"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }
}
