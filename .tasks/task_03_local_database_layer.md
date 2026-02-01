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

- [x] `DatabaseService` creates and configures `ModelContainer` correctly
- [x] All repository protocols are defined with clear interfaces
- [x] `AccountRepository` implements all CRUD operations
- [x] `EmailRepository` supports filtering by account, folder, read status
- [x] `EmailRepository.search()` searches across subject, sender, and snippet
- [x] `EmailRepository.deleteOldest()` enforces the 1000 email limit
- [x] Unread count queries work for both global and per-account/folder
- [x] Background context creation works for sync operations
- [x] All repositories handle errors appropriately
- [x] Unit tests cover repository operations with in-memory database

## Completion Summary

**Status:** COMPLETED

**Date:** 2026-01-31

**Implementation Notes:**

1. **Architecture**: Clean architecture with generic `BaseRepository<T>` providing common CRUD operations
   - Protocol-based design for testability and mockability
   - Per-method `ModelContext` parameter for flexibility with main/background contexts
   - `@Observable` `DatabaseService` for SwiftUI environment injection

2. **Files Created** (8 source files):
   - `Core/Errors/DatabaseError.swift` - Typed errors (DB_001-DB_004) conforming to AppError
   - `Core/Services/DatabaseService.swift` - ModelContainer management, context factory
   - `Core/Repositories/RepositoryProtocols.swift` - Protocol definitions for all repositories
   - `Core/Repositories/BaseRepository.swift` - Generic base class with fetch, save, delete, count
   - `Core/Repositories/AccountRepository.swift` - Account CRUD operations
   - `Core/Repositories/EmailRepository.swift` - Complex filtering, search, batch operations
   - `Core/Repositories/LabelRepository.swift` - Label CRUD operations
   - `Core/Repositories/SyncStateRepository.swift` - Sync state and historyId management

3. **Test Files Created** (5 files, 55 new tests):
   - `CluademailTests/Unit/Repositories/AccountRepositoryTests.swift` - 8 tests
   - `CluademailTests/Unit/Repositories/EmailRepositoryTests.swift` - 25 tests
   - `CluademailTests/Unit/Repositories/LabelRepositoryTests.swift` - 9 tests
   - `CluademailTests/Unit/Repositories/SyncStateRepositoryTests.swift` - 7 tests
   - `CluademailTests/Unit/Repositories/DatabaseServiceTests.swift` - 6 tests

4. **Files Modified**:
   - `App/CluademailApp.swift` - Replaced inline ModelContainer with DatabaseService

5. **Test Results**: 70 unit tests passing, 8 UI tests passing (78 total)

6. **Key Design Decisions**:
   - `BaseRepository<T>` marked `@unchecked Sendable` (stateless, thread-safe)
   - SwiftData predicates built explicitly for each filter combination (compile-time requirement)
   - `DatabaseError` enum with 4 cases: fetchFailed, saveFailed, deleteFailed, notFound
   - Background contexts created with `autosaveEnabled = false` for manual transaction control
   - Search uses `localizedStandardContains` for case-insensitive matching

7. **EmailRepository Features**:
   - Dynamic predicate building via `buildPredicate()` helper
   - Search across subject, fromAddress, snippet (limited to 100 results)
   - `deleteOldest()` enforces 1000 email limit per account
   - Separate `count()` and `unreadCount()` methods using `fetchCount()`

8. **Code Simplification** (2026-01-31):
   - Removed redundant MARK comments and verbose documentation
   - Used Swift 5.9+ implicit returns in switch expressions
   - Simplified predicates with shorthand closure syntax (`$0.property`)
   - Used `if let` shorthand syntax throughout
   - Replaced `for` loops with `forEach` where appropriate
   - Removed unnecessary debug logging (kept error logging)
   - Removed unused imports
   - Net reduction: ~100 lines of code removed while preserving all functionality

9. **Next Steps**: Task 04 (Google OAuth & Keychain) can now begin

## References

- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [FetchDescriptor](https://developer.apple.com/documentation/swiftdata/fetchdescriptor)
- [Predicate](https://developer.apple.com/documentation/foundation/predicate)
