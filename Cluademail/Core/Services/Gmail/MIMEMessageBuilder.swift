import Foundation

/// Builds RFC 2822 MIME messages for sending and drafts.
enum MIMEMessageBuilder {

    /// Builds a complete MIME message and returns it as a Base64URL encoded string.
    /// - Parameters:
    ///   - from: Sender's email address
    ///   - to: Recipients
    ///   - cc: CC recipients
    ///   - bcc: BCC recipients
    ///   - subject: Email subject
    ///   - body: Email body content
    ///   - isHtml: Whether body is HTML
    ///   - replyToMessageId: Message ID for replies (adds In-Reply-To header)
    ///   - attachments: File attachments
    /// - Returns: Base64URL encoded raw message
    static func buildMessage(
        from: String,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        body: String,
        isHtml: Bool,
        replyToMessageId: String?,
        attachments: [AttachmentData]
    ) -> String {
        var message = ""

        // MIME version
        message += "MIME-Version: 1.0\r\n"

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        message += "Date: \(dateFormatter.string(from: Date()))\r\n"

        // From (sanitize and encode if needed)
        message += "From: \(encodeHeaderValue(from))\r\n"

        // Recipients
        message += formatRecipientHeader("To", addresses: to)
        message += formatRecipientHeader("Cc", addresses: cc)
        message += formatRecipientHeader("Bcc", addresses: bcc)

        // Subject (sanitize and encode if needed)
        message += "Subject: \(encodeHeaderValue(subject))\r\n"

        // Reply headers
        if let replyToMessageId {
            let sanitizedId = sanitizeHeaderValue(replyToMessageId)
            message += "In-Reply-To: <\(sanitizedId)>\r\nReferences: <\(sanitizedId)>\r\n"
        }

        // Build body based on attachments
        if attachments.isEmpty {
            // Simple message without attachments
            message += buildSimpleBody(body: body, isHtml: isHtml)
        } else {
            // Multipart message with attachments
            message += buildMultipartBody(body: body, isHtml: isHtml, attachments: attachments)
        }

        // Base64URL encode the entire message
        guard let messageData = message.data(using: .utf8) else {
            return ""
        }

        return messageData.base64URLEncodedString()
    }

    // MARK: - Private Helpers

    /// Formats a recipient header line (To, Cc, Bcc).
    private static func formatRecipientHeader(_ name: String, addresses: [String]) -> String {
        guard !addresses.isEmpty else { return "" }
        let encoded = addresses.map { encodeHeaderValue($0) }.joined(separator: ", ")
        return "\(name): \(encoded)\r\n"
    }

    /// Sanitizes a header value by removing CR/LF characters to prevent header injection attacks.
    private static func sanitizeHeaderValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    /// Encodes a header value using RFC 2047 if it contains non-ASCII characters.
    /// Also sanitizes the value to prevent header injection.
    private static func encodeHeaderValue(_ value: String) -> String {
        // First sanitize to prevent header injection
        let sanitized = sanitizeHeaderValue(value)

        // Check if encoding is needed (non-ASCII characters)
        let needsEncoding = sanitized.unicodeScalars.contains { !$0.isASCII }

        if needsEncoding {
            guard let data = sanitized.data(using: .utf8) else {
                return sanitized
            }
            let base64 = data.base64EncodedString()
            return "=?UTF-8?B?\(base64)?="
        }

        return sanitized
    }

    /// Builds a simple message body without attachments.
    private static func buildSimpleBody(body: String, isHtml: Bool) -> String {
        var result = ""

        let contentType = isHtml ? "text/html" : "text/plain"
        result += "Content-Type: \(contentType); charset=\"UTF-8\"\r\n"
        result += "Content-Transfer-Encoding: base64\r\n"
        result += "\r\n"

        // Base64 encode body
        if let bodyData = body.data(using: .utf8) {
            // Split into 76-character lines for RFC compliance
            let base64 = bodyData.base64EncodedString(options: .lineLength76Characters)
            result += base64
        }

        return result
    }

    /// Builds a multipart message body with attachments.
    private static func buildMultipartBody(
        body: String,
        isHtml: Bool,
        attachments: [AttachmentData]
    ) -> String {
        // Use a strong boundary that's unlikely to appear in content
        let boundary = "====_MIME_BOUNDARY_\(UUID().uuidString)_===="

        var result = ""
        result += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n"
        result += "\r\n"

        // Text body part
        result += "--\(boundary)\r\n"
        let contentType = isHtml ? "text/html" : "text/plain"
        result += "Content-Type: \(contentType); charset=\"UTF-8\"\r\n"
        result += "Content-Transfer-Encoding: base64\r\n"
        result += "\r\n"

        if let bodyData = body.data(using: .utf8) {
            let base64 = bodyData.base64EncodedString(options: .lineLength76Characters)
            result += base64
            result += "\r\n"
        }

        // Attachment parts
        for attachment in attachments {
            // Sanitize filename to prevent injection
            let safeFilename = sanitizeHeaderValue(attachment.filename)
            let safeMimeType = sanitizeHeaderValue(attachment.mimeType)

            result += "--\(boundary)\r\n"
            result += "Content-Type: \(safeMimeType); name=\"\(safeFilename)\"\r\n"
            result += "Content-Disposition: attachment; filename=\"\(safeFilename)\"\r\n"
            result += "Content-Transfer-Encoding: base64\r\n"
            result += "\r\n"

            let base64 = attachment.data.base64EncodedString(options: .lineLength76Characters)
            result += base64
            result += "\r\n"
        }

        // Closing boundary
        result += "--\(boundary)--\r\n"

        return result
    }
}
