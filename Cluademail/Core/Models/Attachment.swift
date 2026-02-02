import Foundation
import SwiftData

/// Email attachment metadata with download state tracking.
/// Content is downloaded on demand, not with the email.
@Model
final class Attachment: Identifiable {

    // MARK: - Identity

    /// Local unique identifier
    @Attribute(.unique) var id: String

    /// Gmail attachment ID for downloading
    var gmailAttachmentId: String

    // MARK: - File Info

    /// Original filename
    var filename: String

    /// MIME type (e.g., "application/pdf")
    var mimeType: String

    /// File size in bytes
    var size: Int64

    /// Content-ID for inline images (CID scheme)
    var contentId: String?

    // MARK: - Download State

    /// Local file path after download (nil if not downloaded)
    var localPath: String?

    /// Whether the attachment has been downloaded
    var isDownloaded: Bool

    // MARK: - Relationships

    /// The email this attachment belongs to
    var email: Email?

    // MARK: - Computed Properties

    /// Human-readable file size (e.g., "1.2 MB")
    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // MARK: - Initialization

    /// Creates a new Attachment.
    /// - Parameters:
    ///   - id: Local unique identifier
    ///   - gmailAttachmentId: Gmail attachment ID
    ///   - filename: Original filename
    ///   - mimeType: MIME type
    ///   - size: File size in bytes
    init(
        id: String,
        gmailAttachmentId: String,
        filename: String,
        mimeType: String,
        size: Int64
    ) {
        self.id = id
        self.gmailAttachmentId = gmailAttachmentId
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.localPath = nil
        self.isDownloaded = false
    }
}
