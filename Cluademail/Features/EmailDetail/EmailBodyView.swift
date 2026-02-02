import SwiftUI
import os.log

/// Displays the email body with support for HTML rendering and quote collapsing.
struct EmailBodyView: View {
    let email: Email
    let loadExternalImages: Bool
    let onAllowExternalImages: () -> Void

    /// Optional pre-resolved HTML with CID images converted to data URIs
    var resolvedBodyHtml: String?

    /// Whether quoted content is expanded
    @State private var isQuotedExpanded: Bool = false

    /// The effective HTML to display (resolved if available, otherwise raw)
    private var effectiveHtml: String? {
        resolvedBodyHtml ?? email.bodyHtml
    }

    /// Whether external images are being blocked
    private var hasBlockedImages: Bool {
        guard let html = effectiveHtml else { return false }
        // Check if there are external image URLs
        return html.contains("http://") || html.contains("https://")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // External images warning banner
            if !loadExternalImages && hasBlockedImages {
                externalImagesWarning
            }

            // HTML content
            if let html = effectiveHtml, !html.isEmpty {
                let sanitized = HTMLSanitizer.sanitize(html, plainTextFallback: email.bodyText)
                HTMLContentView(
                    html: processQuotedContent(sanitized),
                    plainText: nil,
                    loadExternalImages: loadExternalImages
                )
                .frame(minHeight: 200)
            } else if let plainText = email.bodyText, !plainText.isEmpty {
                // Plain text fallback
                HTMLContentView(
                    html: nil,
                    plainText: plainText,
                    loadExternalImages: false
                )
                .frame(minHeight: 200)
            } else {
                // No content
                noContentView
            }

            // Quoted content toggle (if quotes were collapsed)
            if hasQuotedContent && !isQuotedExpanded {
                quotedContentToggle
            }
        }
    }

    // MARK: - Subviews

    private var externalImagesWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.orange)

            Text("Images are blocked to protect your privacy.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Load Images") {
                onAllowExternalImages()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private var noContentView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No content")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var quotedContentToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isQuotedExpanded = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis")
                Text("Show quoted text")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding()
    }

    // MARK: - Quote Handling

    private var hasQuotedContent: Bool {
        guard let html = effectiveHtml else { return false }
        return containsQuotedContent(html)
    }

    private func containsQuotedContent(_ html: String) -> Bool {
        // Check for common quote indicators
        let quotePatterns = [
            "gmail_quote",
            "quote",
            "blockquote",
            "On .* wrote:",
            "wrote:",
            "---------- Forwarded message",
            "-----Original Message-----"
        ]

        for pattern in quotePatterns {
            if html.range(of: pattern, options: [.caseInsensitive, .regularExpression]) != nil {
                return true
            }
        }

        return false
    }

    private func processQuotedContent(_ html: String) -> String {
        guard !isQuotedExpanded else { return html }

        var processed = html

        // Hide Gmail quote blocks
        processed = hideQuoteBlocks(processed, className: "gmail_quote")

        // Hide generic blockquotes (but only top-level ones)
        // This is a simplified approach - a full implementation would use HTML parsing

        return processed
    }

    private func hideQuoteBlocks(_ html: String, className: String) -> String {
        // Add CSS to hide quote blocks
        let hideStyle = """
        <style>
            .\(className) { display: none; }
        </style>
        """

        // Insert style at the beginning of body or html
        if let bodyRange = html.range(of: "<body", options: .caseInsensitive) {
            var modified = html
            modified.insert(contentsOf: hideStyle, at: bodyRange.lowerBound)
            return modified
        } else if let htmlRange = html.range(of: "<html", options: .caseInsensitive) {
            var modified = html
            modified.insert(contentsOf: hideStyle, at: htmlRange.lowerBound)
            return modified
        }

        return hideStyle + html
    }
}

#Preview {
    EmailBodyView(
        email: Email(
            gmailId: "123",
            threadId: "thread123",
            subject: "Test Email",
            snippet: "Preview...",
            fromAddress: "sender@example.com",
            date: Date()
        ),
        loadExternalImages: false,
        onAllowExternalImages: {}
    )
    .frame(width: 600, height: 400)
}
