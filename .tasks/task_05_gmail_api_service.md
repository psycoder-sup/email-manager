# Task 05: Gmail API Service

## Task Overview

Implement the Gmail API client for fetching emails, sending messages, managing labels, and handling attachments. This service interfaces directly with Google's Gmail REST API.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 02: Core Data Models
- Task 04: Google OAuth & Keychain (for access tokens)

## Architectural Guidelines

### Design Patterns
- **Service Pattern**: Encapsulate all Gmail API operations
- **DTO Pattern**: Use DTOs for API request/response mapping
- **Result Pattern**: Return typed results or throw specific errors

### SwiftUI/Swift Conventions
- Use `async/await` for all API calls
- Use `URLSession` for networking (no external dependencies)
- Handle pagination with continuation tokens

### File Organization
```
Core/Services/Gmail/
├── GmailAPIService.swift
├── GmailAPIError.swift
├── GmailEndpoints.swift
├── DTOs/
│   ├── MessageDTO.swift
│   ├── ThreadDTO.swift
│   ├── LabelDTO.swift
│   └── AttachmentDTO.swift
└── Mappers/
    └── GmailModelMapper.swift

Core/Services/IMAP/
├── IMAPService.swift
├── SMTPService.swift
├── IMAPConnectionPool.swift
└── MailProtocolError.swift

Core/Services/
└── EmailServiceFacade.swift  # Unified interface with fallback logic
```

## Implementation Details

### GmailAPIError

**Purpose**: Typed errors for API failures
**Type**: Enum conforming to Error

**Cases**:
- `unauthorized` - 401 response
- `notFound` - 404 response
- `rateLimited(retryAfter: TimeInterval?)` - 429 response
- `quotaExceeded` - 403 response
- `invalidRequest(String)` - Bad request details
- `serverError(statusCode: Int)` - 5xx responses
- `networkError(Error)` - Connection failures
- `decodingError(Error)` - JSON parsing failures
- `invalidMessageFormat` - Malformed email data

---

### GmailEndpoints

**Purpose**: URL construction for all API endpoints
**Type**: Enum with associated values

**Base URL**: `https://gmail.googleapis.com/gmail/v1/users/{userId}`
(userId is typically "me" for authenticated user)

**Endpoints**:

| Case | Path | Method |
|------|------|--------|
| listMessages | /messages | GET |
| getMessage(id, format) | /messages/{id} | GET |
| modifyMessage(id) | /messages/{id}/modify | POST |
| trashMessage(id) | /messages/{id}/trash | POST |
| untrashMessage(id) | /messages/{id}/untrash | POST |
| listThreads | /threads | GET |
| getThread(id, format) | /threads/{id} | GET |
| listLabels | /labels | GET |
| getLabel(id) | /labels/{id} | GET |
| sendMessage | /messages/send | POST |
| createDraft | /drafts | POST |
| getAttachment(messageId, attachmentId) | /messages/{messageId}/attachments/{attachmentId} | GET |
| getProfile | /profile | GET |
| history(startHistoryId) | /history | GET |

**Message Format Options**: minimal, full, raw, metadata

---

### GmailAPIServiceProtocol

**Public Interface**:

**Messages**:
- `listMessages(account:query:labelIds:maxResults:pageToken:) async throws -> (messages: [GmailMessageDTO], nextPageToken: String?)`
- `getMessage(account:messageId:) async throws -> GmailMessageDTO`
- `modifyMessage(account:messageId:addLabelIds:removeLabelIds:) async throws -> GmailMessageDTO`
- `trashMessage(account:messageId:) async throws`
- `untrashMessage(account:messageId:) async throws`

**Threads**:
- `listThreads(account:query:labelIds:maxResults:pageToken:) async throws -> (threads: [GmailThreadDTO], nextPageToken: String?)`
- `getThread(account:threadId:) async throws -> GmailThreadDTO`

**Labels**:
- `listLabels(account:) async throws -> [GmailLabelDTO]`

**Drafts & Sending**:
- `createDraft(account:to:cc:bcc:subject:body:isHtml:replyToMessageId:attachments:) async throws -> GmailDraftDTO`
- `updateDraft(account:draftId:to:cc:bcc:subject:body:isHtml:attachments:) async throws -> GmailDraftDTO`
- `deleteDraft(account:draftId:) async throws`
- `getDraft(account:draftId:) async throws -> GmailDraftDTO`
- `sendMessage(account:to:cc:bcc:subject:body:isHtml:replyToMessageId:attachments:) async throws -> GmailMessageDTO`

**Note**: `sendMessage` is for user-confirmed sends only. AI/MCP can only use `createDraft`.

---

### Sending vs Draft Flow (Security Boundary)

**Purpose**: Enforce PRD requirement that AI cannot send emails directly

**Draft Creation Flow** (AI/MCP allowed):
```
MCP Tool (create_draft)
    → GmailAPIService.createDraft()
    → Gmail API POST /drafts
    → Returns draft ID
    → User sees draft in Drafts folder
    → User manually reviews and clicks Send
```

**Direct Send Flow** (User-only, NOT exposed to MCP):
```
ComposeView "Send" button (user click)
    → ComposeViewModel.send()
    → GmailAPIService.sendMessage()
    → Gmail API POST /messages/send
    → Email sent immediately
```

**Enforcement Points**:
1. MCP `create_draft` tool calls `createDraft()` only - no send capability
2. `sendMessage()` is NEVER called from MCP layer
3. UI confirmation required: user must physically click Send button
4. Draft review: user sees full email before sending

**Draft-to-Send User Flow**:
1. AI creates draft via MCP
2. User receives notification: "Draft created: {subject}"
3. User opens Drafts folder in Cluademail
4. User reviews email content, recipients, attachments
5. User clicks "Send" button
6. App calls `sendMessage()` with draft content
7. Optionally: delete draft after successful send

**DraftServiceProtocol Methods**:
- `createDraft(...)` - Creates draft, available to MCP
- `sendDraft(draftId:account:)` - UI only, NOT exposed to MCP
- `deleteDraft(draftId:account:)` - Discards draft

---

**Attachments**:
- `getAttachment(account:messageId:attachmentId:) async throws -> Data`

**Sync**:
- `getHistory(account:startHistoryId:historyTypes:) async throws -> GmailHistoryDTO`
- `getProfile(account:) async throws -> GmailProfileDTO`

---

### GmailAPIService Implementation

**Dependencies**:
- AuthenticationService (for access tokens)
- URLSession (default .shared)

**Request Building**:
1. Get access token from AuthenticationService
2. Build URL from endpoint
3. Set Authorization header: `Bearer {token}`
4. Set Accept header: `application/json`
5. For POST requests, set Content-Type and encode body

**Response Handling**:
- 200-299: Decode response body
- 401: Throw unauthorized
- 404: Throw notFound
- 429: Extract Retry-After header, throw rateLimited
- 403: Throw quotaExceeded
- 5xx: Throw serverError with status code

---

### Error Retry Decision Matrix

**Purpose**: Comprehensive retry logic for all error scenarios

| HTTP Status | Error Type | Retryable | Max Retries | Backoff | Action |
|-------------|------------|-----------|-------------|---------|--------|
| 400 | Bad Request | No | 0 | N/A | Log error, surface to user |
| 401 | Unauthorized | Yes (once) | 1 | None | Refresh token, retry once |
| 403 (quotaExceeded) | Quota Exceeded | No | 0 | N/A | Switch to IMAP fallback |
| 403 (forbidden) | Permission Denied | No | 0 | N/A | Check OAuth scopes |
| 404 | Not Found | No | 0 | N/A | Resource deleted, skip |
| 408 | Request Timeout | Yes | 3 | Exponential | Retry with backoff |
| 429 | Rate Limited | Yes | 5 | Retry-After header | Wait, then retry |
| 500 | Internal Error | Yes | 3 | Exponential | Retry with backoff |
| 502 | Bad Gateway | Yes | 3 | Exponential | Retry with backoff |
| 503 | Service Unavailable | Yes | 5 | Exponential | Retry with backoff |
| 504 | Gateway Timeout | Yes | 3 | Exponential | Retry with backoff |
| Network Error | Connection Failed | Yes | 3 | Exponential | Check connectivity |
| DNS Error | Resolution Failed | Yes | 2 | Linear (5s) | May need IMAP fallback |
| SSL Error | Certificate Issue | No | 0 | N/A | Log, alert user |
| Timeout | Request Timeout | Yes | 2 | Linear (10s) | Increase timeout on retry |

**Exponential Backoff Formula**:
- Calculate delay: `baseDelay * pow(2.0, attempt - 1)`
- Add jitter: ±10% randomization to prevent thundering herd
- Cap maximum delay at 60 seconds

**Retry Implementation Guidelines**:
- Loop through attempts up to `maxAttempts`
- On error, check if `isRetryable` - throw immediately if not
- Calculate delay using backoff formula or use `retryDelay` from error (e.g., Retry-After header)
- Sleep for calculated delay before retry
- After exhausting attempts, throw the last error

**Message Fetching**:
- `listMessages` returns minimal info (id, threadId only)
- Must call `getMessage` for full content
- Consider batch fetching for efficiency

**Raw Message Building** (for drafts/sending):
1. Build MIME headers (To, Subject, MIME-Version, etc.)
2. Add Cc, Bcc if present
3. Add In-Reply-To and References for replies
4. Set Content-Type based on isHtml
5. For attachments, use multipart/mixed with boundary
6. Base64URL encode the complete message

---

### GmailModelMapper

**Purpose**: Convert DTOs to app models
**Type**: Class

**Public Interface**:
- `mapToEmail(_:account:) -> Email`

**Header Parsing**:
- Extract Subject, From, To, Cc, Bcc, Date from headers array
- Parse "Name <email>" format for addresses
- Parse RFC 2822 date format

**Body Extraction**:
- Recursively search payload for text/plain and text/html parts
- Decode base64URL data to string
- Handle multipart structures

**Attachment Extraction**:
- Recursively search for parts with filename and attachmentId
- Create Attachment objects with metadata (don't download content)

---

### Base64URL Encoding

**Data Extension Methods**:
- `base64URLEncodedString() -> String`: Standard base64 with `+`→`-`, `/`→`_`, no padding
- `init?(base64URLEncoded:)`: Reverse the encoding, restore padding

---

### Supporting Types

**AttachmentData** (for sending):
- `filename`: String
- `mimeType`: String
- `data`: Data

**ListMessagesResponse**:
- `messages`: [MessageRef]? (id, threadId only)
- `nextPageToken`: String?
- `resultSizeEstimate`: Int?

**ModifyMessageRequest**:
- `addLabelIds`: [String]
- `removeLabelIds`: [String]

---

---

### IMAP/SMTP Fallback (PRD Requirement)

**Purpose**: Alternative protocol when Gmail API is unavailable
**Trigger Conditions**:
- Gmail API quota exceeded (403 with `quotaExceeded` reason)
- Gmail API rate limited (429) after 3 retries with exponential backoff
- Gmail API endpoint unreachable (network timeout after 30s, 3 attempts)
- Explicit user preference toggle in Settings (future)

**Library Decision: MailCore2 via CocoaPods or Manual Integration**

**Rationale**:
- Native `Network` framework lacks IMAP protocol implementation
- MailCore2 is mature, supports XOAUTH2 authentication
- Official repository: `https://github.com/MailCore/mailcore2`

**Integration Options** (in order of preference):

**Option 1: CocoaPods (Recommended)**:
```ruby
# Podfile
platform :osx, '14.0'
use_frameworks!

target 'Cluademail' do
  pod 'MailCore2-osx'
end
```

**Option 2: Manual Framework Integration**:
1. Download prebuilt framework from MailCore2 releases
2. Add `MailCore.framework` to project
3. Embed & Sign in target settings
4. Add to Framework Search Paths

**Option 3: Build from Source**:
```bash
git clone https://github.com/MailCore/mailcore2.git
cd mailcore2/build-mac
./build.sh
# Output: mailcore2/build-mac/MailCore.framework
```

**Build Configuration**:
- Link `MailCore.framework`
- Add required system frameworks: Security, CFNetwork, CoreServices
- Set `CLANG_CXX_LANGUAGE_STANDARD` to `gnu++17`
- Add `-lc++` to Other Linker Flags

**IMAPService**:
- Server: `imap.gmail.com:993` (SSL)
- Authentication: OAuth2 XOAUTH2 SASL mechanism
- Use existing OAuth tokens (same as API)
- Framework: MailCore2 (`MCOIMAPSession`)

**IMAP Operations**:
- `connect(account:) async throws`
- `fetchMessages(folder:limit:) async throws -> [Email]`
- `fetchMessage(uid:folder:) async throws -> Email`
- `moveMessage(uid:from:to:) async throws`
- `setFlags(uid:flags:) async throws` (read, starred, deleted)

**SMTPService**:
- Server: `smtp.gmail.com:587` (STARTTLS)
- Authentication: OAuth2 XOAUTH2 SASL mechanism
- `send(message:from:) async throws`

**EmailServiceFacade**:
- Unified interface over Gmail API and IMAP/SMTP
- Automatic fallback: try API first, fall back to IMAP on specific errors
- Track which protocol is active per account
- Emit events when fallback occurs (for UI notification)

**XOAUTH2 Token Format**:
```
base64("user=" + email + "\x01auth=Bearer " + accessToken + "\x01\x01")
```

**XOAUTH2Helper Implementation**:
- Generate SASL token by concatenating: `user={email}\x01auth=Bearer {accessToken}\x01\x01`
- Base64 encode the concatenated string

**MailCore2 IMAP Session Setup**:
- Create MCOIMAPSession with hostname `imap.gmail.com`, port 993
- Set connectionType to TLS, authType to xoAuth2
- Pass accessToken to oAuth2Token property (MailCore2 handles XOAUTH2 formatting)

**MailCore2 SMTP Session Setup**:
- Create MCOSMTPSession with hostname `smtp.gmail.com`, port 587
- Set connectionType to startTLS, authType to xoAuth2
- Pass accessToken to oAuth2Token property

---

### Batch API Implementation

**Purpose**: Fetch multiple messages efficiently
**Endpoint**: `https://gmail.googleapis.com/batch`

**Request Format**:
- Content-Type: `multipart/mixed; boundary={boundary}`
- Each part: individual HTTP request with Content-Type: application/http

**Batch Limits**:
- Max 100 requests per batch
- Max 1MB total request size

**Implementation**:
- `batchGetMessages(account:messageIds:) async throws -> BatchResult<GmailMessageDTO>`
- Chunk messageIds into groups of 50
- Parse multipart response, handle partial failures

**BatchResult Type**:
- Generic struct `BatchResult<T>` with `succeeded: [T]` and `failed: [BatchFailure]`
- Computed property `hasFailures` returns true if any failures exist
- `BatchFailure` contains: requestIndex, messageId, statusCode, error (GmailAPIError)

**Partial Failure Handling**:
1. Parse each part of multipart response independently
2. Extract HTTP status from each part's status line
3. For 2xx responses: decode and add to `succeeded`
4. For non-2xx responses: create `BatchFailure` with error details
5. Return `BatchResult` with both succeeded and failed items

**Retry Strategy for Batch Failures**:
| Status Code | Action |
|-------------|--------|
| 429 | Retry entire batch after Retry-After delay |
| 500, 503 | Retry failed items only (max 2 retries) |
| 401 | Refresh token, retry entire batch once |
| 404 | Skip (message deleted), log warning |
| Other 4xx | Skip (permanent failure), log error |

**Batch Response Parsing**:

**Response Format**: Multipart response with boundary markers. Each part contains:
- Outer headers (Content-Type, Content-ID)
- Inner HTTP response (status line, headers, JSON body)

**BatchPartResult**: Struct containing index, statusCode, headers dictionary, and body Data

**Parser Implementation Guidelines**:
1. Convert response data to string (UTF-8)
2. Split by boundary marker (`--{boundary}`)
3. Filter out empty parts and closing boundary
4. For each part:
   - Split by double CRLF to separate headers from body
   - Extract outer headers (Content-Type, Content-ID)
   - Parse HTTP status line to get status code (e.g., "HTTP/1.1 200 OK" → 200)
   - Parse inner response headers
   - Extract JSON body (everything after inner headers)
5. Return array of BatchPartResult

**Content-ID Correlation**:
- Request Content-ID: `<request-{index}>`
- Response Content-ID: `response-{index}`
- Use index to correlate request message ID with response

---

### Quota Management

**Gmail API Quotas** (per user):
- 250 quota units/second
- 1 billion units/day

**Unit Costs**:
| Operation | Units |
|-----------|-------|
| messages.list | 5 |
| messages.get | 5 |
| messages.send | 100 |
| threads.list | 10 |
| labels.list | 1 |

**Strategy**:
- Track quota usage per minute
- Implement request queuing when approaching limits
- Back off exponentially on 429 responses
- Switch to IMAP fallback if quota exhausted

---

### International Character Handling

**Encoded-Word Syntax** (RFC 2047):
- Format: `=?charset?encoding?encoded_text?=`
- Example: `=?UTF-8?B?5pel5pys6Kqe?=` (Base64) or `=?UTF-8?Q?...?=` (Quoted-Printable)

**Implementation**:
- Detect and decode encoded-word in headers (Subject, From, To)
- Helper: `decodeRFC2047(_:) -> String`
- Handle multiple encoded-word segments concatenated

**Body Encoding**:
- Check Content-Type charset parameter
- Decode body using specified charset (UTF-8, ISO-8859-1, etc.)
- Fallback to UTF-8 if charset missing

---

### Large Email Handling

**Gmail Limits**:
- Max message size: 25MB (API), 35MB (IMAP with attachments)

**Strategy for Large Emails**:
- Fetch metadata first (format=metadata)
- Lazy-load body parts on demand
- Stream large attachments instead of loading to memory
- Show loading indicator for body content

**Timeout Configuration**:
- API requests: 30 second timeout
- Large attachment downloads: 5 minute timeout
- Configurable via URLSessionConfiguration

### Key Considerations

- **Rate Limiting**: Gmail API has quota limits; respect Retry-After header
- **Batch Requests**: Use Gmail batch API for fetching multiple messages (50 per batch)
- **Pagination**: Always handle nextPageToken for large result sets
- **Email Body**: Handle multipart MIME, base64 encoding, HTML vs plain text
- **Attachment Download**: Download on demand, not during sync (can be large)
- **IMAP Fallback**: Automatic fallback when API unavailable (PRD requirement)
- **Encoding**: Handle RFC 2047 encoded headers for international characters

## Acceptance Criteria

- [ ] `GmailAPIService` can list messages with pagination
- [ ] `GmailAPIService` can fetch full message content
- [ ] `GmailAPIService` can modify message labels (read/unread, star, archive)
- [ ] `GmailAPIService` can create drafts with body and attachments
- [ ] `GmailAPIService` can send emails (for user-confirmed sends)
- [ ] `GmailAPIService` can download attachments on demand
- [ ] `GmailAPIService` supports incremental sync via History API
- [ ] `GmailModelMapper` correctly parses email headers (From, To, CC, Subject, Date)
- [ ] `GmailModelMapper` extracts plain text and HTML body content
- [ ] `GmailModelMapper` identifies and maps attachments
- [ ] Rate limiting is handled with exponential backoff
- [ ] All API errors are mapped to typed `GmailAPIError`
- [ ] Base64URL encoding/decoding works correctly
- [ ] **Batch API** fetches up to 50 messages per request
- [ ] **Batch partial failures** handled with retry for transient errors, skip for permanent
- [ ] **BatchResult** type returns both succeeded and failed items
- [ ] **IMAP fallback** connects via `imap.gmail.com` with XOAUTH2
- [ ] **SMTP fallback** sends via `smtp.gmail.com` with XOAUTH2
- [ ] **MailCore2** integrated via SPM with proper build configuration
- [ ] **XOAUTH2Helper** generates valid SASL tokens
- [ ] **EmailServiceFacade** provides unified interface with automatic fallback
- [ ] **Fallback triggers** on 403 quota, 429 after retries, or network timeout
- [ ] **RFC 2047** encoded headers decoded correctly (international characters)
- [ ] **Quota tracking** implemented with backoff strategy
- [ ] **Draft CRUD** - createDraft, updateDraft, deleteDraft, getDraft all implemented
- [ ] Large emails (>5MB) lazy-load body content
- [ ] **Error retry matrix** implemented with correct retry/skip decisions
- [ ] **401 errors** trigger token refresh and single retry
- [ ] **Sending flow** separated: MCP can only createDraft, UI can sendMessage
- [ ] **DraftService** enforces security boundary between AI and direct sending
- [ ] **Batch parsing** correctly handles Content-ID correlation
- [ ] **Batch parsing** extracts status code from nested HTTP response
- [ ] **MailCore2** integrated via CocoaPods or manual framework

## References

- [Gmail API Reference](https://developers.google.com/gmail/api/reference/rest)
- [Gmail API Messages](https://developers.google.com/gmail/api/reference/rest/v1/users.messages)
- [Gmail API Threads](https://developers.google.com/gmail/api/reference/rest/v1/users.threads)
- [Gmail API Labels](https://developers.google.com/gmail/api/reference/rest/v1/users.labels)
- [Gmail API Drafts](https://developers.google.com/gmail/api/reference/rest/v1/users.drafts)
- [Sending Email](https://developers.google.com/gmail/api/guides/sending)
