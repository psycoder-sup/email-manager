# SwiftData Threading Crash on App Launch

## Issue
App crashes immediately on launch with `EXC_BAD_ACCESS (SIGSEGV)` when accessing SwiftData model properties.

## Root Cause
SwiftData models fetched from `mainContext` were being accessed from background threads. SwiftUI's `.task` modifier runs on cooperative thread pools, not the main actor, causing threading violations when repository methods filtered models in-memory.

**Crash location:** `Email.labelIds.getter` during filter operations in `EmailRepository.fetch()`.

## Affected Files
- `EmailRepository.swift` - In-memory filtering on wrong thread
- `FolderRow.swift` - `.task` calling `unreadCount()` with `mainContext`
- `SidebarView.swift` - `.task` calling `loadAccounts()` with `mainContext`
- `SettingsView.swift` - `.task` calling `loadAccounts()` with `mainContext`

## Fix
1. **Split repository methods** into folder-filtered (`@MainActor`) and non-filtered variants
2. **Add `@MainActor`** to UI view methods that use `mainContext`
3. **Update `SyncEngine`** to use non-filtered methods for background context operations

## Code Changes

```swift
// Before: Optional folder, no actor isolation
func fetch(account: Account?, folder: String?, ...) async throws -> [Email]

// After: Separate methods with explicit isolation
@MainActor
func fetch(account: Account?, folder: String, ...) async throws -> [Email]  // For UI

func fetch(account: Account?, isRead: Bool?, ...) async throws -> [Email]   // For background
```

```swift
// UI views now explicitly run on MainActor
@MainActor
private func loadUnreadCount() async { ... }
```

## Commit
`4390dcc` - fix(threading): resolve SwiftData context crashes with MainActor isolation
