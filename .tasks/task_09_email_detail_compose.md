# Task 09: Email Detail & Compose

## Task Overview

Build the email reading pane for viewing full email content with HTML rendering and the compose window for creating new emails, replies, and forwards with attachment support.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 02: Core Data Models
- Task 05: Gmail API Service
- Task 07: Main Window & Navigation

## Architectural Guidelines

### Design Patterns
- **Delegation**: Compose view reports actions to parent
- **Builder Pattern**: Build email message structure
- **State Machine**: Track compose state (draft, sending, sent)

### SwiftUI/Swift Conventions
- Use `WKWebView` wrapped for HTML rendering
- Use `NSViewRepresentable` for AppKit integration
- Use sheets/windows for compose modal

### File Organization
```
Features/EmailDetail/
├── EmailDetailView.swift
├── EmailHeaderView.swift
├── EmailBodyView.swift
├── HTMLContentView.swift
├── AttachmentListView.swift
├── ExternalImagePolicy.swift   # Image loading controls
└── ThreadExpandedView.swift

Features/Compose/
├── ComposeView.swift
├── ComposeViewModel.swift
├── RecipientField.swift
├── AttachmentPicker.swift
├── RichTextEditor.swift        # HTML/rich text composing
├── FormattingToolbar.swift     # Bold, italic, links, etc.
├── DraftAutoSaveManager.swift  # Auto-save logic
└── ComposeWindowManager.swift  # Multiple compose windows
```

## Implementation Details

### EmailDetailView

**Purpose**: Full email content display
**Type**: SwiftUI View

**States**:
- Email selected: Show email content
- Thread selected: Show ThreadExpandedView
- Nothing selected: Show placeholder ("Select an email to read")

**Structure**:
- ScrollView containing:
  - EmailHeaderView (padded)
  - Divider
  - EmailBodyView (padded)
  - Divider (if attachments)
  - AttachmentListView (if attachments)

**Toolbar**:
- Reply, Reply All, Forward buttons
- Divider
- Archive, Delete buttons

**Behavior**:
- Mark as read on appear (if unread)
- Sheet for compose (reply/forward)

---

### EmailHeaderView

**Purpose**: Display email metadata
**Type**: SwiftUI View

**Elements**:
- Subject (title2, semibold)
- From: Avatar, name, email address
- To: Recipients (expandable if many)
- Cc: Recipients (shown when expanded)
- Date: Absolute date and time
- Account badge (via account)

**Expand/Collapse**:
- "More"/"Less" button to show all recipients and CC
- Default collapsed if > 1 To recipient or has CC

---

### EmailBodyView

**Purpose**: Display email body (HTML or plain text)
**Type**: SwiftUI View

**Content Priority**:
1. HTML body (if available and not showing plain text)
2. Plain text body
3. "No content" placeholder

**View Toggle**:
- Button to switch between HTML and plain text (if both available)

---

### HTMLContentView

**Purpose**: Render HTML email content safely
**Type**: NSViewRepresentable wrapping WKWebView

**Security Configuration**:
- Disable JavaScript (`allowsContentJavaScript = false`)
- Text interaction enabled
- Transparent background

**HTML Wrapper Styles**:
```css
body {
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    font-size: 14px;
    line-height: 1.5;
    color: #333;
    margin: 0;
    padding: 0;
    background: transparent;
}
img { max-width: 100%; height: auto; }
a { color: #007AFF; }
blockquote {
    border-left: 3px solid #ccc;
    margin-left: 0;
    padding-left: 16px;
    color: #666;
}
@media (prefers-color-scheme: dark) {
    body { color: #fff; }
    a { color: #0A84FF; }
    blockquote { border-color: #555; color: #aaa; }
}
```

**Link Handling**:
- Intercept link clicks via WKNavigationDelegate
- Open external links in default browser (NSWorkspace.shared.open)
- Allow internal navigation (cancel external)

**Loading State**:
- Track isLoading via delegate callbacks
- Show progress indicator while loading

---

### Malformed HTML Handling

**Purpose**: Gracefully handle broken or unusual HTML in emails

**Common Issues**:
| Issue | Detection | Solution |
|-------|-----------|----------|
| Missing closing tags | HTML parsing errors | Use HTML5 parser (tolerant) |
| Invalid encoding | Mojibake characters | Detect charset, re-decode |
| Nested tables (newsletters) | Deep nesting | Limit nesting, simplify |
| Inline styles overflow | CSS causes horizontal scroll | Wrap in container, constrain width |
| Script tags (blocked) | `<script>` present | Already stripped, log attempt |
| Broken image refs | 404 errors | Replace with placeholder |
| Giant fonts | Font-size > 48px | Cap at reasonable size |

**HTML Sanitization Pipeline**:
1. Fix encoding issues - detect charset from meta tag, handle mojibake patterns
2. Remove dangerous elements (script, iframe, object, embed)
3. Sanitize inline styles - constrain widths, handle overflow
4. Fix broken tags using HTML5 tolerant parser
5. Wrap in responsive container with style constraints

**Encoding Detection**:
- Extract charset from meta tag if present
- Check for mojibake patterns (garbled characters)
- Try common encodings (ISO-8859-1, Windows-1252) if UTF-8 fails

**Style Constraints**:
```css
/* Injected into email wrapper */
.email-content * {
    max-width: 100% !important;
    box-sizing: border-box !important;
}
.email-content table {
    table-layout: fixed !important;
    width: 100% !important;
}
.email-content img {
    max-width: 100% !important;
    height: auto !important;
}
.email-content pre, .email-content code {
    white-space: pre-wrap !important;
    word-wrap: break-word !important;
}
```

**Fallback Chain**:
1. Try rendering sanitized HTML
2. If WebView crashes or hangs (5s timeout): show plain text
3. If no plain text: show snippet with "Unable to display email" message
4. Offer "View raw source" option for debugging

**Error Reporting**:
- Log malformed HTML issues (anonymized)
- Track which senders produce broken emails
- Consider reporting to user: "This email may not display correctly"

---

### Inline Images (CID Attachments)

**Purpose**: Display images embedded in email body via Content-ID references

**CID Format**:
```html
<!-- In HTML body -->
<img src="cid:image001.png@01D12345.ABCDEF00">

<!-- Corresponding attachment header -->
Content-Type: image/png
Content-ID: <image001.png@01D12345.ABCDEF00>
Content-Disposition: inline
```

**CID Resolution**:
- CIDResolver struct takes array of attachments
- `resolveHTML()` method:
  - Find all `cid:` references using regex pattern `src=["']cid:([^"']+)["']`
  - For each match, find attachment by Content-ID
  - Replace CID reference with data URL (`data:{mimeType};base64,{base64data}`)
- `createDataURL()`: Convert attachment data to base64 data URL
- Return empty placeholder if attachment data is nil

**Lazy Loading CID Images**:
1. Initially render HTML with placeholder for CID images
2. When email displayed, fetch attachment data for inline images only
3. Inject data URLs and refresh WebView

**CID vs External Images**:
- CID images are part of the email—always display them
- External images are remote—apply ExternalImagePolicy
- Don't block CID images even when external images are blocked

---

### Print Support

**Purpose**: Allow users to print email content

**Print Flow**:
1. User clicks Print (Cmd+P) or File > Print
2. Generate print-optimized HTML
3. Pass to system print dialog

**Implementation**:
- `printEmail()` method:
  1. Generate print-optimized HTML with header fields and body
  2. Write to temporary file in temporaryDirectory
  3. Load into WKWebView (A4 size: 595x842)
  4. After short delay for load, call `printOperation(with:).run()`

**Print-Optimized HTML Guidelines**:
- Use `@page { margin: 1in; }` for proper print margins
- Serif font (Georgia) at 12pt for readability
- Header section with border-bottom containing From, To, Date, Subject fields
- Body section with 1.6 line-height
- `@media print` rule to show link URLs after anchor text
- Constrain images to max-width: 100%

**Menu Integration**:
- Add to app menu: File > Print (Cmd+P)
- Only enabled when email is selected
- Include "Print Thread" option for conversation view

**Attachment Handling in Print**:
- List attachment names at bottom of print
- Don't embed large attachments
- Optional: print attachment previews for images/PDFs

---

### Quote Detection & Collapsing

**Purpose**: Collapse lengthy quoted replies for better readability

**Quote Patterns**:
| Pattern | Example |
|---------|---------|
| Gmail style | `<div class="gmail_quote">` |
| Outlook style | `<div id="divRplyFwdMsg">` |
| Plain text | Lines starting with `>` |
| Date line | "On {date}, {name} wrote:" |
| Separator | "---------- Forwarded message ----------" |

**Quote Detection**:
- QuoteDetector with static selectors:
  - Gmail: `.gmail_quote`
  - Outlook: `#divRplyFwdMsg, .MsoNormal`
  - Plain text: Lines starting with `>`
  - "wrote" pattern: `On .+, .+ wrote:$`
- `detectQuotes(in:)` method returns array of QuoteRange identifying quote blocks

**Collapsible Quote UI**:
- Track `isExpanded` state (default false)
- Toggle button with chevron icon and "Show/Hide quoted text" label
- When expanded, show HTMLContentView with max height 300pt
- Visual indicator: 3pt wide secondary color bar on leading edge

**Quote Trimming Strategy**:
1. Detect quote blocks in HTML
2. If quote is > 5 lines, collapse by default
3. Show preview of first 2 lines
4. "..." ellipsis button to expand
5. Remember expansion state per email (session only)

**Plain Text Quote Handling**:
- Process text line by line
- Lines starting with `>` styled as quotes:
  - Secondary foreground color
  - Italic font
- Non-quote lines use default styling
- Return AttributedString with appropriate formatting

---

### Signature Handling

**Purpose**: Handle existing Gmail signatures in replies/forwards

**Note**: Per PRD, per-account signature configuration is out of scope for v1. However, we must handle existing signatures properly.

**Detection of Existing Signatures**:
- SignatureDetector with common signature patterns:
  - Standard delimiter: `--` followed by whitespace
  - Gmail signature div: `<div class="gmail_signature">`
  - Outlook style: `<div id="Signature">`
  - Mobile signatures: "Sent from my iPhone", "Get Outlook for iOS"
- `detectSignature(in:)` returns range of signature block if found

**Reply/Forward Behavior**:
1. When replying, preserve user's Gmail signature if present in original
2. Don't duplicate signatures
3. Place cursor before signature if present

**Compose Signature Handling**:
- In setupReply, start with blank lines for user input
- Add quoted original message below
- Gmail adds signature on send if configured in Gmail settings
- Don't add signature ourselves in v1

**Future Consideration** (v2):
- Add signature management in Settings
- Per-account signature configuration
- Rich text signature support

---

### External Image Policy (Privacy)

**Purpose**: Control loading of remote images to prevent tracking
**Type**: Enum

**Options**:
- `blockAll` - Never load external images (default for privacy)
- `allowTrusted` - Load from known safe domains
- `allowAll` - Load all external images

**Implementation**:
- Parse HTML content, find all `<img src="...">` tags
- For blocked images, replace src with placeholder
- Show "Load images" button in email header area
- When user clicks, reload with images allowed (per-email basis)

**Blocked Image Placeholder**:
- Show gray box with "image blocked" icon
- Tooltip: "Image blocked for privacy"

**Tracking Prevention**:
- Block images from known tracking domains
- Block 1x1 pixel images (tracking pixels)
- Block images with tracking query parameters (utm_*, etc.)

**User Setting**:
- Default: `blockAll`
- Per-sender override: "Always load images from {sender}"
- Stored in UserDefaults

---

### AttachmentListView

**Purpose**: Display and interact with attachments
**Type**: SwiftUI View

**Layout**:
- Header: "Attachments (N)"
- LazyVGrid with adaptive columns (min 150pt)
- AttachmentItemView for each attachment

---

### AttachmentItemView

**Purpose**: Single attachment display
**Type**: SwiftUI View

**Elements**:
- Icon based on MIME type
- Filename (1 line)
- File size (displaySize)
- Download progress (if downloading)

**MIME Type Icons**:
| Type Prefix | Icon |
|------------|------|
| image/ | photo |
| video/ | film |
| audio/ | music.note |
| application/pdf | doc.richtext |
| zip/archive | doc.zipper |
| default | doc |

**Actions**:
- Tap: Download and open
- Context menu: Download, Quick Look

---

### ComposeMode

**Purpose**: Identify compose context
**Type**: Enum

**Cases**:
- `new` - Fresh email
- `reply(Email)` - Reply to sender
- `replyAll(Email)` - Reply to all
- `forward(Email)` - Forward email

---

### ComposeView

**Purpose**: Compose new email or reply/forward
**Type**: SwiftUI View

**Layout**:
- Toolbar row: Attach button, Format toggle, spacer, save status
- Form:
  - From picker (account selector)
  - To (RecipientField)
  - Cc/Bcc (toggle to show, RecipientField)
  - Subject (TextField)
  - Attachments list (if any)
- FormattingToolbar (when rich text mode)
- Body (RichTextEditor or plain TextEditor)

**Toolbar**:
- Cancel button (cancellation action)
- Send button (confirmation action, Cmd+Return)

**Constraints**:
- Minimum size: 600x500

---

### ComposeViewModel

**Purpose**: Compose state and logic
**Type**: `@Observable` class

**Properties**:
- `selectedAccount`: Account?
- `toRecipients`, `ccRecipients`, `bccRecipients`: [String]
- `subject`, `body`: String
- `attachments`: [AttachmentData]
- `showCcBcc`: Bool
- `isSending`, `isSaving`: Bool
- `errorMessage`: String?
- `availableAccounts`: [Account]

**Computed**:
- `canSend`: Has account, has recipients, has subject, not sending

**Setup by Mode**:
- **new**: Empty
- **reply**: To = original sender, Subject = "Re: ..." (if not already), body = quoted reply
- **replyAll**: To = sender + original To (minus self), Cc = original Cc (minus self)
- **forward**: Subject = "Fwd: ..." (if not already), body = forwarded message header

**Methods**:
- `send() async` - Create draft (AI constraint) or send (user action)
- `saveDraft() async` - Save to Gmail drafts
- `showAttachmentPicker()` - Open NSOpenPanel
- `removeAttachment(_:)`

**Quoted Reply Format**:
```
On {date}, {name} wrote:
> original line 1
> original line 2
```

**Forwarded Message Format**:
```
---------- Forwarded message ---------
From: {name} <{email}>
Date: {date}
Subject: {subject}
To: {recipients}

{body}
```

---

### RecipientField

**Purpose**: Token-based email input
**Type**: SwiftUI View

**Layout**:
- Label (To/Cc/Bcc)
- FlowLayout containing:
  - RecipientChip for each recipient
  - TextField for new input

**RecipientChip**:
- Email text
- X button to remove
- Capsule background

**Input Handling**:
- On submit: validate email format, add to recipients, clear input
- Validate: non-empty, contains @, not duplicate

---

### RichTextEditor (PRD Requirement)

**Purpose**: HTML/rich text email composition
**Type**: NSViewRepresentable wrapping NSTextView

**Why NSTextView over WKWebView**:
- Native rich text editing support
- Better performance for editing
- RTF to HTML conversion built-in

**Formatting Capabilities**:
- Bold (Cmd+B)
- Italic (Cmd+I)
- Underline (Cmd+U)
- Font size (increase/decrease)
- Text color
- Bullet list
- Numbered list
- Hyperlinks (Cmd+K)
- Blockquote

**FormattingToolbar Layout**:
```
[B] [I] [U] | [A↑] [A↓] | [Color] | [•] [1.] | [🔗] | [❝]
```

**HTML Generation**:
- Convert NSAttributedString to HTML on send
- Use `NSAttributedString.DocumentType.html` export
- Clean up generated HTML (remove Office-style classes)

**Plain Text Toggle**:
- User can switch between rich text and plain text modes
- Warn if switching will lose formatting
- Strip HTML tags when converting to plain

**isHtml Property**:
- Track compose mode (rich vs plain)
- Set Content-Type accordingly when sending

---

### DraftAutoSaveManager

**Purpose**: Periodically save drafts to prevent data loss
**Type**: Class

**Configuration**:
- Auto-save interval: 30 seconds (configurable)
- Debounce: Wait 2 seconds after last keystroke before saving

**Trigger Conditions**:
- Content changed since last save
- At least 2 seconds since last edit
- At least 30 seconds since last save

**Save Flow**:
1. Check if content differs from last saved
2. Call GmailAPIService.createDraft or updateDraft
3. Store draft ID for future updates
4. Update "Saved" indicator in toolbar

**Draft State Tracking**:
- `draftId`: String? (nil until first save)
- `lastSavedContent`: String (for change detection)
- `lastSaveDate`: Date?
- `isSaving`: Bool
- `hasUnsavedChanges`: Bool

**Visual Indicator**:
- "Draft saved" (gray, timestamp)
- "Saving..." (with spinner)
- "Unsaved changes" (yellow dot)

**Edge Cases**:
- Window close with unsaved: Show confirmation dialog
- Network failure: Queue save, retry, show error badge
- Discard draft: Delete from Gmail API

---

### ComposeWindowManager

**Purpose**: Handle multiple compose windows
**Type**: Singleton class

**Problem**: User may want multiple compose windows simultaneously

**Window Management**:
- Track open compose windows: `[UUID: NSWindow]`
- Each compose gets unique window ID
- Independent state per window

**Creating New Window**:
```swift
func openComposeWindow(mode: ComposeMode, account: Account?) -> UUID
```

**Window Configuration**:
- Style: `.titled`, `.closable`, `.miniaturizable`, `.resizable`
- Minimum size: 600x500
- Title: "New Message" / "Re: Subject" / "Fwd: Subject"
- Not part of main window tab group

**Close Behavior**:
- Prompt if unsaved changes
- Remove from tracking dictionary
- Clean up associated draft if discarded

**Keyboard Shortcut**:
- Cmd+N: New compose window
- Cmd+Shift+N: New compose in same window (sheet)

---

### Key Considerations

- **HTML Security**: Disable JavaScript, sanitize content
- **Quoted Reply**: Include original message properly formatted
- **Draft Auto-Save**: Auto-save every 30 seconds with 2-second debounce
- **Account Selection**: Auto-select account for replies (same as original)
- **Attachment Size**: Display human-readable sizes
- **Keyboard Shortcuts**: Cmd+Enter to send, Cmd+B/I/U for formatting
- **External Images**: Block by default for privacy, allow per-email/sender
- **Rich Text**: Support bold, italic, links, lists (PRD requirement)
- **Multiple Windows**: Support simultaneous compose windows

## Acceptance Criteria

- [x] Email detail view shows full header (from, to, cc, date)
- [x] HTML emails render correctly with proper styling
- [x] Plain text emails display properly
- [x] Links open in external browser
- [x] Attachments list shows with file icons
- [x] Attachments can be downloaded/opened
- [x] Compose window opens for new email
- [x] Reply pre-fills recipient and quoted text
- [x] Reply All includes all recipients
- [x] Forward includes forwarded message header
- [x] Account selector works for composing
- [x] Cc/Bcc fields can be shown/hidden
- [x] Attachments can be added via picker
- [x] Attachments can be removed
- [x] Send button disabled when validation fails
- [x] Cmd+Enter sends email
- [x] Empty state shows when no email selected
- [x] **External images loaded** by default (changed from blocked per user preference)
- [x] **Rich text editor** supports bold, italic, underline, links, lists
- [x] **Formatting toolbar** visible in rich text mode
- [x] **Plain text toggle** allows switching modes with warning
- [x] **Draft auto-save** every 30 seconds with visual indicator
- [x] **Unsaved changes warning** on window close
- [x] **Multiple compose windows** can be opened simultaneously
- [x] Cmd+N opens new compose window
- [x] **Malformed HTML** displays gracefully with fallback to plain text
- [x] **Encoding issues** (mojibake) detected and fixed
- [x] **Oversized inline styles** constrained to viewport width
- [x] **CID inline images** resolved and displayed correctly
- [x] **CID images** not blocked by external image policy
- [ ] **Print** (Cmd+P) generates print-optimized layout
- [ ] **Print** includes email header (from, to, date, subject)
- [ ] **Quote detection** identifies Gmail and Outlook quote styles
- [ ] **Long quotes** (>5 lines) collapsed by default
- [ ] **Quote expansion** works via click/tap
- [ ] **Signatures** detected and preserved in replies
- [ ] **Cursor placement** in replies is before signature

## Implementation Status

**Completed:**
- EmailDetailView with header, body, and attachment sections
- EmailHeaderView with expandable recipients
- EmailBodyView with HTML/plain text toggle
- HTMLContentView with WKWebView and dark mode support
- AttachmentListView with download/preview support
- CIDResolver for inline image resolution
- EmailDetailViewModel with full email loading and mark-as-read
- ComposeView with form layout and toolbar
- ComposeViewModel with reply/forward setup
- RecipientFieldView with token-based input
- RichTextEditor with NSTextView integration
- FormattingToolbar with formatting buttons
- DraftAutoSaveManager for auto-saving
- ComposeWindowManager for multiple compose windows
- ComposeMode enum for compose contexts

**Remaining:**
- Print support (Cmd+P)
- Quote detection and collapsing
- Signature handling in replies

## References

- [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)
- [NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)
- [NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel)
- [RFC 2822 - Internet Message Format](https://www.rfc-editor.org/rfc/rfc2822)
