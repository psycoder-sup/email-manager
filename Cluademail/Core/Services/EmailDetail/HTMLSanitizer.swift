import Foundation
import os.log

/// Sanitizes HTML email content to handle malformed HTML and security concerns.
enum HTMLSanitizer {

    // MARK: - Configuration

    /// Maximum time allowed for sanitization before falling back to plain text.
    private static let timeout: TimeInterval = 5.0

    /// Maximum size of HTML to process (10MB).
    private static let maxSize = 10 * 1024 * 1024

    // MARK: - Dangerous Elements

    /// HTML tags that should be removed entirely (with content).
    private static let dangerousTags: Set<String> = [
        "script",
        "style",
        "iframe",
        "frame",
        "frameset",
        "object",
        "embed",
        "applet",
        "form",
        "input",
        "button",
        "select",
        "textarea"
    ]

    /// Attributes that should be removed from all elements.
    private static let dangerousAttributes: Set<String> = [
        "onclick",
        "ondblclick",
        "onmousedown",
        "onmouseup",
        "onmouseover",
        "onmouseout",
        "onmousemove",
        "onkeydown",
        "onkeyup",
        "onkeypress",
        "onfocus",
        "onblur",
        "onchange",
        "onsubmit",
        "onreset",
        "onload",
        "onerror",
        "onabort"
    ]

    // MARK: - Public Methods

    /// Sanitizes HTML content for safe display.
    /// - Parameters:
    ///   - html: The HTML to sanitize
    ///   - plainTextFallback: Plain text to use if sanitization fails
    /// - Returns: Sanitized HTML or plain text as HTML
    static func sanitize(_ html: String, plainTextFallback: String?) -> String {
        // Check size limit
        guard html.utf8.count <= maxSize else {
            Logger.ui.warning("HTML too large, falling back to plain text")
            return convertPlainTextToHTML(plainTextFallback ?? "Content too large to display")
        }

        // Use a task with timeout
        let result = withTimeout(timeout) {
            performSanitization(html)
        }

        if let sanitized = result {
            return sanitized
        } else {
            Logger.ui.warning("HTML sanitization timed out, falling back to plain text")
            return convertPlainTextToHTML(plainTextFallback ?? extractPlainText(from: html))
        }
    }

    // MARK: - Private Methods

    /// Performs the actual sanitization.
    private static func performSanitization(_ html: String) -> String {
        var result = html

        // Remove dangerous tags with their content
        for tag in dangerousTags {
            result = removeTags(result, tagName: tag, removeContent: true)
        }

        // Remove dangerous attributes
        for attribute in dangerousAttributes {
            result = removeAttribute(result, attributeName: attribute)
        }

        // Remove javascript: and data: URLs from href/src (except data:image)
        result = sanitizeURLs(result)

        // Fix common malformed HTML issues
        result = fixMalformedHTML(result)

        return result
    }

    /// Removes all instances of a tag from HTML.
    private static func removeTags(_ html: String, tagName: String, removeContent: Bool) -> String {
        if removeContent {
            // Remove opening tag, content, and closing tag
            let pattern = "<\(tagName)[^>]*>.*?</\(tagName)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(html.startIndex..., in: html)
                return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
            }
        } else {
            // Remove just the tags, keep content
            let openingPattern = "<\(tagName)[^>]*>"
            let closingPattern = "</\(tagName)>"

            var result = html

            if let openingRegex = try? NSRegularExpression(pattern: openingPattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = openingRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }

            if let closingRegex = try? NSRegularExpression(pattern: closingPattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = closingRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }

            return result
        }

        return html
    }

    /// Removes all instances of an attribute from HTML.
    private static func removeAttribute(_ html: String, attributeName: String) -> String {
        // Pattern matches attribute with quoted or unquoted values
        let pattern = #"\s*\#(attributeName)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return html
        }

        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    /// Sanitizes URLs in href and src attributes.
    private static func sanitizeURLs(_ html: String) -> String {
        var result = html

        // Remove javascript: URLs
        let jsPattern = #"(href|src)\s*=\s*["']?\s*javascript:[^"'\s>]*["']?"#
        if let jsRegex = try? NSRegularExpression(pattern: jsPattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = jsRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        // Remove data: URLs except for images
        let dataPattern = #"(href|src)\s*=\s*["']?\s*data:(?!image/)[^"'\s>]*["']?"#
        if let dataRegex = try? NSRegularExpression(pattern: dataPattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = dataRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        return result
    }

    /// Fixes common malformed HTML issues.
    private static func fixMalformedHTML(_ html: String) -> String {
        var result = html

        // Fix unclosed tags (basic approach)
        // This is a simplified fix - a full implementation would use proper HTML parsing

        // Remove orphan closing tags at the start
        let orphanClosingPattern = #"^(\s*</[^>]+>\s*)+"#
        if let orphanRegex = try? NSRegularExpression(pattern: orphanClosingPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = orphanRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        // Ensure proper HTML structure if missing
        if !result.lowercased().contains("<html") && !result.lowercased().contains("<body") {
            // It's probably just body content, wrap it
            result = """
            <!DOCTYPE html>
            <html>
            <head><meta charset="UTF-8"></head>
            <body>\(result)</body>
            </html>
            """
        }

        return result
    }

    /// Extracts plain text from HTML by removing all tags.
    private static func extractPlainText(from html: String) -> String {
        // Remove all HTML tags
        let tagPattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else {
            return html
        }

        let range = NSRange(html.startIndex..., in: html)
        var result = regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")

        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        // Clean up whitespace
        result = result
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return result
    }

    /// Converts plain text to displayable HTML.
    private static func convertPlainTextToHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, sans-serif;
                    font-size: 14px;
                    line-height: 1.5;
                    padding: 16px;
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }
            </style>
        </head>
        <body>\(escaped)</body>
        </html>
        """
    }

    /// Executes a closure with a timeout.
    private static func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () -> T) -> T? {
        var result: T?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            result = operation()
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        return waitResult == .success ? result : nil
    }
}
