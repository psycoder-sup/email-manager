import SwiftUI
import os.log

/// Main view for displaying email details including header, body, and attachments.
struct EmailDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(DatabaseService.self) private var databaseService

    @State private var viewModel: EmailDetailViewModel?

    var body: some View {
        Group {
            if let email = appState.selectedEmail {
                emailContent(email)
            } else {
                emptyStateView
            }
        }
        .onAppear {
            // Initialize view model synchronously to avoid SwiftData threading issues
            if viewModel == nil {
                viewModel = EmailDetailViewModel(databaseService: databaseService, appState: appState)
            }
        }
        .task(id: appState.selectedEmail?.id) {
            // Load email asynchronously when selection changes
            guard let email = appState.selectedEmail else { return }
            await viewModel?.setEmail(email)
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private func emailContent(_ email: Email) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header section
                EmailHeaderView(email: email)

                Divider()

                // Loading indicator
                if viewModel?.isLoading == true {
                    loadingView
                } else if let errorMessage = viewModel?.errorMessage {
                    errorView(errorMessage)
                } else {
                    // Body section
                    EmailBodyView(
                        email: email,
                        loadExternalImages: viewModel?.loadExternalImages ?? false,
                        onAllowExternalImages: {
                            viewModel?.allowExternalImages()
                        },
                        resolvedBodyHtml: viewModel?.resolvedBodyHtml
                    )

                    // Attachments section (if any)
                    if !email.attachments.isEmpty {
                        Divider()
                        AttachmentListView(attachments: email.attachments, email: email)
                    }
                }
            }
        }
        .toolbar {
            emailToolbar(email)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.open")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select an email to read")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .glassEffect(.clear, in: .rect(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading email...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    await viewModel?.setEmail(appState.selectedEmail)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func emailToolbar(_ email: Email) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Reply button
            Button {
                openCompose(mode: .reply(email))
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            }
            .help("Reply")

            // Reply All button
            Button {
                openCompose(mode: .replyAll(email))
            } label: {
                Image(systemName: "arrowshape.turn.up.left.2")
            }
            .help("Reply All")

            // Forward button
            Button {
                openCompose(mode: .forward(email))
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
            }
            .help("Forward")

            Divider()

            // Archive button
            Button {
                Task {
                    await viewModel?.archive()
                }
            } label: {
                Image(systemName: "archivebox")
            }
            .help("Archive")
            .disabled(viewModel == nil)

            // Delete button
            Button {
                Task {
                    await viewModel?.moveToTrash()
                    appState.selectedEmail = nil
                }
            } label: {
                Image(systemName: "trash")
            }
            .help("Move to Trash")
            .disabled(viewModel == nil)

            Divider()

            // Star toggle
            Button {
                Task {
                    await viewModel?.toggleStar()
                }
            } label: {
                Image(systemName: email.isStarred ? "star.fill" : "star")
                    .foregroundStyle(email.isStarred ? .yellow : .primary)
            }
            .help(email.isStarred ? "Unstar" : "Star")
            .disabled(viewModel == nil)

            // Mark as unread
            Button {
                Task {
                    await viewModel?.markAsUnread()
                }
            } label: {
                Image(systemName: "envelope.badge")
            }
            .help("Mark as unread")
            .disabled(viewModel == nil)
        }

        // Print button
        ToolbarItem(placement: .secondaryAction) {
            Button {
                printEmail(email)
            } label: {
                SwiftUI.Label("Print", systemImage: "printer")
            }
            .keyboardShortcut("p", modifiers: .command)
        }
    }

    // MARK: - Actions

    private func openCompose(mode: ComposeMode) {
        // Post notification to open compose window
        NotificationCenter.default.post(
            name: .openComposeWindow,
            object: nil,
            userInfo: ["mode": mode]
        )
        Logger.ui.info("Opening compose in mode: \(String(describing: mode))")
    }

    private func printEmail(_ email: Email) {
        // Create printable HTML content
        let printHTML = buildPrintHTML(email)

        // Create a temporary file for printing
        let tempDir = FileManager.default.temporaryDirectory
        let printFile = tempDir.appendingPathComponent("email_print_\(email.gmailId).html")

        do {
            try printHTML.write(to: printFile, atomically: true, encoding: .utf8)

            // Open print dialog
            let printInfo = NSPrintInfo.shared
            printInfo.paperSize = NSSize(width: 612, height: 792) // Letter size
            printInfo.orientation = .portrait
            printInfo.scalingFactor = 1.0

            // Use NSWorkspace to open and print
            NSWorkspace.shared.open(printFile)

            Logger.ui.info("Printing email: \(email.gmailId, privacy: .private)")
        } catch {
            Logger.ui.error("Failed to prepare email for printing: \(error.localizedDescription)")
        }
    }

    private func buildPrintHTML(_ email: Email) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        let dateString = formatter.string(from: email.date)

        // Sanitize HTML content for printing
        let bodyContent: String
        if let html = email.bodyHtml {
            bodyContent = HTMLSanitizer.sanitize(html, plainTextFallback: email.bodyText)
        } else {
            bodyContent = email.bodyText?.replacingOccurrences(of: "\n", with: "<br>") ?? ""
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif;
                    font-size: 12pt;
                    line-height: 1.5;
                    max-width: 7.5in;
                    margin: 0 auto;
                    padding: 0.5in;
                }
                .header {
                    border-bottom: 1px solid #ccc;
                    padding-bottom: 12pt;
                    margin-bottom: 12pt;
                }
                .subject {
                    font-size: 16pt;
                    font-weight: bold;
                    margin-bottom: 8pt;
                }
                .meta {
                    font-size: 10pt;
                    color: #666;
                }
                .meta-row {
                    margin: 2pt 0;
                }
                .meta-label {
                    font-weight: bold;
                    display: inline-block;
                    width: 40pt;
                }
                .body {
                    margin-top: 12pt;
                }
                @media print {
                    body { padding: 0; }
                }
            </style>
        </head>
        <body>
            <div class="header">
                <div class="subject">\(escapeHTML(email.subject))</div>
                <div class="meta">
                    <div class="meta-row">
                        <span class="meta-label">From:</span>
                        \(escapeHTML(email.fromName ?? email.fromAddress)) &lt;\(escapeHTML(email.fromAddress))&gt;
                    </div>
                    <div class="meta-row">
                        <span class="meta-label">To:</span>
                        \(escapeHTML(email.toAddresses.joined(separator: ", ")))
                    </div>
                    \(email.ccAddresses.isEmpty ? "" : """
                    <div class="meta-row">
                        <span class="meta-label">Cc:</span>
                        \(escapeHTML(email.ccAddresses.joined(separator: ", ")))
                    </div>
                    """)
                    <div class="meta-row">
                        <span class="meta-label">Date:</span>
                        \(dateString)
                    </div>
                </div>
            </div>
            <div class="body">
                \(bodyContent)
            </div>
        </body>
        </html>
        """
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let openComposeWindow = Notification.Name("openComposeWindow")
}

#Preview {
    EmailDetailView()
        .environment(AppState())
        .environment(DatabaseService(isStoredInMemoryOnly: true))
        .frame(width: 600, height: 800)
}
