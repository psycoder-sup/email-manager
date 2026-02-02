import Foundation

// MARK: - Gmail Model Mapper

/// Maps Gmail API DTOs to app models.
enum GmailModelMapper {

    // MARK: - Email Mapping

    /// Maps a Gmail message DTO to an Email model.
    /// - Parameters:
    ///   - dto: The Gmail message DTO
    ///   - account: The associated account
    /// - Returns: An Email model
    static func mapToEmail(_ dto: GmailMessageDTO, account: Account) throws -> Email {
        let headers = extractHeaders(dto.payload?.headers)

        // Extract body content from payload
        let (plainText, htmlBody) = extractBodies(dto.payload)

        // Determine read/starred status from labels
        let labelIds = dto.labelIds ?? []
        let isRead = !labelIds.contains("UNREAD")
        let isStarred = labelIds.contains("STARRED")

        // Parse date from internalDate (milliseconds since epoch)
        let date: Date
        if let internalDate = dto.internalDate,
           let milliseconds = Int64(internalDate) {
            date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        } else {
            date = headers.date ?? Date()
        }

        let email = Email(
            gmailId: dto.id,
            threadId: dto.threadId,
            subject: headers.subject,
            snippet: dto.snippet ?? "",
            fromAddress: headers.fromAddress,
            fromName: headers.fromName,
            toAddresses: headers.toAddresses,
            ccAddresses: headers.ccAddresses,
            bccAddresses: headers.bccAddresses,
            date: date,
            isRead: isRead,
            isStarred: isStarred,
            labelIds: labelIds
        )

        // Set body content if available
        email.bodyText = plainText
        email.bodyHtml = htmlBody

        // Associate with account
        email.account = account

        // Map attachments
        email.attachments = extractAttachments(dto.payload)

        return email
    }

    // MARK: - Header Parsing

    /// Parsed headers from a message.
    struct ParsedHeaders {
        let subject: String
        let fromAddress: String
        let fromName: String?
        let toAddresses: [String]
        let ccAddresses: [String]
        let bccAddresses: [String]
        let date: Date?
        let inReplyTo: String?
        let references: String?
    }

    /// Extracts and parses headers from a header array.
    private static func extractHeaders(_ headers: [HeaderDTO]?) -> ParsedHeaders {
        guard let headers else {
            return ParsedHeaders(
                subject: "", fromAddress: "", fromName: nil,
                toAddresses: [], ccAddresses: [], bccAddresses: [],
                date: nil, inReplyTo: nil, references: nil
            )
        }

        var result = (
            subject: "", from: "",
            to: [String](), cc: [String](), bcc: [String](),
            date: nil as Date?, inReplyTo: nil as String?, references: nil as String?
        )

        for header in headers {
            let value = decodeRFC2047(header.value)

            switch header.name.lowercased() {
            case "subject": result.subject = value
            case "from": result.from = value
            case "to": result.to = parseAddressList(value)
            case "cc": result.cc = parseAddressList(value)
            case "bcc": result.bcc = parseAddressList(value)
            case "date": result.date = parseRFC2822Date(value)
            case "in-reply-to": result.inReplyTo = value
            case "references": result.references = value
            default: break
            }
        }

        let (fromAddress, fromName) = parseEmailAddress(result.from)

        return ParsedHeaders(
            subject: result.subject,
            fromAddress: fromAddress,
            fromName: fromName,
            toAddresses: result.to,
            ccAddresses: result.cc,
            bccAddresses: result.bcc,
            date: result.date,
            inReplyTo: result.inReplyTo,
            references: result.references
        )
    }

    /// Parses "Name <email>" format into components.
    private static func parseEmailAddress(_ value: String) -> (email: String, name: String?) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Pattern: "Name <email@example.com>" or "<email@example.com>" or "email@example.com"
        if let angleStart = trimmed.lastIndex(of: "<"),
           let angleEnd = trimmed.lastIndex(of: ">"),
           angleStart < angleEnd {
            let email = String(trimmed[trimmed.index(after: angleStart)..<angleEnd])
                .trimmingCharacters(in: .whitespaces)
            let name = String(trimmed[..<angleStart])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (email, name.isEmpty ? nil : name)
        }

        // Just an email address
        return (trimmed, nil)
    }

    /// Parses a comma-separated list of email addresses.
    private static func parseAddressList(_ value: String) -> [String] {
        // Split by comma, but be careful with quoted strings
        var addresses: [String] = []
        var current = ""
        var inQuotes = false

        for char in value {
            if char == "\"" {
                inQuotes.toggle()
                current.append(char)
            } else if char == "," && !inQuotes {
                let (email, _) = parseEmailAddress(current)
                if !email.isEmpty {
                    addresses.append(email)
                }
                current = ""
            } else {
                current.append(char)
            }
        }

        // Don't forget the last one
        let (email, _) = parseEmailAddress(current)
        if !email.isEmpty {
            addresses.append(email)
        }

        return addresses
    }

    // MARK: - Date Parsing

    /// Parses an RFC 2822 date string.
    private static func parseRFC2822Date(_ value: String) -> Date? {
        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss z",
            "dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss z"
        ]

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formatters {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    // MARK: - Body Extraction

    /// Extracts plain text and HTML bodies from a payload.
    private static func extractBodies(_ payload: PayloadDTO?) -> (plainText: String?, html: String?) {
        guard let payload else { return (nil, nil) }

        var plainText: String?
        var html: String?

        // Check direct body
        if let mimeType = payload.mimeType, let data = payload.body?.data {
            switch mimeType {
            case "text/plain": plainText = data.base64URLDecodedString()
            case "text/html": html = data.base64URLDecodedString()
            default: break
            }
        }

        // Check parts recursively
        if let parts = payload.parts {
            let (partPlain, partHtml) = extractBodiesFromParts(parts)
            plainText = plainText ?? partPlain
            html = html ?? partHtml
        }

        return (plainText, html)
    }

    /// Recursively extracts bodies from message parts.
    private static func extractBodiesFromParts(_ parts: [PartDTO]) -> (plainText: String?, html: String?) {
        var plainText: String?
        var html: String?

        for part in parts {
            // Check this part's body (skip if it has a filename - that's an attachment)
            let isAttachment = part.filename.map { !$0.isEmpty } ?? false
            if !isAttachment, let mimeType = part.mimeType, let data = part.body?.data {
                switch (mimeType, plainText, html) {
                case ("text/plain", nil, _): plainText = data.base64URLDecodedString()
                case ("text/html", _, nil): html = data.base64URLDecodedString()
                default: break
                }
            }

            // Recurse into nested parts
            if let nestedParts = part.parts {
                let (nestedPlain, nestedHtml) = extractBodiesFromParts(nestedParts)
                plainText = plainText ?? nestedPlain
                html = html ?? nestedHtml
            }
        }

        return (plainText, html)
    }

    // MARK: - Attachment Extraction

    /// Extracts attachment metadata from a payload.
    private static func extractAttachments(_ payload: PayloadDTO?) -> [Attachment] {
        guard let payload else { return [] }

        var attachments: [Attachment] = []
        extractAttachmentsFromParts(payload.parts ?? [], into: &attachments)
        return attachments
    }

    /// Recursively extracts attachments from message parts.
    private static func extractAttachmentsFromParts(_ parts: [PartDTO], into attachments: inout [Attachment]) {
        for part in parts {
            // Check if this part is an attachment
            if let filename = part.filename, !filename.isEmpty,
               let attachmentId = part.body?.attachmentId {
                let attachment = Attachment(
                    id: UUID().uuidString,
                    gmailAttachmentId: attachmentId,
                    filename: filename,
                    mimeType: part.mimeType ?? "application/octet-stream",
                    size: Int64(part.body?.size ?? 0)
                )

                // Extract Content-ID for inline images (CID scheme)
                if let headers = part.headers {
                    for header in headers {
                        if header.name.lowercased() == "content-id" {
                            attachment.contentId = header.value
                            break
                        }
                    }
                }

                attachments.append(attachment)
            }

            // Recurse into nested parts
            if let nestedParts = part.parts {
                extractAttachmentsFromParts(nestedParts, into: &attachments)
            }
        }
    }

    // MARK: - RFC 2047 Decoding

    /// Decodes RFC 2047 encoded-word syntax for international characters.
    /// Format: =?charset?encoding?encoded_text?=
    static func decodeRFC2047(_ value: String) -> String {
        // Simple pattern matching for encoded words
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        var result = value
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))

        // Process in reverse to maintain correct ranges
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: value),
                  let charsetRange = Range(match.range(at: 1), in: value),
                  let encodingRange = Range(match.range(at: 2), in: value),
                  let textRange = Range(match.range(at: 3), in: value) else {
                continue
            }

            let charset = String(value[charsetRange])
            let encoding = String(value[encodingRange]).uppercased()
            let encodedText = String(value[textRange])

            var decodedText: String?

            if encoding == "B" {
                // Base64 encoding
                if let data = Data(base64Encoded: encodedText) {
                    decodedText = decodeWithCharset(data, charset: charset)
                }
            } else if encoding == "Q" {
                // Quoted-printable encoding
                let unescaped = encodedText
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "=", with: "%")
                if let decoded = unescaped.removingPercentEncoding {
                    decodedText = decoded
                }
            }

            if let decoded = decodedText {
                result.replaceSubrange(fullRange, with: decoded)
            }
        }

        return result
    }

    /// Decodes data with a specific charset.
    private static func decodeWithCharset(_ data: Data, charset: String) -> String? {
        let encoding: String.Encoding

        switch charset.lowercased() {
        case "utf-8":
            encoding = .utf8
        case "iso-8859-1", "latin1":
            encoding = .isoLatin1
        case "iso-8859-2", "latin2":
            encoding = .isoLatin2
        case "windows-1252", "cp1252":
            encoding = .windowsCP1252
        case "us-ascii", "ascii":
            encoding = .ascii
        default:
            encoding = .utf8
        }

        return String(data: data, encoding: encoding)
    }
}
