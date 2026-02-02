import SwiftUI
import QuickLook
import os.log

/// Displays a list of email attachments with download functionality.
struct AttachmentListView: View {
    let attachments: [Attachment]
    let email: Email

    @Environment(DatabaseService.self) private var databaseService

    /// Currently downloading attachment IDs
    @State private var downloadingIds: Set<String> = []

    /// Error message for download failures
    @State private var errorMessage: String?

    /// URL for Quick Look preview
    @State private var quickLookURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)

                Text("\(attachments.count) Attachment\(attachments.count == 1 ? "" : "s")")
                    .font(.headline)

                Spacer()

                // Download all button
                if attachments.count > 1 {
                    Button("Download All") {
                        Task {
                            await downloadAll()
                        }
                    }
                    .buttonStyle(.link)
                    .disabled(!downloadingIds.isEmpty)
                }
            }
            .padding(.horizontal)

            Divider()

            // Attachment grid
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)],
                spacing: 12
            ) {
                ForEach(attachments) { attachment in
                    AttachmentItemView(
                        attachment: attachment,
                        isDownloading: downloadingIds.contains(attachment.id),
                        onDownload: { await download(attachment) },
                        onQuickLook: { quickLook(attachment) }
                    )
                }
            }
            .padding(.horizontal)

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(nsColor: .controlBackgroundColor))
        .quickLookPreview($quickLookURL)
    }

    // MARK: - Actions

    private func download(_ attachment: Attachment) async {
        guard !downloadingIds.contains(attachment.id),
              let account = email.account else { return }

        downloadingIds.insert(attachment.id)
        errorMessage = nil

        defer {
            downloadingIds.remove(attachment.id)
        }

        do {
            let data = try await GmailAPIService.shared.getAttachment(
                accountEmail: account.email,
                messageId: email.gmailId,
                attachmentId: attachment.gmailAttachmentId
            )

            // Save to Downloads folder
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let fileURL = downloadsURL.appendingPathComponent(attachment.filename)

            // Handle duplicate filenames
            let finalURL = uniqueFileURL(for: fileURL)

            try data.write(to: finalURL)

            // Update attachment state
            attachment.localPath = finalURL.path
            attachment.isDownloaded = true
            try databaseService.mainContext.save()

            Logger.ui.info("Downloaded attachment: \(attachment.filename)")

            // Show in Finder
            NSWorkspace.shared.activateFileViewerSelecting([finalURL])

        } catch {
            Logger.ui.error("Failed to download attachment: \(error.localizedDescription)")
            errorMessage = "Failed to download \(attachment.filename)"
        }
    }

    private func downloadAll() async {
        for attachment in attachments {
            await download(attachment)
        }
    }

    private func quickLook(_ attachment: Attachment) {
        if let localPath = attachment.localPath {
            quickLookURL = URL(fileURLWithPath: localPath)
        } else {
            // Download first, then preview
            Task {
                await download(attachment)
                if let localPath = attachment.localPath {
                    quickLookURL = URL(fileURLWithPath: localPath)
                }
            }
        }
    }

    private func uniqueFileURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        var newURL: URL

        repeat {
            let newFilename = ext.isEmpty ? "\(filename) (\(counter))" : "\(filename) (\(counter)).\(ext)"
            newURL = directory.appendingPathComponent(newFilename)
            counter += 1
        } while fileManager.fileExists(atPath: newURL.path)

        return newURL
    }
}

/// Individual attachment item view.
struct AttachmentItemView: View {
    let attachment: Attachment
    let isDownloading: Bool
    let onDownload: () async -> Void
    let onQuickLook: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // File type icon
                fileIcon
                    .font(.title2)
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    // Filename
                    Text(attachment.filename)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    // File size
                    Text(attachment.displaySize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 8) {
                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else if attachment.isDownloaded {
                    Button {
                        onQuickLook()
                    } label: {
                        SwiftUI.Label("Preview", systemImage: "eye")
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                } else {
                    Button {
                        Task {
                            await onDownload()
                        }
                    } label: {
                        SwiftUI.Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if attachment.isDownloaded {
                onQuickLook()
            } else {
                Task {
                    await onDownload()
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var fileIcon: Image {
        let ext = (attachment.filename as NSString).pathExtension.lowercased()

        switch ext {
        case "pdf":
            return Image(systemName: "doc.fill")
        case "doc", "docx":
            return Image(systemName: "doc.text.fill")
        case "xls", "xlsx":
            return Image(systemName: "tablecells.fill")
        case "ppt", "pptx":
            return Image(systemName: "rectangle.split.3x1.fill")
        case "jpg", "jpeg", "png", "gif", "webp", "heic":
            return Image(systemName: "photo.fill")
        case "mp4", "mov", "avi":
            return Image(systemName: "film.fill")
        case "mp3", "wav", "m4a":
            return Image(systemName: "music.note")
        case "zip", "rar", "7z", "tar", "gz":
            return Image(systemName: "doc.zipper")
        case "txt", "rtf":
            return Image(systemName: "doc.plaintext.fill")
        case "html", "htm":
            return Image(systemName: "globe")
        case "json", "xml":
            return Image(systemName: "curlybraces")
        default:
            return Image(systemName: "doc.fill")
        }
    }

    private var iconColor: Color {
        let ext = (attachment.filename as NSString).pathExtension.lowercased()

        switch ext {
        case "pdf":
            return .red
        case "doc", "docx":
            return .blue
        case "xls", "xlsx":
            return .green
        case "ppt", "pptx":
            return .orange
        case "jpg", "jpeg", "png", "gif", "webp", "heic":
            return .purple
        case "mp4", "mov", "avi":
            return .pink
        case "mp3", "wav", "m4a":
            return .cyan
        case "zip", "rar", "7z", "tar", "gz":
            return .gray
        default:
            return .secondary
        }
    }
}

#Preview {
    let email = Email(
        gmailId: "123",
        threadId: "thread123",
        subject: "Test",
        snippet: "...",
        fromAddress: "sender@example.com",
        date: Date()
    )

    let attachments = [
        Attachment(id: "1", gmailAttachmentId: "att1", filename: "document.pdf", mimeType: "application/pdf", size: 1024 * 512),
        Attachment(id: "2", gmailAttachmentId: "att2", filename: "spreadsheet.xlsx", mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", size: 1024 * 128),
        Attachment(id: "3", gmailAttachmentId: "att3", filename: "photo.jpg", mimeType: "image/jpeg", size: 1024 * 1024 * 2)
    ]

    return AttachmentListView(attachments: attachments, email: email)
        .environment(DatabaseService(isStoredInMemoryOnly: true))
        .frame(width: 500)
}
