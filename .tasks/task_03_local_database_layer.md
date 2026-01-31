# Task 03: Local Database Layer

## Task Overview

Set up SwiftData for local persistence, create repository classes that abstract database operations, and implement the data access patterns used throughout the app.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 02: Core Data Models

## Architectural Guidelines

### Design Patterns
- **Repository Pattern**: Abstract all data access behind repository protocols
- **Unit of Work**: Use ModelContext for transaction management
- **Specification Pattern**: Use predicates for complex queries

### SwiftUI/Swift Conventions
- Use `@Query` in views for reactive data binding
- Use `ModelContainer` at app level, `ModelContext` for operations
- Leverage SwiftData's automatic change tracking

### File Organization
```
Core/Repositories/
├── RepositoryProtocols.swift
├── AccountRepository.swift
├── EmailRepository.swift
├── LabelRepository.swift
└── SyncStateRepository.swift

Core/Services/
└── DatabaseService.swift
```

## Implementation Details

### DatabaseService

**Purpose**: Configure and manage SwiftData container
**Type**: Class with `@MainActor` isolation

**Responsibilities**:
- Create `ModelContainer` with schema for all models (Account, Email, EmailThread, Attachment, Label, SyncState)
- Configure `ModelConfiguration` for persistent storage
- Provide `mainContext` property for UI operations
- Factory method `newBackgroundContext()` for sync operations

**Initialization**:
- Fatal error if ModelContainer creation fails (unrecoverable)

---

### Repository Protocols

**AccountRepositoryProtocol**:
- `fetchAll() async throws -> [Account]`
- `fetch(byId:) async throws -> Account?`
- `fetch(byEmail:) async throws -> Account?`
- `save(_:) async throws`
- `delete(_:) async throws`

**EmailRepositoryProtocol**:
- `fetch(byGmailId:) async throws -> Email?`
- `fetch(account:folder:isRead:limit:offset:) async throws -> [Email]`
- `fetchThreads(account:folder:limit:) async throws -> [EmailThread]`
- `search(query:account:) async throws -> [Email]`
- `save(_:) async throws`
- `saveAll(_:) async throws`
- `delete(_:) async throws`
- `deleteOldest(account:keepCount:) async throws`
- `count(account:folder:) async throws -> Int`
- `unreadCount(account:folder:) async throws -> Int`

**LabelRepositoryProtocol**:
- `fetchAll(account:) async throws -> [Label]`
- `fetch(byGmailId:account:) async throws -> Label?`
- `save(_:) async throws`
- `saveAll(_:) async throws`

**SyncStateRepositoryProtocol**:
- `fetch(accountId:) async throws -> SyncState?`
- `save(_:) async throws`
- `updateHistoryId(_:for:) async throws`

---

### EmailRepository Implementation

**Query Building**:
- Build predicates dynamically based on filters
- Combine predicates with AND logic
- Sort by date descending by default

**Key Methods**:

`fetch(account:folder:isRead:limit:offset:)`:
- Build predicate from optional account, folder (label ID), and read status
- Apply sorting, limit, and offset via FetchDescriptor
- Return fetched results

`search(query:account:)`:
- Search across subject, fromAddress, fromName, snippet
- Use `localizedStandardContains` for case-insensitive matching
- Limit results to 100
- Sort by date descending

`saveAll(_:)`:
- Insert all emails into context
- Save context once at end (batch efficiency)

`deleteOldest(account:keepCount:)`:
- Fetch all emails for account sorted by date (newest first)
- If count exceeds keepCount, delete emails beyond that threshold
- Used to enforce 1000 email limit per account

`unreadCount(account:folder:)`:
- Filter by isRead=false plus optional account and folder
- Return count of matching emails

---

### AccountRepository Implementation

**Key Methods**:
- `fetchAll()`: Sort by email, return all
- `fetch(byId:)`: Predicate on id, limit 1
- `fetch(byEmail:)`: Predicate on email string, limit 1
- `save(_:)`: Insert and save context
- `delete(_:)`: Delete and save context

---

### Key Considerations

- **1000 Email Limit**: Enforce per-account email limit during sync via `deleteOldest`
- **Background Context**: Use separate contexts for background sync operations to avoid UI blocking
- **Batch Operations**: Insert multiple emails before single save for performance
- **Index Optimization**: SwiftData handles indexes automatically, but be aware of query patterns
- **Thread Safety**: Use SwiftData's actor isolation properly; ModelContext is not thread-safe

## Acceptance Criteria

- [ ] `DatabaseService` creates and configures `ModelContainer` correctly
- [ ] All repository protocols are defined with clear interfaces
- [ ] `AccountRepository` implements all CRUD operations
- [ ] `EmailRepository` supports filtering by account, folder, read status
- [ ] `EmailRepository.search()` searches across subject, sender, and snippet
- [ ] `EmailRepository.deleteOldest()` enforces the 1000 email limit
- [ ] Unread count queries work for both global and per-account/folder
- [ ] Background context creation works for sync operations
- [ ] All repositories handle errors appropriately
- [ ] Unit tests cover repository operations with in-memory database

## References

- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [FetchDescriptor](https://developer.apple.com/documentation/swiftdata/fetchdescriptor)
- [Predicate](https://developer.apple.com/documentation/foundation/predicate)
