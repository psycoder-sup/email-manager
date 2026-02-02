import Foundation
import os.log

/// Resolves Content-ID (CID) references in HTML email bodies to actual image data.
/// CID references are used for inline images embedded in emails.
@MainActor
final class CIDResolver {

    // MARK: - Dependencies

    private let gmailAPIService: GmailAPIService

    // MARK: - Cache

    /// Cache of resolved CID data to avoid re-fetching
    private var cache: [String: Data] = [:]

    // MARK: - Initialization

    init(gmailAPIService: GmailAPIService = .shared) {
        self.gmailAPIService = gmailAPIService
    }

    // MARK: - Public Methods

    /// Resolves all CID references in HTML content.
    /// - Parameters:
    ///   - html: The HTML content with CID references
    ///   - email: The email containing the attachments
    /// - Returns: HTML with CID references replaced by data URIs
    func resolveAllCIDs(in html: String, email: Email) async -> String {
        guard let account = email.account else { return html }

        // Find all CID references
        let cidPattern = #"cid:([^"'\s>]+)"#
        guard let regex = try? NSRegularExpression(pattern: cidPattern) else {
            return html
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        // Collect unique CIDs
        var cids: Set<String> = []
        for match in matches {
            if let cidRange = Range(match.range(at: 1), in: html) {
                cids.insert(String(html[cidRange]))
            }
        }

        // Resolve each CID in parallel
        // First, check cache and identify which CIDs need fetching
        var resolved: [String: String] = [:]
        var cidsToFetch: Set<String> = []

        for cid in cids {
            if let cachedData = cache[cid] {
                resolved[cid] = dataURI(from: cachedData, mimeType: guessMimeType(for: cid))
            } else {
                cidsToFetch.insert(cid)
            }
        }

        // Fetch uncached CIDs in parallel, then batch-update cache
        // This pattern ensures cache writes happen after TaskGroup completes
        var fetchedData: [(String, Data, String)] = []

        await withTaskGroup(of: (String, Data?, String?).self) { group in
            for cid in cidsToFetch {
                group.addTask {
                    guard let (data, mimeType) = await self.fetchCIDData(cid, email: email, account: account) else {
                        return (cid, nil, nil)
                    }
                    return (cid, data, mimeType)
                }
            }
            for await (cid, data, mimeType) in group {
                if let data, let mimeType {
                    fetchedData.append((cid, data, mimeType))
                }
            }
        }

        // Batch-update cache and build data URIs (runs on MainActor after TaskGroup)
        for (cid, data, mimeType) in fetchedData {
            cache[cid] = data
            resolved[cid] = dataURI(from: data, mimeType: mimeType)
        }

        // Replace CID references with data URIs
        var result = html
        for (cid, dataURI) in resolved {
            result = result.replacingOccurrences(of: "cid:\(cid)", with: dataURI)
        }

        return result
    }

    /// Resolves a single CID reference to a data URI.
    /// Checks cache first, then fetches if needed.
    /// - Parameters:
    ///   - cid: The Content-ID to resolve
    ///   - email: The email containing the attachment
    ///   - account: The account for API access
    /// - Returns: A data URI string or nil if resolution fails
    private func resolveCID(_ cid: String, email: Email, account: Account) async -> String? {
        // Check cache first
        if let cachedData = cache[cid] {
            return dataURI(from: cachedData, mimeType: guessMimeType(for: cid))
        }

        // Fetch and cache
        guard let (data, mimeType) = await fetchCIDData(cid, email: email, account: account) else {
            return nil
        }

        cache[cid] = data
        return dataURI(from: data, mimeType: mimeType)
    }

    /// Fetches CID data from the API without caching.
    /// This method is safe to call from TaskGroup child tasks.
    /// - Parameters:
    ///   - cid: The Content-ID to resolve
    ///   - email: The email containing the attachment
    ///   - account: The account for API access
    /// - Returns: Tuple of (data, mimeType) or nil if fetch fails
    private func fetchCIDData(_ cid: String, email: Email, account: Account) async -> (Data, String)? {
        // Find the attachment with matching Content-ID
        let normalizedCID = cid.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard let attachment = email.attachments.first(where: {
            $0.contentId?.trimmingCharacters(in: CharacterSet(charactersIn: "<>")) == normalizedCID
        }) else {
            Logger.ui.debug("No attachment found for CID: \(cid, privacy: .private)")
            return nil
        }

        // Download the attachment data
        do {
            let data = try await gmailAPIService.getAttachment(
                accountEmail: account.email,
                messageId: email.gmailId,
                attachmentId: attachment.gmailAttachmentId
            )
            return (data, attachment.mimeType)
        } catch {
            Logger.ui.error("Failed to resolve CID \(cid, privacy: .private): \(error.localizedDescription)")
            return nil
        }
    }

    /// Creates a data URI from binary data.
    private func dataURI(from data: Data, mimeType: String) -> String {
        let base64 = data.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }

    /// Guesses MIME type from a CID reference.
    private func guessMimeType(for cid: String) -> String {
        let ext = (cid as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/png"
        }
    }

    /// Clears the cache.
    func clearCache() {
        cache.removeAll()
    }
}
