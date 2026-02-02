import SwiftUI

/// A token-based recipient input field with email chip display.
struct RecipientFieldView: View {
    let label: String
    @Binding var recipients: [String]
    let placeholder: String

    /// Current text being typed
    @State private var inputText: String = ""

    /// Whether the field is focused
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Label
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            // Recipients + input field
            FlowLayout(spacing: 4) {
                // Existing recipient chips
                ForEach(recipients, id: \.self) { recipient in
                    RecipientChip(
                        email: recipient,
                        onRemove: {
                            recipients.removeAll { $0 == recipient }
                        }
                    )
                }

                // Input field
                TextField(recipients.isEmpty ? placeholder : "", text: $inputText)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 100)
                    .focused($isFocused)
                    .onSubmit {
                        addRecipient()
                    }
                    .onChange(of: inputText) { _, newValue in
                        // Check for comma or space to add recipient
                        if newValue.hasSuffix(",") || newValue.hasSuffix(" ") {
                            inputText = String(newValue.dropLast())
                            addRecipient()
                        }
                    }
            }
            .padding(4)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    private func addRecipient() {
        let email = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, isValidEmail(email), !recipients.contains(email) else {
            inputText = ""
            return
        }

        recipients.append(email)
        inputText = ""
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}

/// A single recipient displayed as a removable chip.
struct RecipientChip: View {
    let email: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(email)
                .font(.caption)
                .lineLimit(1)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }
}

/// A flow layout that wraps content to the next line.
struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let containerWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        return LayoutResult(
            positions: positions,
            height: currentY + rowHeight
        )
    }

    struct LayoutResult {
        let positions: [CGPoint]
        let height: CGFloat
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var recipients = ["john@example.com", "jane@example.com"]

        var body: some View {
            RecipientFieldView(
                label: "To:",
                recipients: $recipients,
                placeholder: "Add recipients"
            )
            .padding()
            .frame(width: 400)
        }
    }

    return PreviewWrapper()
}
