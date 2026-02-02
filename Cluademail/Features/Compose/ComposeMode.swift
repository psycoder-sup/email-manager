import Foundation

/// Represents the mode of a compose window.
enum ComposeMode: Identifiable, Hashable {
    /// New email with no context
    case new

    /// Reply to a single sender
    case reply(Email)

    /// Reply to all recipients
    case replyAll(Email)

    /// Forward an email
    case forward(Email)

    /// Edit an existing draft
    case draft(Email)

    // MARK: - Identifiable

    var id: String {
        switch self {
        case .new:
            return "new"
        case .reply(let email):
            return "reply-\(email.gmailId)"
        case .replyAll(let email):
            return "replyAll-\(email.gmailId)"
        case .forward(let email):
            return "forward-\(email.gmailId)"
        case .draft(let email):
            return "draft-\(email.gmailId)"
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ComposeMode, rhs: ComposeMode) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Properties

    /// The original email being replied to, forwarded, or edited.
    var originalEmail: Email? {
        switch self {
        case .new:
            return nil
        case .reply(let email), .replyAll(let email), .forward(let email), .draft(let email):
            return email
        }
    }

    /// Whether this is a reply mode (reply or replyAll).
    var isReply: Bool {
        switch self {
        case .reply, .replyAll:
            return true
        default:
            return false
        }
    }

    /// The window title for this mode.
    var windowTitle: String {
        switch self {
        case .new:
            return "New Message"
        case .reply:
            return "Reply"
        case .replyAll:
            return "Reply All"
        case .forward:
            return "Forward"
        case .draft:
            return "Draft"
        }
    }

    // MARK: - Subject Generation

    /// Generates the subject line for this compose mode.
    func generateSubject() -> String {
        guard let email = originalEmail else { return "" }

        switch self {
        case .new:
            return ""
        case .reply, .replyAll:
            let subject = email.subject
            if subject.lowercased().hasPrefix("re:") {
                return subject
            }
            return "Re: \(subject)"
        case .forward:
            let subject = email.subject
            if subject.lowercased().hasPrefix("fwd:") {
                return subject
            }
            return "Fwd: \(subject)"
        case .draft:
            return email.subject
        }
    }

    // MARK: - Recipient Generation

    /// Generates the To recipients for this compose mode.
    func generateToRecipients(currentUserEmail: String) -> [String] {
        guard let email = originalEmail else { return [] }

        switch self {
        case .new:
            return []
        case .reply, .replyAll:
            // Reply to sender
            return [email.fromAddress]
        case .forward:
            // Forward starts with empty recipients
            return []
        case .draft:
            return email.toAddresses
        }
    }

    /// Generates the CC recipients for this compose mode.
    func generateCCRecipients(currentUserEmail: String) -> [String] {
        guard let email = originalEmail else { return [] }

        switch self {
        case .new, .reply, .forward:
            return []
        case .replyAll:
            // Include original To recipients (except current user) and CC recipients
            var ccRecipients = email.toAddresses.filter { $0.lowercased() != currentUserEmail.lowercased() }
            ccRecipients.append(contentsOf: email.ccAddresses.filter { $0.lowercased() != currentUserEmail.lowercased() })
            return ccRecipients
        case .draft:
            return email.ccAddresses
        }
    }

    // MARK: - Body Generation

    /// Generates the body content for this compose mode.
    func generateBody() -> String {
        guard let email = originalEmail else { return "" }

        switch self {
        case .new:
            return ""
        case .reply, .replyAll:
            return generateReplyBody(email)
        case .forward:
            return generateForwardBody(email)
        case .draft:
            return email.bodyHtml ?? email.bodyText ?? ""
        }
    }

    private func generateReplyBody(_ email: Email) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        let dateString = formatter.string(from: email.date)

        let senderName = email.fromName ?? email.fromAddress
        let quotedBody = email.bodyHtml ?? email.bodyText ?? ""

        return """
        <br><br>
        <div class="gmail_quote">
            <div>On \(dateString), \(escapeHTML(senderName)) &lt;\(escapeHTML(email.fromAddress))&gt; wrote:</div>
            <blockquote style="margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex">
                \(quotedBody)
            </blockquote>
        </div>
        """
    }

    private func generateForwardBody(_ email: Email) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        let dateString = formatter.string(from: email.date)

        let senderName = email.fromName ?? email.fromAddress
        let originalBody = email.bodyHtml ?? email.bodyText ?? ""

        return """
        <br><br>
        <div class="gmail_forward">
            <div>---------- Forwarded message ----------</div>
            <div>From: \(escapeHTML(senderName)) &lt;\(escapeHTML(email.fromAddress))&gt;</div>
            <div>Date: \(dateString)</div>
            <div>Subject: \(escapeHTML(email.subject))</div>
            <div>To: \(escapeHTML(email.toAddresses.joined(separator: ", ")))</div>
            <br>
            \(originalBody)
        </div>
        """
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
