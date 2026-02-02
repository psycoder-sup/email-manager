import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os.log

/// Main compose view for creating and sending emails.
struct ComposeView: View {
    @Environment(AppState.self) private var appState
    @Environment(DatabaseService.self) private var databaseService
    @Environment(\.dismiss) private var dismiss

    let mode: ComposeMode
    let account: Account?
    let windowId: UUID
    let onClose: () -> Void

    /// Optional window data for reconstructing mode after window restore
    var windowData: ComposeWindowData?

    @State private var viewModel: ComposeViewModel?

    /// Reference to the text view for formatting
    @State private var textView: NSTextView?

    /// Whether to show the file picker
    @State private var showFilePicker: Bool = false

    /// Whether to show the discard confirmation
    @State private var showDiscardConfirmation: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel {
                // Header with recipient fields
                headerSection(viewModel: viewModel)

                Divider()

                // Formatting toolbar
                FormattingToolbar(
                    textView: textView,
                    onAttach: { showFilePicker = true }
                )

                Divider()

                // Body editor
                editorSection(viewModel: viewModel)

                // Attachments (if any)
                if !viewModel.attachments.isEmpty {
                    Divider()
                    attachmentsSection(viewModel: viewModel)
                }

                Divider()

                // Footer with send button
                footerSection(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 540, minHeight: 400)
        .navigationTitle(mode.windowTitle)
        .onAppear {
            // Initialize view model with resolved account (synchronous to avoid SwiftData threading issues)
            guard viewModel == nil else { return }
            let resolvedAccount = account ?? appState.accounts.first
            guard let resolvedAccount else { return }

            // Reconstruct mode from windowData if needed (for window restore scenarios)
            let resolvedMode = reconstructMode() ?? mode

            viewModel = ComposeViewModel(
                mode: resolvedMode,
                account: resolvedAccount,
                windowId: windowId,
                databaseService: databaseService
            )
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFilePicker(result)
        }
        .confirmationDialog(
            "Discard this message?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                Task {
                    await viewModel?.discardDraft()
                    closeWindow()
                }
            }
            Button("Save Draft") {
                Task {
                    await viewModel?.saveDraft()
                    closeWindow()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsent changes. Would you like to save this as a draft?")
        }
        .onDisappear {
            viewModel?.stopAutoSave()
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private func headerSection(viewModel: ComposeViewModel) -> some View {
        VStack(spacing: 8) {
            // From (read-only)
            HStack {
                Text("From:")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Text(viewModel.account.email)
                    .textSelection(.enabled)

                Spacer()
            }
            .padding(.horizontal)

            // To
            RecipientFieldView(
                label: "To:",
                recipients: Binding(
                    get: { viewModel.toRecipients },
                    set: {
                        viewModel.toRecipients = $0
                        viewModel.contentDidChange()
                    }
                ),
                placeholder: "Add recipients"
            )
            .padding(.horizontal)

            // CC/BCC toggle
            if !viewModel.showCcBcc {
                HStack {
                    Spacer()
                    Button("Cc/Bcc") {
                        withAnimation {
                            viewModel.showCcBcc = true
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .padding(.horizontal)
            }

            // CC (if visible)
            if viewModel.showCcBcc {
                RecipientFieldView(
                    label: "Cc:",
                    recipients: Binding(
                        get: { viewModel.ccRecipients },
                        set: {
                            viewModel.ccRecipients = $0
                            viewModel.contentDidChange()
                        }
                    ),
                    placeholder: ""
                )
                .padding(.horizontal)

                // BCC
                RecipientFieldView(
                    label: "Bcc:",
                    recipients: Binding(
                        get: { viewModel.bccRecipients },
                        set: {
                            viewModel.bccRecipients = $0
                            viewModel.contentDidChange()
                        }
                    ),
                    placeholder: ""
                )
                .padding(.horizontal)
            }

            // Subject
            HStack {
                Text("Subject:")
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)

                TextField("Subject", text: Binding(
                    get: { viewModel.subject },
                    set: {
                        viewModel.subject = $0
                        viewModel.contentDidChange()
                    }
                ))
                .textFieldStyle(.plain)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Editor Section

    @ViewBuilder
    private func editorSection(viewModel: ComposeViewModel) -> some View {
        RichTextEditor(
            text: Binding(
                get: { viewModel.body },
                set: {
                    viewModel.body = $0
                    viewModel.contentDidChange()
                }
            ),
            isHtml: Binding(
                get: { viewModel.isHtml },
                set: { viewModel.isHtml = $0 }
            ),
            placeholder: "Write your message here...",
            onTextChange: {
                viewModel.contentDidChange()
            }
        )
        .frame(minHeight: 200)
    }

    // MARK: - Attachments Section

    @ViewBuilder
    private func attachmentsSection(viewModel: ComposeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)

                Text("\(viewModel.attachments.count) attachment\(viewModel.attachments.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.attachmentSizeExceeded {
                    Text("(exceeds 25MB limit)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.attachments) { attachment in
                        ComposeAttachmentChip(
                            attachment: attachment,
                            onRemove: {
                                viewModel.removeAttachment(attachment)
                            }
                        )
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - Footer Section

    @ViewBuilder
    private func footerSection(viewModel: ComposeViewModel) -> some View {
        HStack {
            // Discard button
            Button("Discard") {
                if viewModel.hasChanges {
                    showDiscardConfirmation = true
                } else {
                    closeWindow()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])

            // Draft save indicator
            if let lastSave = viewModel.lastSaveDate {
                Text("Draft saved \(lastSave.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.isSavingDraft {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Error message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Send button
            Button {
                Task {
                    let success = await viewModel.send()
                    if success {
                        closeWindow()
                    }
                }
            } label: {
                if viewModel.isSending {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Sending...")
                    }
                } else {
                    Text("Send")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSend || viewModel.attachmentSizeExceeded)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    // MARK: - Actions

    private func handleFilePicker(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            viewModel?.addAttachments(urls: urls)
        case .failure(let error):
            Logger.ui.error("Failed to pick files: \(error.localizedDescription)")
        }
    }

    private func closeWindow() {
        onClose()
        dismiss()
    }

    /// Reconstructs the compose mode from windowData for window restore scenarios.
    /// - Returns: The reconstructed mode, or nil if no reconstruction is needed/possible.
    private func reconstructMode() -> ComposeMode? {
        guard let windowData, let emailId = windowData.emailId else {
            return nil
        }

        // Fetch the email from the database
        let fetchDescriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.gmailId == emailId }
        )

        guard let email = try? databaseService.mainContext.fetch(fetchDescriptor).first else {
            Logger.ui.warning("Could not find email for mode reconstruction: \(emailId, privacy: .private)")
            return nil
        }

        // Reconstruct the mode based on modeType
        switch windowData.modeType {
        case "reply":
            return .reply(email)
        case "replyAll":
            return .replyAll(email)
        case "forward":
            return .forward(email)
        case "draft":
            return .draft(email)
        default:
            return nil
        }
    }
}

// MARK: - Attachment Chip

struct ComposeAttachmentChip: View {
    let attachment: ComposeAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            fileIcon

            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.filename)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(attachment.displaySize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var fileIcon: some View {
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        let iconName: String
        let color: Color

        switch ext {
        case "pdf":
            iconName = "doc.fill"
            color = .red
        case "doc", "docx":
            iconName = "doc.text.fill"
            color = .blue
        case "xls", "xlsx":
            iconName = "tablecells.fill"
            color = .green
        case "jpg", "jpeg", "png", "gif", "webp":
            iconName = "photo.fill"
            color = .purple
        case "mp4", "mov":
            iconName = "film.fill"
            color = .pink
        case "zip", "rar":
            iconName = "doc.zipper"
            color = .gray
        default:
            iconName = "doc.fill"
            color = .secondary
        }

        return Image(systemName: iconName)
            .foregroundStyle(color)
    }
}

#Preview {
    ComposeView(
        mode: .new,
        account: nil,
        windowId: UUID(),
        onClose: {}
    )
    .environment(AppState())
    .environment(DatabaseService(isStoredInMemoryOnly: true))
}
