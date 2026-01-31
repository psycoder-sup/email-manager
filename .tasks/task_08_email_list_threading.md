# Task 08: Email List & Threading

## Task Overview

Build the email list view that displays conversations grouped by thread, with support for aggregated and per-account views, folder filtering, and proper visual indicators for read/unread status, stars, and attachments.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 02: Core Data Models
- Task 03: Local Database Layer
- Task 07: Main Window & Navigation

## Architectural Guidelines

### Design Patterns
- **View Composition**: Build list from small, reusable row components
- **Lazy Loading**: Use `LazyVStack` or SwiftUI List for efficient rendering
- **Debouncing**: Debounce rapid selection changes

### SwiftUI/Swift Conventions
- Use `@Query` with predicates for filtered data
- Use `List` with `selection` binding for single/multi-select
- Follow macOS list row design patterns

### File Organization
```
Features/EmailList/
├── EmailListView.swift
├── EmailListViewModel.swift
├── EmailRowView.swift
├── ThreadRowView.swift
└── EmptyStateView.swift
```

## Implementation Details

### EmailListViewModel

**Purpose**: Data fetching and manipulation logic
**Type**: `@Observable` class

**Properties**:
- `emails`: [Email]
- `threads`: [EmailThread]
- `isLoading`: Bool
- `errorMessage`: String?
- `displayMode`: enum (emails, threads)

**Public Interface**:
- `loadEmails(account:folder:) async`
- `loadMore() async` (pagination)
- `markAsRead(_:) async`
- `markAsUnread(_:) async`
- `toggleStar(_:) async`
- `archive(_:) async`
- `moveToTrash(_:) async`

**Loading Behavior**:
- Set isLoading=true during fetch
- Fetch from EmailRepository based on account, folder, displayMode
- Handle errors by setting errorMessage

---

### EmailListView

**Purpose**: Main list container
**Type**: SwiftUI View

**States**:
- Loading: Show ProgressView with message
- Empty: Show EmptyStateView
- Data: Show email/thread list

**List Configuration**:
- Inset style
- Alternating row backgrounds
- Selection binding to track selected IDs

**Toolbar**:
- View mode picker (threads vs messages, segmented)
- Sort menu (Date newest/oldest, Sender, Subject)

**Features**:
- Searchable modifier with toolbar placement
- Swipe actions (trailing: delete, archive; leading: read/unread toggle)
- Context menu on right-click

**Selection Handling**:
- On selection change, update NavigationState.selectedEmail or selectedThread
- Support single selection (Set<String>)

---

### EmailRowView

**Purpose**: Display single email row
**Type**: SwiftUI View

**Layout** (HStack):
1. Unread indicator: Blue circle (8pt) if unread, clear if read
2. Star button: Yellow star.fill if starred, gray star outline if not
3. Content VStack:
   - Row 1: Sender name/address, spacer, relative date
   - Row 2: Subject (or "No Subject"), attachment indicator if has attachments
   - Row 3: Snippet (2 line limit, secondary color)
   - Row 4: Account badge (if showAccountBadge)

**Styling**:
- Sender: Semibold if unread
- Subject: Secondary color if read
- Vertical padding 6pt

---

### ThreadRowView

**Purpose**: Display thread summary row
**Type**: SwiftUI View

**Layout** (similar to EmailRowView):
1. Unread indicator (8pt circle)
2. Star button
3. Content VStack:
   - Row 1: Participants (formatted), message count badge, spacer, date
   - Row 2: Subject
   - Row 3: Snippet
   - Row 4: Account badge (if applicable)

**Participant Formatting**:
- Show first 3 participants (username portion only)
- If more than 3, append "+N" for remaining

---

### EmptyStateView

**Purpose**: Display when no emails match criteria
**Type**: SwiftUI View

**Properties**:
- `folder`: Folder
- `searchQuery`: String? (optional)

**Content**:
- Icon: Search icon if query present, else folder icon
- Title: "No Results" for search, or folder-specific ("Inbox is Empty", etc.)
- Message: Contextual description

**Folder-Specific Messages**:
| Folder | Title | Message |
|--------|-------|---------|
| inbox | Inbox is Empty | New messages will appear here |
| sent | No Sent Messages | Messages you send will appear here |
| drafts | No Drafts | Drafts you save will appear here |
| starred | No Starred Messages | Star important messages to find them here |
| trash | Trash is Empty | Deleted messages appear here |
| spam | No Spam | Messages marked as spam appear here |
| allMail | No Messages | All your messages appear here |

---

### Context Menu Actions

**Available Actions**:
- Star/Unstar
- Mark as Read/Unread
- Divider
- Reply
- Forward
- Divider
- Archive
- Move to Trash (destructive)

---

### Swipe Actions

**Trailing Edge**:
- Delete (trash icon, destructive role)
- Archive (archivebox icon, blue tint)

**Leading Edge**:
- Read/Unread toggle (envelope.badge or envelope.open, purple tint)

---

### Key Considerations

- **Performance**: Use List for automatic cell reuse and lazy loading
- **Thread Grouping**: Display threads when in thread mode, expand on selection
- **Visual Hierarchy**: Clear distinction between sender, subject, snippet
- **Account Indicator**: Show badge in aggregated (All Accounts) view only
- **Selection Persistence**: Attempt to maintain selection across data refreshes
- **Context Menu**: Provide quick actions without leaving the list

## Acceptance Criteria

- [ ] Email list displays with proper formatting
- [ ] Thread view groups related emails
- [ ] Can switch between thread and message view
- [ ] Unread emails show visual indicator (blue dot)
- [ ] Starred emails show yellow star
- [ ] Attachment indicator shows for emails with attachments
- [ ] Account badge shows in aggregated view
- [ ] Selection updates navigation state
- [ ] Swipe actions work (delete, archive, read/unread)
- [ ] Context menu shows on right-click
- [ ] Empty state shows appropriate message per folder
- [ ] Search filters list results
- [ ] List scrolls smoothly with many items
- [ ] Relative dates display correctly (e.g., "2 hours ago")

## References

- [SwiftUI List](https://developer.apple.com/documentation/swiftui/list)
- [Swipe Actions](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:))
- [Context Menus](https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:))
- [SwiftData @Query](https://developer.apple.com/documentation/swiftdata/query)
