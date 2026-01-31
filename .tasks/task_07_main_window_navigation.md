# Task 07: Main Window & Navigation

## Task Overview

Build the main application window structure with sidebar navigation, account tabs, and folder navigation. This establishes the foundational UI layout that all other views will integrate into.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 02: Core Data Models
- Task 03: Local Database Layer
- Task 04: Google OAuth & Keychain (for account data)

## Architectural Guidelines

### Design Patterns
- **Coordinator Pattern**: Use navigation state for controlling view hierarchy
- **Container/Presentational**: Separate logic from presentation
- **Composition**: Build complex UI from small, reusable components

### SwiftUI/Swift Conventions
- Use `NavigationSplitView` for three-column layout
- Use `@State` and `@Binding` for view-local state
- Use environment objects for shared state
- Follow Apple HIG for macOS sidebar design

### File Organization
```
Features/
├── Main/
│   ├── MainView.swift
│   ├── ContentView.swift
│   └── NavigationState.swift
├── Sidebar/
│   ├── SidebarView.swift
│   ├── AccountListView.swift
│   ├── FolderListView.swift
│   └── SyncStatusView.swift
└── Common/
    ├── AccountBadge.swift
    └── UnreadCountBadge.swift
```

## Implementation Details

### NavigationState

**Purpose**: Observable state for navigation
**Type**: `@Observable` class

**Properties**:
- `selectedAccount`: Account? (nil = All Accounts)
- `selectedFolder`: Folder = .inbox
- `selectedEmail`: Email?
- `selectedThread`: EmailThread?
- `searchQuery`: String = ""
- `isSearching`: Bool = false

**Computed Properties**:
- `displayTitle`: Combines folder name and account name for window title

**Methods**:
- `selectAccount(_:)` - Set account, clear email/thread selection
- `selectFolder(_:)` - Set folder, clear email/thread selection

---

### MainView

**Purpose**: Root view with NavigationSplitView
**Type**: SwiftUI View

**Structure**:
- Three-column NavigationSplitView
- Sidebar: SidebarView (200-300pt width)
- Content: EmailListView (300-500pt width)
- Detail: EmailDetailView (400pt+ width)

**Toolbar Items**:
- Compose button (square.and.pencil)
- Refresh button (arrow.clockwise)
- Sidebar toggle (sidebar.left)

**Configuration**:
- Minimum window size: 900x600
- Inject NavigationState into environment
- Apply ErrorAlertModifier for error display

---

### SidebarView

**Purpose**: Account list, folder navigation, sync status
**Type**: SwiftUI View

**Sections**:
1. **Accounts**: "All Accounts" option + list of accounts
2. **Folders**: Standard Gmail folders with unread badges
3. **Labels**: User labels (when single account selected)

**Layout**:
- List with sidebar style
- Safe area inset at bottom for SyncStatusView
- Selection binding to NavigationState

---

### AccountRow

**Purpose**: Display single account or "All Accounts" option
**Type**: SwiftUI View

**Elements**:
- Avatar (AsyncImage from profileImageURL, fallback to person.circle.fill)
- Display name (semibold if selected)
- Email address (caption, secondary color)
- For "All Accounts": tray.2 icon, "All Accounts" text

**Styling**:
- Vertical padding 4pt
- Highlight background when selected (accentColor at 15% opacity)
- Corner radius 6pt

---

### FolderRow

**Purpose**: Display folder with unread badge
**Type**: SwiftUI View

**Elements**:
- Label with folder icon and display name
- Unread count badge (if > 0)

**Behavior**:
- Load unread count on appear (task with account ID)
- Bold when selected

---

### UnreadCountBadge

**Purpose**: Show unread count
**Type**: SwiftUI View

**Styling**:
- Capsule shape
- Accent color background
- White foreground
- Caption2 font, medium weight
- Display "99+" if count exceeds 99

---

### SyncStatusView

**Purpose**: Show sync status and manual sync button
**Type**: SwiftUI View

**States**:
- Syncing: ProgressView + "Syncing..." text
- Idle: Checkmark icon (green) + "Synced X ago" (relative time)

**Actions**:
- Refresh button (disabled while syncing)

---

### AccountBadge

**Purpose**: Colored badge for account identification
**Type**: SwiftUI View

**Styling**:
- Extract username from email (before @)
- Caption2 font
- Capsule shape
- Color generated from email hash (consistent per account)

---

### App Entry Point Updates

**WindowGroup Configuration**:
- Default size: 1200x800
- Window style: automatic
- Commands: SidebarCommands, New Message (Cmd+N), Check Mail (Cmd+Shift+R)

**Settings Scene**:
- SettingsView with AppState in environment

---

### Accessibility Support

**Purpose**: Full VoiceOver and keyboard accessibility for all users

**VoiceOver Labels**:
| Element | Accessibility Label | Hint |
|---------|---------------------|------|
| Account row | "{name}, {email}" | "Double tap to select account" |
| All Accounts | "All Accounts" | "Shows emails from all accounts" |
| Folder row | "{folder name}, {N} unread" | "Double tap to view folder" |
| Unread badge | "{N} unread messages" | - |
| Sync status | "Last synced {time}" or "Syncing" | - |
| Compose button | "Compose new email" | "Opens compose window" |
| Refresh button | "Check for new mail" | "Syncs all accounts" |

**Focus Management**:
- Use `@FocusState` with Column enum (sidebar, list, detail)
- Apply `.focused()` modifier to each column view
- Handle Tab key to cycle focus between columns
- Each column should be focusable for keyboard navigation

**Keyboard Shortcuts**:
| Key | Action | Context |
|-----|--------|---------|
| ↑/↓ | Navigate list items | Sidebar, Email list |
| ←/→ | Switch columns | Any |
| Enter | Select/Open | List items |
| Space | Toggle star | Email selected |
| Delete | Move to trash | Email selected |
| Cmd+1-6 | Switch folders | Global |
| Cmd+[ / ] | Previous/Next email | Email list |

**Reduced Motion Support**:
- Read `@Environment(\.accessibilityReduceMotion)` to check user preference
- Skip animations when reduceMotion is true (pass nil to .animation modifier)
- Apply to all animated state changes (expansion, transitions, etc.)

---

### Window State Restoration

**Purpose**: Persist and restore window state across app launches

**Persisted State** (via `@SceneStorage`):
- `sidebar.isCollapsed`: Bool (default false)
- `selectedAccountId`: String? (nil = All Accounts)
- `selectedFolder`: String (default "inbox")
- `columnVisibility`: NavigationSplitViewVisibility (default .all)

**Window Frame Restoration**:
- Use `.defaultPosition(.center)` and `.defaultSize(width: 1200, height: 800)`
- Use `.windowResizability(.contentSize)` for proper sizing
- macOS automatically restores window position via NSWindow restoration mechanism

**State Restoration Flow**:
1. On launch: Read `@SceneStorage` values
2. Validate stored account ID still exists
3. Apply stored folder selection
4. Restore sidebar collapse state
5. Restore column visibility

**Invalid State Handling**:
- If stored account was deleted: default to "All Accounts"
- If stored folder invalid: default to Inbox
- If window size invalid: use default dimensions

**Last Selected Email**:
- Store `lastSelectedEmailId` in `@SceneStorage`
- On appear, check if stored email ID still exists in repository
- If found, restore selection to that email via NavigationState

---

### Drag and Drop Support

**Purpose**: Support drag-drop for attachments and email organization

**Drop Targets**:

| Target | Accepted Types | Action |
|--------|----------------|--------|
| Compose window | Files, URLs | Add as attachment |
| Folder row | Email items | Move email to folder |
| Trash folder | Email items | Delete email |
| Label row | Email items | Apply label |

**Attachment Drop in Compose**:
- Use `.onDrop(of: [.fileURL, .url])` modifier on compose view
- For each dropped provider, load file URL data
- Create AttachmentData with filename (lastPathComponent), mimeType (from UTType), and file data
- Append to attachments array

**Email Drag to Folder**:
- Apply `.draggable(email)` modifier to EmailRowView with custom drag preview
- Apply `.dropDestination(for: Email.self)` to FolderRow
- On drop, iterate through dropped emails and call emailService.moveToFolder for each
- Return true to indicate successful handling

**Visual Feedback**:
- Highlight drop target on hover
- Show (+) badge when valid drop
- Show (x) badge when invalid drop
- Animate email removal from source list

**Multi-Select Drag**:
- Support dragging multiple selected emails
- Show count badge on drag preview: "3 emails"

---

### Key Considerations

- **Window Size**: Set minimum and ideal window dimensions
- **Sidebar Collapse**: Support sidebar toggle via toolbar button
- **Keyboard Navigation**: Arrow keys navigate folder/email list
- **Focus Management**: Proper focus handling for list selection
- **Account Badges**: Use consistent colors derived from email address hash
- **Accessibility**: Full VoiceOver support with proper labels and hints
- **State Restoration**: Persist navigation state across launches
- **Drag and Drop**: Support file drops for attachments, email moves

## Acceptance Criteria

- [ ] `MainView` displays three-column NavigationSplitView
- [ ] Sidebar shows account list with "All Accounts" option
- [ ] Sidebar shows folder list with proper icons
- [ ] Folder selection updates `NavigationState`
- [ ] Account selection filters email list
- [ ] Unread count badges appear on folders
- [ ] Sync status shows in sidebar footer
- [ ] Manual sync button triggers sync
- [ ] Toolbar has compose and refresh buttons
- [ ] Sidebar can be toggled on/off
- [ ] Window has minimum size constraints
- [ ] Keyboard navigation works (arrow keys)
- [ ] Account badge shows consistent colors
- [ ] User labels section appears when account is selected
- [ ] **VoiceOver** announces all UI elements with proper labels
- [ ] **Accessibility hints** provided for interactive elements
- [ ] **Focus state** managed correctly between columns
- [ ] **Keyboard shortcuts** work (Cmd+1-6 for folders, etc.)
- [ ] **Reduced motion** respected for animations
- [ ] **Window state restored** on relaunch (position, size, sidebar state)
- [ ] **Selected account/folder** persisted via @SceneStorage
- [ ] **Invalid stored state** handled gracefully (deleted account, etc.)
- [ ] **Files dropped** on compose window added as attachments
- [ ] **Emails draggable** to folders for organization
- [ ] **Drop targets** highlight when valid drop hovering
- [ ] **Multi-select drag** shows count badge on preview

## References

- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [macOS Human Interface Guidelines - Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [SwiftUI List Styles](https://developer.apple.com/documentation/swiftui/liststyle)
- [SwiftUI Toolbar](https://developer.apple.com/documentation/swiftui/toolbar)
