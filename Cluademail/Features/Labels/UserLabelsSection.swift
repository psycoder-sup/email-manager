import SwiftUI
import os.log

/// Displays user labels in the sidebar for the selected account.
struct UserLabelsSection: View {
    let account: Account
    let labelService: LabelService
    @Environment(DatabaseService.self) private var databaseService

    @State private var displayLabels: [LabelService.DisplayItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if displayLabels.isEmpty {
                Text("No labels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayLabels) { item in
                    labelRow(for: item)
                }
            }
        }
        .task(id: account.id) {
            await loadLabels()
        }
    }

    @ViewBuilder
    private func labelRow(for item: LabelService.DisplayItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: item.backgroundColor) ?? .secondary)
                .frame(width: 8, height: 8)
            Text(item.name.components(separatedBy: "/").last ?? item.name)
                .lineLimit(1)
        }
        .padding(.leading, CGFloat(max(0, item.name.components(separatedBy: "/").count - 1) * 12))
    }

    private func loadLabels() async {
        let accountId = account.id

        // Check cache first (thread-safe via LabelService's @MainActor isolation)
        if let cached = labelService.getDisplayItems(for: accountId) {
            displayLabels = cached
            isLoading = false
            return
        }

        // Prevent concurrent loads for same account
        guard !labelService.isLoadingDisplayItems(for: accountId) else {
            return
        }
        labelService.startLoadingDisplayItems(for: accountId)
        defer { labelService.finishLoadingDisplayItems(for: accountId) }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch labels directly from repository
            let labelRepository = LabelRepository()
            let allLabels = try await labelRepository.fetchAll(account: account, context: databaseService.mainContext)
            let userLabels = allLabels.filter { $0.type == .user }

            // Convert to display items (breaks SwiftData observation)
            let items = userLabels.map { LabelService.DisplayItem(from: $0) }

            // Store in service cache (thread-safe)
            labelService.setDisplayItems(items, for: accountId)
            displayLabels = items
            isLoading = false
        } catch {
            Logger.ui.error("Failed to load labels: \(error.localizedDescription)")
            errorMessage = "Failed to load"
            isLoading = false
        }
    }
}
