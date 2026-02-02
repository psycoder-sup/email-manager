import SwiftUI
import WebKit
import os.log

// MARK: - Scroll-Forwarding WebView

/// A WKWebView subclass that forwards scroll wheel events to its parent scroll view.
/// This allows the WebView to be embedded in a SwiftUI ScrollView without capturing scroll events.
final class ScrollForwardingWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // Forward scroll events to the next responder (parent scroll view)
        nextResponder?.scrollWheel(with: event)
    }
}

// MARK: - HTMLContentView

/// A WKWebView wrapper for displaying HTML email content securely.
struct HTMLContentView: NSViewRepresentable {
    /// The HTML content to display
    let html: String?

    /// Plain text fallback if no HTML
    let plainText: String?

    /// Whether to load external images
    let loadExternalImages: Bool

    /// Called when a link is clicked
    var onLinkClick: ((URL) -> Void)?

    /// Binding to report the content height for dynamic sizing
    @Binding var contentHeight: CGFloat

    func makeNSView(context: Context) -> ScrollForwardingWebView {
        let configuration = WKWebViewConfiguration()

        // Enable JavaScript for content height measurement
        // This is safe since we control the HTML content
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Disable features we don't need
        configuration.preferences.isElementFullscreenEnabled = false

        let webView = ScrollForwardingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Disable zoom
        webView.allowsMagnification = false

        // Make background transparent
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ webView: ScrollForwardingWebView, context: Context) {
        context.coordinator.loadExternalImages = loadExternalImages
        context.coordinator.onLinkClick = onLinkClick

        let content = buildHTMLContent()

        // Only reload if content changed
        let contentHash = content.hashValue
        if context.coordinator.lastContentHash != contentHash {
            context.coordinator.lastContentHash = contentHash
            webView.loadHTMLString(content, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(loadExternalImages: loadExternalImages, onLinkClick: onLinkClick, contentHeight: $contentHeight)
    }

    // MARK: - HTML Building

    private func buildHTMLContent() -> String {
        let bodyContent: String

        if let html, !html.isEmpty {
            bodyContent = processHTML(html)
        } else if let plainText, !plainText.isEmpty {
            bodyContent = "<pre class=\"plain-text-fallback\">\(escapeHTML(plainText))</pre>"
        } else {
            bodyContent = "<p style=\"color: gray;\">No content</p>"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                \(cssStyles)
            </style>
        </head>
        <body>
            \(bodyContent)
        </body>
        </html>
        """
    }

    private var cssStyles: String {
        """
        :root {
            color-scheme: light dark;
        }
        /* Minimal base styles - let emails define their own design */
        body {
            background: transparent;
            margin: 0;
            padding: 8px;
        }
        /* Only style plain text fallback content */
        pre.plain-text-fallback {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.5;
            color: #333;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        @media (prefers-color-scheme: dark) {
            pre.plain-text-fallback {
                color: #e0e0e0;
            }
        }
        /* Hide external images when not allowed */
        .external-image-blocked {
            display: none;
        }
        .image-placeholder {
            display: inline-block;
            background: rgba(128, 128, 128, 0.1);
            border: 1px dashed rgba(128, 128, 128, 0.3);
            border-radius: 4px;
            padding: 8px 12px;
            color: #666;
            font-size: 12px;
        }
        @media (prefers-color-scheme: dark) {
            .image-placeholder {
                color: #999;
                border-color: rgba(128, 128, 128, 0.4);
            }
        }
        """
    }

    private func processHTML(_ html: String) -> String {
        var processed = html

        // If external images are blocked, replace img tags with placeholders
        if !loadExternalImages {
            processed = blockExternalImages(processed)
        }

        return processed
    }

    private func blockExternalImages(_ html: String) -> String {
        // Simple regex to find and replace external images
        // This is a basic implementation - a more robust solution would use proper HTML parsing
        let pattern = #"<img\s+[^>]*src\s*=\s*["']?(https?://[^"'\s>]+)["']?[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return html
        }

        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(
            in: html,
            range: range,
            withTemplate: "<span class=\"image-placeholder\">[Image blocked]</span>"
        )
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var loadExternalImages: Bool
        var onLinkClick: ((URL) -> Void)?
        var lastContentHash: Int?
        @Binding var contentHeight: CGFloat

        init(loadExternalImages: Bool, onLinkClick: ((URL) -> Void)?, contentHeight: Binding<CGFloat>) {
            self.loadExternalImages = loadExternalImages
            self.onLinkClick = onLinkClick
            self._contentHeight = contentHeight
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Allow initial page load
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Handle link clicks - open in default browser
            if let url = navigationAction.request.url {
                Logger.ui.info("Link clicked: \(url.absoluteString, privacy: .public)")

                if let onLinkClick {
                    onLinkClick(url)
                } else {
                    NSWorkspace.shared.open(url)
                }
            }

            // Don't navigate within the webview
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Logger.ui.debug("WebView finished loading")
            // Use JavaScript to measure document height
            measureContentHeight(webView)
        }

        private func measureContentHeight(_ webView: WKWebView) {
            let script = "document.body.scrollHeight"
            webView.evaluateJavaScript(script) { [weak self] result, error in
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        self?.contentHeight = height
                    }
                } else if let error {
                    Logger.ui.error("Failed to measure content height: \(error.localizedDescription)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Logger.ui.error("WebView failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var contentHeight: CGFloat = 200

        var body: some View {
            HTMLContentView(
                html: """
                <h1>Welcome!</h1>
                <p>This is a <strong>test email</strong> with some HTML content.</p>
                <blockquote>This is a quoted reply</blockquote>
                <p>Here's a <a href="https://example.com">link</a>.</p>
                """,
                plainText: nil,
                loadExternalImages: false,
                contentHeight: $contentHeight
            )
            .frame(width: 600, height: contentHeight)
        }
    }

    return PreviewWrapper()
}
