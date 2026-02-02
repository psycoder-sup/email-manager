import SwiftUI

/// Popover form for adding and editing search filters.
struct FilterPickerPopover: View {
    @Binding var filters: SearchFilters
    @Binding var isPresented: Bool

    @State private var fromText: String = ""
    @State private var toText: String = ""
    @State private var afterDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var beforeDate: Date = Date()
    @State private var useAfterDate: Bool = false
    @State private var useBeforeDate: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Filters")
                .font(.headline)

            Form {
                // From filter
                TextField("From:", text: $fromText)

                // To filter
                TextField("To:", text: $toText)

                // Date range
                Section {
                    Toggle("After date", isOn: $useAfterDate)
                    if useAfterDate {
                        DatePicker("", selection: $afterDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    Toggle("Before date", isOn: $useBeforeDate)
                    if useBeforeDate {
                        DatePicker("", selection: $beforeDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    // Quick date presets
                    HStack(spacing: 8) {
                        Text("Quick:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Today") {
                            useAfterDate = true
                            afterDate = Calendar.current.startOfDay(for: Date())
                            useBeforeDate = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Last 7 days") {
                            useAfterDate = true
                            afterDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                            useBeforeDate = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Last 30 days") {
                            useAfterDate = true
                            afterDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                            useBeforeDate = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Boolean filters
                Section {
                    Toggle("Has attachment", isOn: Binding(
                        get: { filters.hasAttachment },
                        set: { filters.hasAttachment = $0 }
                    ))

                    Toggle("Unread only", isOn: Binding(
                        get: { filters.isUnread },
                        set: { filters.isUnread = $0 }
                    ))
                }
            }
            .formStyle(.grouped)

            // Date validation error
            if useAfterDate && useBeforeDate && afterDate > beforeDate {
                Text("Error: After date must be before the Before date")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Action buttons
            HStack {
                Button("Reset") {
                    resetForm()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("Apply") {
                    applyFilters()
                }
                .buttonStyle(.borderedProminent)
                .disabled(useAfterDate && useBeforeDate && afterDate > beforeDate)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            loadFromFilters()
        }
    }

    private func loadFromFilters() {
        fromText = filters.from ?? ""
        toText = filters.to ?? ""

        if let after = filters.afterDate {
            useAfterDate = true
            afterDate = after
        }

        if let before = filters.beforeDate {
            useBeforeDate = true
            beforeDate = before
        }
    }

    private func applyFilters() {
        filters.from = fromText.isEmpty ? nil : fromText
        filters.to = toText.isEmpty ? nil : toText
        filters.afterDate = useAfterDate ? afterDate : nil
        filters.beforeDate = useBeforeDate ? beforeDate : nil

        isPresented = false
    }

    private func resetForm() {
        fromText = ""
        toText = ""
        useAfterDate = false
        useBeforeDate = false
        filters.hasAttachment = false
        filters.isUnread = false
        filters.labelIds = []
    }
}

#Preview {
    FilterPickerPopover(
        filters: .constant(SearchFilters()),
        isPresented: .constant(true)
    )
}
