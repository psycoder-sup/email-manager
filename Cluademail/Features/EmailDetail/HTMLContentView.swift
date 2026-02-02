import SwiftUI
import WebKit
import os.log

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

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Security: Disable JavaScript
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        // Disable features we don't need
        configuration.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Disable zoom
        webView.allowsMagnification = false

        // Make background transparent
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
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
        Coordinator(loadExternalImages: loadExternalImages, onLinkClick: onLinkClick)
    }

    // MARK: - HTML Building

    private func buildHTMLContent() -> String {
        let bodyContent: String

        if let html, !html.isEmpty {
            bodyContent = processHTML(html)
        } else if let plainText, !plainText.isEmpty {
            bodyContent = "<pre style=\"white-space: pre-wrap; word-wrap: break-word; font-family: inherit;\">\(escapeHTML(plainText))</pre>"
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
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.5;
            color: var(--text-color, #333);
            background: transparent;
            margin: 0;
            padding: 16px;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        @media (prefers-color-scheme: dark) {
            body {
                color: #e0e0e0;
            }
            a {
                color: #6eb5ff;
            }
        }
        img {
            max-width: 100%;
            height: auto;
        }
        a {
            color: #0066cc;
        }
        blockquote {
            margin: 0.5em 0;
            padding-left: 1em;
            border-left: 2px solid #ccc;
            color: #666;
        }
        @media (prefers-color-scheme: dark) {
            blockquote {
                border-left-color: #555;
                color: #aaa;
            }
        }
        pre, code {
            font-family: "SF Mono", Monaco, "Courier New", monospace;
            font-size: 13px;
            background: rgba(128, 128, 128, 0.1);
            border-radius: 4px;
            padding: 2px 4px;
        }
        pre {
            padding: 8px;
            overflow-x: auto;
        }
        table {
            border-collapse: collapse;
            max-width: 100%;
        }
        td, th {
            border: 1px solid #ddd;
            padding: 8px;
        }
        @media (prefers-color-scheme: dark) {
            td, th {
                border-color: #444;
            }
        }
        /* Hide external images when not allowed */
        .external-image-blocked {
            display: none;
        }
        .image-placeholder {
            display: inline-block;
            background: rgba(128, 128, 128, 0.2);
            border-radius: 4px;
            padding: 8px 12px;
            color: #666;
            font-size: 12px;
        }
        @media (prefers-color-scheme: dark) {
            .image-placeholder {
                color: #999;
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

        init(loadExternalImages: Bool, onLinkClick: ((URL) -> Void)?) {
            self.loadExternalImages = loadExternalImages
            self.onLinkClick = onLinkClick
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
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Logger.ui.error("WebView failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    HTMLContentView(
        html: """
        <h1>Welcome!</h1>
        <p>This is a <strong>test email</strong> with some HTML content.</p>
        <blockquote>This is a quoted reply</blockquote>
        <p>Here's a <a href="https://example.com">link</a>.</p>
        """,
        plainText: nil,
        loadExternalImages: false
    )
    .frame(width: 600, height: 400)
}
