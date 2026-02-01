# Task 06: Email Sync Engine

## Task Overview

Build the background sync engine that keeps local email data synchronized with Gmail. This includes initial full sync, incremental sync using Gmail History API, and managing the 1000 email per account limit.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 02: Core Data Models
- Task 03: Local Database Layer
- Task 04: Google OAuth & Keychain
- Task 05: Gmail API Service

## Architectural Guidelines

### Design Patterns
- **Actor Pattern**: Use Swift actors for thread-safe sync operations
- **Observer Pattern**: Publish sync state changes for UI updates
- **Strategy Pattern**: Different sync strategies (full vs incremental)

### SwiftUI/Swift Conventions
- Use `async/await` and structured concurrency
- Use `TaskGroup` for parallel operations
- Implement cancellation support

### File Organization
```
Core/Services/Sync/
├── SyncEngine.swift
├── SyncCoordinator.swift
├── SyncScheduler.swift
├── IMAPSyncEngine.swift      # IMAP fallback sync
├── RetryPolicy.swift         # Exponential backoff logic
└── SyncRecoveryManager.swift # Partial failure recovery
```

## Implementation Details

### SyncEngine

**Purpose**: Core sync logic for a single account
**Type**: Actor (thread-safe)

**Dependencies**:
- Account instance
- GmailAPIService
- EmailRepository
- LabelRepository
- SyncStateRepository
- GmailModelMapper

**Constants**:
- `maxEmailsPerAccount`: 1000

**Sync Types**:
- `full`: Complete sync from scratch
- `incremental`: Delta sync using History API

**Sync Result**:
- `success(newEmails:updatedEmails:deletedEmails:)`: Counts of changes
- `partialSuccess(error:)`: Some operations failed
- `failure(Error)`: Complete failure

**Public Interface**:
- `sync() async -> SyncResult`

**Sync Flow**:
1. Check for existing SyncState with historyId
2. If historyId exists: attempt incremental sync
3. If incremental fails with notFound (history expired): fall back to full sync
4. If no historyId: perform full sync

---

### Full Sync Strategy

**Process**:
1. Sync labels first (call `syncLabels()`)
2. Fetch messages up to `maxEmailsPerAccount` with pagination
3. For each message:
   - Map DTO to Email model
   - Check if email exists by gmailId
   - If exists: update labels, read/starred status
   - If new: insert email
4. Enforce email limit via `deleteOldest`
5. Fetch profile to get latest historyId
6. Save historyId to SyncState

**Pagination Loop**:
- Request 100 messages per page (or remaining count)
- Continue until maxEmailsPerAccount reached or no more pages
- Track nextPageToken

---

### Incremental Sync Strategy

**Process**:
1. Sync labels
2. Fetch history from startHistoryId with types: messageAdded, messageDeleted, labelAdded, labelRemoved
3. Process each history record:
   - **messagesAdded**: Fetch full message, insert or update
   - **messagesDeleted**: Delete from local database
   - **labelsAdded**: Add labels to email, update isRead/isStarred
   - **labelsRemoved**: Remove labels from email, update isRead/isStarred
4. Track latest historyId from response
5. Handle pagination (nextPageToken)
6. Enforce email limit via `deleteOldest`
7. Update SyncState with new historyId

**Label State Derivation**:
- `isRead = !labelIds.contains("UNREAD")`
- `isStarred = labelIds.contains("STARRED")`

---

### Labels Sync

**Process**:
1. Fetch all labels from Gmail API
2. For each label:
   - Determine type (system vs user) based on known system IDs
   - Create or update Label model
   - Save to repository

---

### Thread Sync Strategy

**Approach**: Derive threads from emails, don't sync separately

**Rationale**:
- Gmail API threads endpoint returns same data as messages grouped by threadId
- Syncing threads separately doubles API calls
- Thread metadata (subject, participants, dates) can be derived from messages

**Thread Derivation Process**:
1. After syncing emails, group by `threadId`
2. For each unique threadId:
   - Find all emails with that threadId
   - Derive thread metadata:
     - `subject`: From first message in thread (by date)
     - `snippet`: From latest message
     - `lastMessageDate`: Max date of all messages
     - `messageCount`: Count of messages
     - `participantEmails`: Unique senders/recipients
     - `isRead`: All messages are read
     - `isStarred`: Any message is starred
3. Upsert EmailThread record

**ThreadDerivationService**:
- Actor that derives EmailThread records from synced emails
- Group emails by `threadId` using Dictionary grouping
- For each thread group, sort messages by date and derive:
  - `subject`: From first message in thread
  - `snippet`: From latest message
  - `lastMessageDate`: Max date of all messages
  - `messageCount`: Count of messages
  - `participantEmails`: Unique senders/recipients (flatten fromAddress + toAddresses)
  - `isRead`: True only if all messages are read
  - `isStarred`: True if any message is starred

**When to Derive**:
- After full sync completes
- After incremental sync processes all deltas
- After any email label change (read/star affects thread state)

**Thread Cleanup**:
- If all emails in a thread are deleted, delete the EmailThread record
- Check during `deleteOldest` enforcement

---

### SyncCoordinator

**Purpose**: Coordinates sync across multiple accounts
**Type**: `@Observable` class

**Properties**:
- `isSyncing`: Bool
- `syncProgress`: [UUID: SyncProgress] - Per-account status
- `lastSyncDate`: Date?
- `syncError`: Error?

**SyncProgress**:
- `status`: enum (idle, syncing, completed, error)
- `message`: String (human-readable status)

**Public Interface**:
- `syncAllAccounts(_:) async` - Sync all enabled accounts concurrently
- `syncAccount(_:) async` - Sync single account

**Concurrent Sync**:
- Use `TaskGroup` to sync accounts in parallel
- Track progress per account
- Collect results and update syncProgress map
- Set lastSyncDate when complete

**Engine Management**:
- Maintain dictionary of SyncEngine per account ID
- Create engine on first use, reuse thereafter

---

### SyncScheduler

**Purpose**: Background sync scheduling
**Type**: Class

**Properties**:
- `isRunning`: Bool
- `syncInterval`: TimeInterval (default 300 = 5 minutes)

**Dependencies**:
- SyncCoordinator
- AccountRepository

**Public Interface**:
- `start(interval:)` - Begin scheduled syncing
- `stop()` - Cancel scheduled syncing
- `triggerImmediateSync() async` - Sync now
- `updateInterval(_:)` - Change interval (restarts if running)

**Scheduling**:
- Use `Task` with sleep loop
- Check `Task.isCancelled` for clean shutdown
- Fetch all accounts from repository before each sync

---

### IMAP Fallback Sync (PRD Requirement)

**Purpose**: Sync via IMAP when Gmail API unavailable
**Type**: `IMAPSyncEngine` actor

**Trigger Conditions** (Specific):

| Condition | Detection | Threshold |
|-----------|-----------|-----------|
| Quota exceeded | HTTP 403 with `reason: "quotaExceeded"` in error body | Immediate |
| Rate limited | HTTP 429 | After 3 retries with exponential backoff (total ~30s) |
| API unreachable | Network timeout or DNS failure | 3 consecutive failures within 5 minutes |
| Server error | HTTP 500/502/503 | After 5 retries over 2 minutes |

**FallbackTrigger Implementation**:
- Actor with properties: `consecutiveFailures` (Int), `lastFailureTime` (Date?), `isInFallbackMode` (Bool)
- `recordFailure(error:)` method logic:
  - `quotaExceeded`: Immediate fallback, return true
  - `rateLimited`: If retryAfter > 300 seconds (5 min), enter fallback
  - `networkError`/`serverError`: Increment consecutiveFailures, enter fallback at 3 failures
  - Other errors: Return false, don't trigger fallback
- `recordSuccess()`: Reset consecutiveFailures to 0 (don't auto-exit fallback mode)
- `resetFallbackMode()`: Reset both isInFallbackMode and consecutiveFailures

**Fallback Mode Recovery**:
- After entering fallback mode, attempt API every 15 minutes
- If API succeeds, mark `pendingCategorySync = true` for full label refresh
- Exit fallback mode after 3 consecutive API successes

**IMAP Sync Flow**:
1. Connect to `imap.gmail.com:993` with XOAUTH2
2. SELECT folder (e.g., [Gmail]/All Mail or INBOX)
3. FETCH messages with SINCE date or UID range
4. Parse MIME structure for headers and body
5. Map to Email model
6. Save to local database

**Folder Mapping** (IMAP → Gmail Labels):
| IMAP Folder | Gmail Label |
|-------------|-------------|
| INBOX | INBOX |
| [Gmail]/Sent Mail | SENT |
| [Gmail]/Drafts | DRAFT |
| [Gmail]/Trash | TRASH |
| [Gmail]/Spam | SPAM |
| [Gmail]/Starred | STARRED |
| [Gmail]/All Mail | (all messages) |

**IMAP FLAGS → Gmail Label Mapping**:
| IMAP Flag | Gmail Equivalent | Notes |
|-----------|------------------|-------|
| \Seen | Remove UNREAD label | isRead = true |
| \Flagged | STARRED label | isStarred = true |
| \Deleted | TRASH label | Move to trash |
| \Draft | DRAFT label | Is a draft |
| \Answered | (no equivalent) | Track locally only |

**User Labels via IMAP**:
- Gmail exposes user labels as IMAP folders under root
- List all folders, filter out system folders (starting with [Gmail])
- Remaining folders are user labels
- To apply label via IMAP: COPY message to label folder
- To remove label via IMAP: Not directly supported—use API when available

**Category Labels (IMAP Limitation)**:
- CATEGORY_PERSONAL, CATEGORY_SOCIAL, CATEGORY_PROMOTIONS, CATEGORY_UPDATES
- **Not accessible via IMAP** - these are Gmail-only smart labels
- During IMAP fallback: skip category labels, sync when API resumes
- Store `pendingCategorySync: Bool` in SyncState

**IMAP Incremental Sync**:
- Store last seen UID per folder in SyncState: `imapUidValidity`, `lastSeenUid`
- FETCH UIDs greater than last seen
- Use CONDSTORE extension if available for change detection

**CONDSTORE Fallback**:
- Check if server supports CONDSTORE by fetching capabilities
- If CONDSTORE supported:
  - Use CHANGEDSINCE modifier with stored modseq from SyncState
  - Fetch only messages changed since last sync
- If CONDSTORE not supported (fallback):
  - Fetch all UIDs from remote folder
  - Compare with locally stored UIDs
  - Calculate newUIDs (remote - local) and deletedUIDs (local - remote)
  - Fetch new messages, delete removed ones locally

---

### Retry Policy & Exponential Backoff

**RetryPolicy Configuration**:
- `maxAttempts`: 5 (default)
- `baseDelay`: 1.0 second
- `maxDelay`: 60.0 seconds (cap)
- `multiplier`: 2.0 (exponential)
- `jitter`: 0.1 (±10% randomization)

**Delay Calculation**:
- Formula: `min(baseDelay * (multiplier ^ attempt), maxDelay)`
- Apply jitter: `delay * (1 + random(-jitter, jitter))`

**Retry Sequence** (default policy):
| Attempt | Base Delay | With Jitter Range |
|---------|------------|-------------------|
| 1 | 1s | 0.9-1.1s |
| 2 | 2s | 1.8-2.2s |
| 3 | 4s | 3.6-4.4s |
| 4 | 8s | 7.2-8.8s |
| 5 | 16s | 14.4-17.6s |

**Retryable Errors**:
- Network timeout
- 429 rate limited
- 503 service unavailable
- 500 internal server error (transient)

**Non-Retryable Errors**:
- 401 unauthorized (trigger re-auth)
- 403 forbidden (switch to IMAP fallback)
- 404 not found (resource doesn't exist)

---

### Partial Failure Recovery

**SyncRecoveryManager**:
- Tracks failed operations during sync
- Stores: `[FailedOperation]` with messageId, operationType, error, attemptCount

**FailedOperation Types**:
- `fetchMessage(id)` - Failed to fetch full message
- `parseMessage(id)` - Failed to parse MIME
- `saveMessage(id)` - Failed to save to database
- `deleteMessage(id)` - Failed to delete

**Recovery Strategy**:
1. Complete sync for successful operations
2. Log failed operations with context
3. Store failed IDs in SyncState.failedMessageIds
4. Retry failed operations on next sync cycle
5. After 3 failed attempts, mark as permanently failed and skip

**Partial Success Handling**:
- Return `SyncResult.partialSuccess(succeeded:N, failed:M, errors:[Error])`
- Update lastSyncDate even on partial success
- UI shows warning indicator for partial failures

---

### Concurrent Sync Protection

**Problem**: User triggers manual sync while scheduled sync running

**Solution - SyncLock**:
- Actor with `activeSyncs: Set<UUID>` tracking account IDs currently syncing
- Methods:
  - `acquireLock(for:)` - Returns true if lock acquired, false if already locked
  - `releaseLock(for:)` - Removes account from active syncs
  - `isLocked(_:)` - Check if account is currently syncing

**Behavior**:
- Only one sync per account at a time
- If sync requested while another running: skip or queue
- Configurable via `SyncCoordinator.conflictPolicy`: `.skip`, `.queue`, `.cancel`

**Queue Mode**:
- Queue subsequent sync requests (max queue size: 1)
- Execute queued sync after current completes

---

### Large Mailbox Initial Sync

**Problem**: Accounts with >10k messages take too long for initial sync

**Progressive Sync Strategy**:
1. **Phase 1 - Recent (Quick)**: Fetch last 100 messages first
   - User sees emails immediately
   - Mark phase complete, allow UI interaction

2. **Phase 2 - Extended**: Fetch remaining up to 1000
   - Run in background with lower priority
   - Show progress indicator

3. **Batch Size Tuning**:
   - Start with batch of 100
   - If response time >5s, reduce to 50
   - If <1s and no errors, increase to 200

**SyncState Phase Tracking**:
- `phase`: enum (initial, extended, complete)
- `fetchedCount`: Int
- `targetCount`: Int (1000)

---

### History Deduplication

**Problem**: Multiple history records may reference the same message

**Example**:
- History record 1: messageAdded (id: 123)
- History record 2: labelAdded (id: 123, label: STARRED)
- History record 3: labelRemoved (id: 123, label: UNREAD)

**Solution**:
1. Collect all history records first
2. Group by messageId
3. For each message, determine final state:
   - If any `messagesDeleted`: delete locally
   - Otherwise: fetch latest message state once
4. Apply final state to local database

**MessageDelta Struct**:
- `messageId`: String identifier
- `isDeleted`: Bool (default false)
- `labelsToAdd`: Set<String> for labels to add
- `labelsToRemove`: Set<String> for labels to remove
- `needsFullFetch`: Bool (true if messagesAdded event)

---

### Key Considerations

- **1000 Email Limit**: Enforce per-account after every sync operation
- **Initial Sync**: Full sync on first launch or account add (no historyId)
- **History ID Expiration**: Gmail history expires; detect notFound error and fall back to full sync
- **Conflict Resolution**: Server wins for label/read state (authoritative source)
- **Network Efficiency**: Batch requests, respect pagination
- **User Experience**: Don't block UI during sync; all operations are async
- **IMAP Fallback**: Automatic switch when Gmail API unavailable (PRD requirement)
- **Retry Policy**: Exponential backoff with jitter for transient failures
- **Partial Failures**: Continue sync for successful operations, retry failures later
- **Concurrent Protection**: Prevent duplicate syncs on same account
- **Progressive Initial Sync**: Show results quickly for large mailboxes
- **History Deduplication**: Coalesce multiple history records for same message

## Acceptance Criteria

- [x] `SyncEngine` performs full sync for new accounts
- [x] `SyncEngine` performs incremental sync using History API
- [x] `SyncEngine` falls back to full sync when history expires
- [x] `SyncEngine` enforces 1000 email limit per account
- [x] `SyncEngine` syncs labels from Gmail
- [x] `SyncCoordinator` syncs multiple accounts concurrently
- [x] `SyncCoordinator` publishes sync progress for UI
- [x] `SyncScheduler` runs background sync at configurable intervals
- [x] `SyncScheduler` supports immediate sync trigger
- [x] `SyncScheduler` properly cancels on stop
- [x] Sync handles network errors gracefully
- [x] Sync doesn't block main thread/UI
- [x] New emails are detected and added
- [x] Deleted emails are removed from local database
- [x] Label changes are reflected locally
- [ ] **IMAP fallback** activates when Gmail API unavailable *(deferred)*
- [ ] **Fallback triggers** on 403 quota (immediate), 429 after retries, or 3 network failures *(deferred)*
- [ ] **FallbackTrigger** tracks consecutive failures and manages fallback mode *(deferred)*
- [ ] **IMAP FLAG mapping** correctly converts \Seen, \Flagged to Gmail labels *(deferred)*
- [ ] **Category labels** skipped during IMAP fallback, marked for sync when API resumes *(deferred)*
- [ ] **CONDSTORE** used when available, falls back to UID comparison otherwise *(deferred)*
- [ ] **Thread derivation** creates EmailThread records from synced emails *(deferred - can add in Task 08)*
- [ ] **Thread state** (isRead, isStarred) correctly derived from message states *(deferred - can add in Task 08)*
- [ ] **Exponential backoff** retries transient failures (1s→2s→4s→8s→16s) *(uses RetryHelper from Task 05)*
- [ ] **Partial failures** don't abort entire sync; failed items retry later *(deferred)*
- [x] **Concurrent sync protection** prevents duplicate syncs per account
- [x] **Progressive sync** shows first 100 emails quickly for new accounts
- [ ] **History deduplication** coalesces multiple records for same message *(deferred)*

---

## Completion Summary (2026-02-01)

1. **Files Created**:
   - `Core/Services/Sync/SyncProtocols.swift` - Result types (`SyncResult`, `SyncProgress`) and progress tracking
   - `Core/Services/Sync/SyncLock.swift` - Actor-based concurrent sync protection
   - `Core/Services/Sync/SyncEngine.swift` - Core sync logic with full/incremental sync, 1000 email limit enforcement
   - `Core/Services/Sync/SyncCoordinator.swift` - Multi-account coordination with `@Observable` for UI binding
   - `Core/Services/Sync/SyncScheduler.swift` - Background periodic sync with configurable intervals
   - `CluademailTests/Mocks/MockDatabaseService.swift` - In-memory SwiftData testing
   - `CluademailTests/TestHelpers/TestFixtures.swift` - Gmail history DTO factory methods
   - `CluademailTests/Unit/Services/Sync/SyncLockTests.swift` - 8 concurrent lock tests
   - `CluademailTests/Unit/Services/Sync/SyncEngineTests.swift` - 15 full/incremental sync tests
   - `CluademailTests/Unit/Services/Sync/SyncCoordinatorTests.swift` - 15 multi-account coordination tests
   - `CluademailTests/Unit/Services/Sync/SyncSchedulerTests.swift` - 13 background scheduling tests

2. **Key Features**:
   - Full sync: Fetches up to 1000 messages, syncs labels, saves historyId
   - Incremental sync: Uses History API for delta changes (messageAdded, messageDeleted, labelAdded, labelRemoved)
   - Progressive sync: Phase 1 fetches 100 recent emails quickly, Phase 2 fetches remaining in background
   - Concurrent protection: `SyncLock` actor prevents duplicate syncs per account
   - Multi-account: `SyncCoordinator` syncs accounts in parallel via `TaskGroup`
   - Background scheduling: Configurable interval (default 5 min), immediate trigger support

3. **Architecture Decisions**:
   - Actor pattern for `SyncEngine` and `SyncLock` (thread-safe sync operations)
   - `@Observable` for `SyncCoordinator` (reactive UI updates)
   - Integrated with app lifecycle via `CluademailApp.swift`
   - Uses existing `RetryHelper` from Task 05 for error handling

4. **Test Coverage**:
   - 51 unit tests covering all sync components
   - Mock infrastructure: `MockDatabaseService`, `MockGmailAPIService`
   - Test fixtures for Gmail history DTOs

5. **Deferred Items**:
   - IMAP fallback sync (lower priority - Gmail API is primary)
   - Thread derivation (can be added in Task 08 - Email List & Threading)
   - History deduplication optimization
   - Partial failure recovery manager

6. **Bug Fix - SwiftData Threading** (2026-02-02):
   - Updated `SyncEngine` to use new non-filtered `count(account:context:)` method
   - Background sync now correctly uses repository methods without MainActor requirement
   - See `docs/swiftdata_threading_crash.md` for full context

7. **Next Steps**: Tasks 08 (Email List & Threading) and 11 (Settings & Notifications) are now unblocked

## References

- [Gmail API Sync](https://developers.google.com/gmail/api/guides/sync)
- [Gmail History API](https://developers.google.com/gmail/api/reference/rest/v1/users.history)
- [Partial Sync](https://developers.google.com/gmail/api/guides/sync#partial_synchronization)
- [Swift Actors](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Actors)
