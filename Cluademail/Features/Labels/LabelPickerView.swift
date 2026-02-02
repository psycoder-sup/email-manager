import SwiftUI

/// A sheet for selecting labels to apply to an email.
struct LabelPickerView: View {
    let email: Email
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @Environment(DatabaseService.self) private var databaseService

    @State private var labelService: LabelService?
    @State private var labels: [Label] = []
    @State private var selectedLabelIds: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Labels")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                ProgressView("Loading labels...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await loadLabels() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if labels.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tag")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No user labels")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(labels) { label in
                    LabelRowView(
                        label: label,
                        isSelected: selectedLabelIds.contains(label.gmailLabelId)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await toggleLabel(label) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 300, height: 400)
        .onAppear {
            labelService = LabelService(databaseService: databaseService)
            selectedLabelIds = Set(email.labelIds)
        }
        .task {
            await loadLabels()
        }
    }

    private func loadLabels() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            labels = try await labelService?.getUserLabels(for: account) ?? []
        } catch {
            errorMessage = "Failed to load labels"
        }
    }

    private func toggleLabel(_ label: Label) async {
        guard let labelService else { return }

        let labelId = label.gmailLabelId
        let isCurrentlySelected = selectedLabelIds.contains(labelId)

        // Optimistically update UI
        if isCurrentlySelected {
            selectedLabelIds.remove(labelId)
        } else {
            selectedLabelIds.insert(labelId)
        }

        do {
            if isCurrentlySelected {
                try await labelService.removeLabel(labelId, from: email.gmailId, account: account)
            } else {
                try await labelService.applyLabel(labelId, to: email.gmailId, account: account)
            }
        } catch {
            // Revert on error
            if isCurrentlySelected {
                selectedLabelIds.insert(labelId)
            } else {
                selectedLabelIds.remove(labelId)
            }
            errorMessage = "Failed to update label"
        }
    }
}

/// A single label row in the picker.
struct LabelRowView: View {
    let label: Label
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            Circle()
                .fill(backgroundColor)
                .frame(width: 12, height: 12)

            // Label name with indentation for nested labels
            Text(displayName)
                .padding(.leading, CGFloat(indentLevel * 16))

            Spacer()

            // Checkmark
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        label.name.components(separatedBy: "/").last ?? label.name
    }

    private var indentLevel: Int {
        max(0, label.name.components(separatedBy: "/").count - 1)
    }

    private var backgroundColor: Color {
        Color(hex: label.backgroundColor) ?? .secondary
    }
}

// Preview requires actual Email and Account models from database, not shown here
