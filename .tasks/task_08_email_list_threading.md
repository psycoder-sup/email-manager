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
- Support single AND multi-selection (Set<String>)

---

### Multi-Select & Bulk Operations

**Purpose**: Allow users to perform actions on multiple emails at once

**Selection Modes**:
- Use `@State` for `selectedEmailIds: Set<String>` and `isMultiSelectMode: Bool`
- Bind selection to List using `selection: $selectedEmailIds`
- Tag each email row with `email.gmailId` for selection tracking

**Enabling Multi-Select**:
| Trigger | Behavior |
|---------|----------|
| Cmd+Click | Add/remove from selection |
| Shift+Click | Select range from last selection |
| Cmd+A | Select all visible emails |
| Escape | Clear selection, exit multi-select mode |

**Bulk Action Toolbar** (appears when multiple selected):
- Show only when `selectedEmailIds.count > 1`
- Display selection count on left side
- Action buttons on right: Mark Read, Archive, Delete (destructive role)
- Use HStack with `.background(.bar)` for toolbar appearance

**Bulk Operations**:
| Action | Method | Confirmation |
|--------|--------|--------------|
| Mark as Read | `markAsRead(emailIds:)` | None |
| Mark as Unread | `markAsUnread(emailIds:)` | None |
| Star | `star(emailIds:)` | None |
| Unstar | `unstar(emailIds:)` | None |
| Archive | `archive(emailIds:)` | None |
| Delete | `moveToTrash(emailIds:)` | Alert if > 10 |
| Apply Label | `applyLabel(_:to:)` | None |
| Remove Label | `removeLabel(_:from:)` | None |

**Batch API Usage**:
- Use Gmail batch API for bulk operations (up to 50 per batch)
- Show progress indicator for large selections
- Handle partial failures gracefully

**EmailListViewModel Bulk Methods**:
- Set `isLoading = true` at start, use defer to reset
- Chunk email IDs into groups of 50 for batch API limits
- Call Gmail batch API to modify messages (e.g., remove "UNREAD" label)
- Update local email state for succeeded items in each batch

---

### Keyboard Navigation (Detailed)

**Purpose**: Full keyboard control for power users

**Navigation Keys**:
| Key | Action | Context |
|-----|--------|---------|
| ↓ / J | Select next email | List focused |
| ↑ / K | Select previous email | List focused |
| Enter | Open email in detail pane | Email selected |
| Space | Quick preview / scroll down | Email selected |
| Shift+Space | Scroll up | Email selected |
| Home / Cmd+↑ | Jump to first email | List focused |
| End / Cmd+↓ | Jump to last email | List focused |
| Page Up | Scroll up one page | List focused |
| Page Down | Scroll down one page | List focused |

**Action Keys**:
| Key | Action | Notes |
|-----|--------|-------|
| R | Reply | Opens compose |
| A | Reply All | Opens compose |
| F | Forward | Opens compose |
| S | Toggle star | Immediate |
| U | Toggle read/unread | Immediate |
| E | Archive | Immediate |
| # / Delete | Move to trash | Immediate |
| L | Open label picker | Shows popover |
| Cmd+Shift+U | Mark all as read | Current folder |

**Multi-Select Keys**:
| Key | Action |
|-----|--------|
| Cmd+A | Select all |
| Cmd+Click | Toggle selection |
| Shift+Click | Extend selection |
| Shift+↓/↑ | Extend selection up/down |
| Escape | Clear selection |

**Implementation**:
- Use `@FocusState` to track list focus
- Apply `.focused()` modifier to list
- Use `.onKeyPress()` for each action key, return `.handled` to consume the event
- Key mappings: arrows/j/k for navigation, r/s/u/e/delete for actions

**Focus Indicator**:
- Blue outline ring on focused row
- Visible focus state for accessibility

---

### Large List Performance

**Purpose**: Maintain smooth scrolling with 1000+ emails per account

**SwiftUI List Optimization**:
- Use ForEach inside List for optimal performance
- Apply `.id(email.gmailId)` for stable row identity
- Use `.listStyle(.inset(alternatesRowBackgrounds: true))` for visual styling

**Lazy Loading Strategy**:
- Initial load: 50 emails
- On scroll near bottom: Load 50 more
- Total cap: 1000 per account (per PRD)

**ScrollView Position Tracking**:
- Track `visibleEmailIds: Set<String>` to know which rows are on screen
- Use `ScrollViewReader` to enable programmatic scrolling
- Apply `.onAppear` and `.onDisappear` to track visible rows
- On email appear, check if near bottom of list (within last 5 items)
- If near bottom and more emails available, trigger `loadMore()` pagination
- Show ProgressView at bottom when `hasMoreEmails` is true

**Row View Optimization**:
- Avoid complex computed properties directly in view body
- Pre-compute values in ViewModel or as cached properties
- Use `.drawingGroup()` to flatten complex view hierarchies for better rendering
- Keep row views simple with basic views (Circle, Text, HStack, VStack)

**Pre-computed Display Values**:
- `cachedRelativeDate`: Use RelativeDateTimeFormatter, cache the result
- `displaySender`: Compute once - use fromName if available, otherwise extract username from email address

**Memory Management**:
- Release attachment data when row goes off-screen
- Use thumbnail images for avatars (not full-size)
- Limit snippet to 150 characters

**Performance Targets**:
| Metric | Target |
|--------|--------|
| Initial list render | < 100ms |
| Scroll FPS | 60 FPS |
| Memory per 1000 emails | < 50MB |
| Row recycle time | < 16ms |

**Instruments Profiling**:
- Use Time Profiler to identify slow renders
- Use Allocations to track memory
- Test with 3+ accounts (3000+ total emails)

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
- [ ] **Multi-select** works with Cmd+Click and Shift+Click
- [ ] **Bulk action toolbar** appears when multiple emails selected
- [ ] **Bulk operations** (mark read, archive, delete) work on selection
- [ ] **Cmd+A** selects all visible emails
- [ ] **Escape** clears selection and exits multi-select mode
- [ ] **Keyboard navigation** works (↑/↓, J/K, Enter, Space)
- [ ] **Action keys** work (R=reply, S=star, E=archive, Delete=trash)
- [ ] **Focus indicator** visible on focused row
- [ ] **Pagination** loads more emails on scroll (50 at a time)
- [ ] **Performance** maintains 60 FPS scroll with 1000+ emails
- [ ] **Memory** stays under 50MB per 1000 emails
- [ ] **Initial render** completes in < 100ms

## References

- [SwiftUI List](https://developer.apple.com/documentation/swiftui/list)
- [Swipe Actions](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:))
- [Context Menus](https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:))
- [SwiftData @Query](https://developer.apple.com/documentation/swiftdata/query)
