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
1. Accounts (person.2 icon)
2. Sync (arrow.triangle.2.circlepath icon)
3. Notifications (bell icon)
4. MCP Server (network icon)

**Configuration**:
- Frame: 500x400

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
- REPLY: Text input action with "Send" button

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
- `didReceive`: Handle action responses (mark read, archive, reply, default tap)

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

## Acceptance Criteria

- [ ] Settings window opens from menu bar (Cmd+,)
- [ ] Accounts tab shows all connected accounts
- [ ] Can add new Gmail account via OAuth
- [ ] Can remove account with confirmation
- [ ] Account removal deletes tokens and local data
- [ ] Sync interval can be configured
- [ ] Manual sync button triggers immediate sync
- [ ] Sync status shows last sync time
- [ ] MCP server can be enabled/disabled
- [ ] MCP server status shows running state
- [ ] Available MCP tools are listed
- [ ] Notification permissions are requested
- [ ] Notifications appear for new emails
- [ ] Notification sound can be toggled
- [ ] Dock badge can be toggled
- [ ] Notification actions work (mark read, archive)
- [ ] Clicking notification navigates to email

## References

- [SwiftUI Settings](https://developer.apple.com/documentation/swiftui/settings)
- [User Notifications](https://developer.apple.com/documentation/usernotifications)
- [macOS Human Interface Guidelines - Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [@AppStorage](https://developer.apple.com/documentation/swiftui/appstorage)
