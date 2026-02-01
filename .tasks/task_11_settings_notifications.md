# Task 11: Settings & Notifications

## Task Overview

Build the Settings UI for account management, sync configuration, and MCP server control. Also implement macOS notifications for new email alerts.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 04: Google OAuth & Keychain
- Task 06: Email Sync Engine

## Architectural Guidelines

### Design Patterns
- **Preferences Pattern**: Use `@AppStorage` for simple settings
- **Observer Pattern**: Notify components of setting changes
- **Notification Center**: Use `UNUserNotificationCenter` for alerts

### SwiftUI/Swift Conventions
- Use SwiftUI Settings scene
- Use `TabView` for settings organization
- Follow macOS Settings design patterns

### File Organization
```
Features/Settings/
├── SettingsView.swift
├── GeneralSettingsView.swift
├── AccountsSettingsView.swift
├── SyncSettingsView.swift
├── MCPSettingsView.swift
└── NotificationSettingsView.swift

Core/Services/
└── NotificationService.swift
```

## Implementation Details

### SettingsView

**Purpose**: Main settings container with tabs
**Type**: SwiftUI View

**Tabs**:
1. General (gear icon)
2. Accounts (person.2 icon)
3. Sync (arrow.triangle.2.circlepath icon)
4. Notifications (bell icon)
5. MCP Server (network icon)

**Configuration**:
- Frame: 500x400
- Appearance: Follows system appearance (no custom dark mode toggle)

---

### GeneralSettingsView

**Purpose**: App version info and general settings
**Type**: SwiftUI View

**Layout**:
- About section with app icon, name, version
- Copyright notice

**About Section**:
- App icon (64x64)
- App name: "Cluademail"
- Version: Read from Bundle.main.infoDictionary (CFBundleShortVersionString)
- Build number: Read from Bundle.main.infoDictionary (CFBundleVersion)
- Copyright: "© 2024 Your Name. All rights reserved."

**Links** (optional):
- "Visit Website" button (if applicable)
- "View on GitHub" button (if open source)

**Out of Scope**:
- Dark mode toggle (app follows system appearance automatically)
- Database/cache size display
- Data export/backup options

---

### AccountsSettingsView

**Purpose**: Manage Gmail accounts
**Type**: SwiftUI View

**Layout**:
- Header: "Gmail Accounts"
- Account list (200pt height)
- Add Account button (right-aligned)
- Info text about OAuth/Keychain

**Account List Items**:
- Avatar, display name, email
- Status indicator (syncing: ProgressView, enabled: green dot, disabled: gray)
- Remove button (red minus.circle)

**Actions**:
- Add: Trigger OAuth flow via AuthenticationService
- Remove: Confirmation dialog, then sign out

**Confirmation Dialog**:
- Title: "Remove Account"
- Message: Warn about data deletion
- Actions: Remove (destructive), Cancel

---

### SyncSettingsView

**Purpose**: Configure sync behavior
**Type**: SwiftUI View

**Settings**:
- Sync interval picker (1 min, 5 min, 15 min, 30 min, 1 hour)
- Uses `@AppStorage("syncInterval")` with default 300

**Status GroupBox**:
- Current status: Syncing (ProgressView) or Idle (checkmark)
- Last sync time (relative)

**Actions**:
- Sync Now button (disabled while syncing)

**Footer Text**:
- "Cluademail stores the last 1,000 emails per account locally."

---

### MCPSettingsView

**Purpose**: Control MCP server
**Type**: SwiftUI View

**Settings**:
- Enable/disable toggle using `@AppStorage("mcpServerEnabled")`
- Toggle triggers server start/stop

**Status GroupBox**:
- Status: Running (green dot) or Stopped (gray dot)
- Transport: "stdio" (monospace)
- Connected clients count (when running)

**Tools GroupBox**:
- List available MCP tools with descriptions:

| Tool | Description |
|------|-------------|
| list_emails | List emails with filters |
| read_email | Read full email content |
| search_emails | Search by query |
| create_draft | Create email draft |
| manage_labels | Add/remove labels |
| get_attachment | Download attachment |

**Footer Text**:
- Explanation that AI can only create drafts, not send

---

### NotificationSettingsView

**Purpose**: Configure notification preferences
**Type**: SwiftUI View

**Permission Check**:
- If denied: Warning box with "Open Settings" button

**Settings** (all `@AppStorage`):
- `notificationsEnabled`: Enable notifications toggle
- `notificationSound`: Play sound toggle
- `notificationBadge`: Show dock badge toggle

**Options GroupBox** (shown when enabled):
- Sound toggle
- Badge toggle

**Footer Text**:
- "Notifications will appear for new emails when Cluademail is running."

---

### NotificationService

**Purpose**: Handle macOS notifications
**Type**: Singleton class conforming to UNUserNotificationCenterDelegate

**Notification Category**: `NEW_EMAIL`

**Notification Actions**:
- MARK_READ: "Mark as Read"
- ARCHIVE: "Archive"
- REPLY: Opens compose window with reply pre-filled (does NOT send directly)

**Note**: Reply action opens the app and presents the compose view. This maintains the PRD requirement that users must manually confirm and send all emails.

**Public Interface**:
- `requestAuthorization() async -> Bool`
- `sendNewEmailNotification(email:account:) async`
- `updateBadgeCount(_:)`
- `clearNotifications(for:)`
- `setupNotificationCategories()`

**Notification Content**:
- Title: Sender name/email
- Subtitle: Subject
- Body: Snippet
- Sound: Based on setting
- Category: NEW_EMAIL
- UserInfo: emailId, accountId
- Thread identifier: Groups by account

**Delegate Methods**:
- `willPresent`: Return [.banner, .sound, .badge] (show in foreground)
- `didReceive`: Handle action responses:
  - MARK_READ: Call Gmail API to remove UNREAD label
  - ARCHIVE: Call Gmail API to archive
  - REPLY: Post notification to open compose window with reply context
  - Default tap: Navigate to email in main window

**Navigation Notification**:
- Post `Notification.Name.navigateToEmail` on default tap
- UserInfo contains emailId and accountId

---

### System Settings Link

**Purpose**: Open macOS notification settings
**URL**: `x-apple.systempreferences:com.apple.preference.notifications`

---

### Key Considerations

- **macOS Settings**: Follow platform conventions for preferences window
- **Permission Handling**: Check and request notification permission gracefully
- **Account Removal**: Clean up tokens from Keychain and data from database
- **Sync Interval**: Validate and apply to SyncScheduler
- **MCP Status**: Reflect actual server state
- **System Appearance**: App automatically follows macOS light/dark mode; no manual toggle needed
- **Notification Reply**: Must open compose window, never send directly (maintains user control)

### Out of Scope (v1)

- Custom dark mode toggle (follows system)
- Database/cache size display
- Data export or backup functionality
- Per-account default setting
- Custom notification sounds

## Acceptance Criteria

- [x] Settings window opens from menu bar (Cmd+,)
- [x] **General tab** shows app name, version, and build number
- [x] **General tab** displays copyright notice
- [x] App follows system appearance automatically (no manual dark mode toggle)
- [x] Accounts tab shows all connected accounts
- [x] Can add new Gmail account via OAuth
- [x] Can remove account with confirmation
- [x] Account removal deletes tokens and local data
- [x] Sync interval can be configured
- [x] Manual sync button triggers immediate sync
- [x] Sync status shows last sync time
- [x] MCP server can be enabled/disabled
- [x] MCP server status shows running state
- [x] Available MCP tools are listed
- [x] Notification permissions are requested
- [x] Notifications appear for new emails
- [x] Notification sound can be toggled
- [x] Dock badge can be toggled
- [x] Notification actions work (mark read, archive)
- [x] **Notification reply action** opens compose window (does not send directly)
- [x] Clicking notification navigates to email

## References

- [SwiftUI Settings](https://developer.apple.com/documentation/swiftui/settings)
- [User Notifications](https://developer.apple.com/documentation/usernotifications)
- [macOS Human Interface Guidelines - Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [@AppStorage](https://developer.apple.com/documentation/swiftui/appstorage)

---

## Completion Summary

**Status:** ✅ Complete
**Completed:** 2026-02-01

### Files Created

| File | Purpose |
|------|---------|
| `Core/Services/NotificationService.swift` | macOS notification handling with UNUserNotificationCenter |
| `Features/Settings/GeneralSettingsView.swift` | App info tab with version and copyright |
| `Features/Settings/NotificationSettingsView.swift` | Notification preferences UI |

### Files Modified

| File | Changes |
|------|---------|
| `Features/Settings/SettingsView.swift` | 5-tab layout, accounts/sync/MCP views expanded |
| `App/CluademailApp.swift` | Notification service setup, event handlers |
| `App/AppDelegate.swift` | Notification delegate and categories setup |
| `Core/Services/Sync/SyncScheduler.swift` | Added `@Observable` for environment injection |

### Features Implemented

1. **Settings Window (5 Tabs)**
   - General: App icon, name, version, build, copyright
   - Accounts: List, add via OAuth, remove with confirmation
   - Sync: Interval picker, manual sync, status display
   - Notifications: Permission check, sound/badge toggles
   - MCP: Enable toggle, status, tools list

2. **NotificationService**
   - Authorization request and status tracking
   - Notification categories with actions (Mark Read, Archive, Reply)
   - Badge count management with 99+ cap
   - Action handlers calling Gmail API
   - Foundation.Notification posting for navigation/compose

3. **App Integration**
   - Notification delegate set in AppDelegate
   - Event observers for `.navigateToEmail` and `.openComposeWithReply`
   - Environment injection of SyncScheduler and NotificationService

### Code Quality

- Applied code-simplifier refinements:
  - Extracted `modifyEmailFromNotification` and `postEmailNotification` helpers
  - Extracted `statusIndicator` and `syncStatusView` computed properties
  - Extracted `extractEmailContext` helper in CluademailApp

### Test Coverage

- UI tests verify settings window and tab navigation
- Unit tests cover notification service authorization and badge updates

### Deferred Items

- Per-account notification settings (v2)
- Custom notification sounds (v2)
- Database/cache size display (v2)
