# Task 02: Core Data Models

## Task Overview

Define all core data models that represent emails, accounts, threads, attachments, and labels. These models serve as the foundation for both local storage (SwiftData) and API mapping (Gmail API).

## Dependencies

- Task 01: Project Setup & Architecture (folder structure must exist)

## Architectural Guidelines

### Design Patterns
- **Value Types for DTOs**: Use structs for data transfer from API
- **Reference Types for Persistence**: Use classes with `@Model` for SwiftData
- **Protocol-Driven**: Define protocols for model behaviors

### SwiftUI/Swift Conventions
- Use `Codable` for JSON serialization
- Use `Identifiable` for SwiftUI list compatibility
- Use `Hashable` for use in Sets and as Dictionary keys
- Follow naming conventions: singular nouns for models

### File Organization
```
Core/Models/
├── Account.swift
├── Email.swift
├── EmailThread.swift
├── Attachment.swift
├── Label.swift
└── SyncState.swift
```

## Implementation Details

### Account Model

**Purpose**: Represents a Gmail account linked to the app
**Type**: `@Model` class (SwiftData)

**Properties**:
- Identity: `id` (UUID, unique), `email` (String)
- Profile: `displayName` (String), `profileImageURL` (String?)
- State: `isEnabled` (Bool), `lastSyncDate` (Date?), `historyId` (String?)

**Relationships**:
- One-to-many with Email (cascade delete)
- One-to-many with Label (cascade delete)

**Initialization**: Requires email and displayName; generates UUID, sets isEnabled=true

---

### Email Model

**Purpose**: Full email representation with all Gmail metadata
**Type**: `@Model` class (SwiftData)

**Properties**:
- Identity: `gmailId` (String, unique), `threadId` (String)
- Content: `subject`, `snippet`, `bodyText`, `bodyHtml`
- Sender: `fromAddress` (String), `fromName` (String?)
- Recipients: `toAddresses`, `ccAddresses`, `bccAddresses` (all [String])
- Metadata: `date` (Date), `isRead`, `isStarred` (Bool), `labelIds` ([String])

**Relationships**:
- Many-to-one with Account
- One-to-many with Attachment (cascade delete)

**Computed Properties**:
- `isInInbox`: labelIds contains "INBOX"
- `isInTrash`: labelIds contains "TRASH"
- `isInSpam`: labelIds contains "SPAM"
- `isDraft`: labelIds contains "DRAFT"
- `isSent`: labelIds contains "SENT"

---

### EmailThread Model

**Purpose**: Groups related emails for thread view
**Type**: `@Model` class (SwiftData)

**Properties**:
- Identity: `threadId` (String, unique)
- Display: `subject`, `snippet` (String)
- Metadata: `lastMessageDate` (Date), `messageCount` (Int)
- Aggregated State: `isRead` (all messages read), `isStarred` (any message starred)
- Participants: `participantEmails` ([String])

**Relationships**:
- Many-to-one with Account

---

### Attachment Model

**Purpose**: Attachment metadata with download state tracking
**Type**: `@Model` class (SwiftData)

**Properties**:
- Identity: `id` (String, unique), `gmailAttachmentId` (String)
- File Info: `filename`, `mimeType` (String), `size` (Int64)
- Download State: `localPath` (String?), `isDownloaded` (Bool)

**Relationships**:
- Many-to-one with Email

**Computed Properties**:
- `displaySize`: Human-readable file size (use ByteCountFormatter)

---

### Label Model

**Purpose**: Gmail label representation (system and user labels)
**Type**: `@Model` class (SwiftData)

**Properties**:
- Identity: `gmailLabelId` (String, unique), `name` (String)
- Classification: `type` (enum: system, user)
- Visibility: `messageListVisibility`, `labelListVisibility` (enum: show, hide, showIfUnread)
- Appearance: `textColor`, `backgroundColor` (String?, hex format)

**Relationships**:
- Many-to-one with Account

**Static Constants**:
- System label IDs: INBOX, SENT, DRAFT, TRASH, SPAM, STARRED, UNREAD, IMPORTANT, CATEGORY_PERSONAL, CATEGORY_SOCIAL, CATEGORY_PROMOTIONS, CATEGORY_UPDATES

---

### SyncState Model

**Purpose**: Tracks sync progress per account for incremental sync
**Type**: `@Model` class (SwiftData)

**Properties**:
- Identity: `accountId` (UUID)
- Sync Progress: `historyId` (String?), `lastFullSyncDate`, `lastIncrementalSyncDate` (Date?)
- Status: `emailCount` (Int), `syncStatus` (enum: idle, syncing, error, completed)
- Error: `errorMessage` (String?)

---

### Gmail API DTOs (Data Transfer Objects)

**Purpose**: Map Gmail API JSON responses to Swift types
**Type**: Structs conforming to `Codable`

**GmailMessageDTO**:
- Root: `id`, `threadId`, `labelIds`, `snippet`, `internalDate`
- Nested: `payload` (PayloadDTO)

**PayloadDTO**:
- `headers` ([HeaderDTO]), `body` (BodyDTO?), `parts` ([PartDTO]?), `mimeType`

**HeaderDTO**:
- `name`, `value` (String)

**BodyDTO**:
- `size` (Int), `data` (String?, base64), `attachmentId` (String?)

**PartDTO**:
- `partId`, `mimeType`, `filename` (String?), `body` (BodyDTO?), `parts` ([PartDTO]?, recursive)

### Key Considerations

- **Gmail ID Mapping**: Use Gmail's message IDs as primary identifiers
- **Thread ID**: Gmail threads share a thread ID across messages
- **Label System**: Gmail uses labels instead of folders; map system labels to folder concepts
- **Attachment Size**: Store metadata only; download content on demand
- **Date Handling**: Use `Date` for internal, ISO8601 for API serialization

## Acceptance Criteria

- [ ] All model files created in `Core/Models/`
- [ ] Models compile without errors
- [ ] SwiftData `@Model` classes have appropriate relationships defined
- [ ] All models conform to `Identifiable`
- [ ] `Email` model can represent all Gmail message metadata
- [ ] `Attachment` model tracks download state and local file path
- [ ] `Label` model distinguishes system vs user labels
- [ ] DTO structs created for Gmail API response mapping
- [ ] Unit tests for model initialization and computed properties
- [ ] Models support encoding/decoding for API communication

## References

- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [Gmail API Messages Resource](https://developers.google.com/gmail/api/reference/rest/v1/users.messages)
- [Gmail API Threads Resource](https://developers.google.com/gmail/api/reference/rest/v1/users.threads)
- [Gmail API Labels Resource](https://developers.google.com/gmail/api/reference/rest/v1/users.labels)
