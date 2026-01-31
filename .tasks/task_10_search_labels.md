# Task 10: Search & Labels

## Task Overview

Implement the in-app search functionality for finding emails by various criteria, and the label viewing/management system for viewing and applying Gmail labels to emails.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 02: Core Data Models
- Task 03: Local Database Layer
- Task 05: Gmail API Service
- Task 07: Main Window & Navigation

## Architectural Guidelines

### Design Patterns
- **Search Strategy**: Local search with server fallback
- **Debouncing**: Debounce search input to avoid excessive queries
- **Caching**: Cache label list per account

### SwiftUI/Swift Conventions
- Use `.searchable()` modifier for search integration
- Use `.searchSuggestions()` for autocomplete
- Follow macOS search patterns

### File Organization
```
Features/Search/
├── SearchService.swift
├── SearchResultsView.swift
├── SearchSuggestionsView.swift
└── SearchFilters.swift

Features/Labels/
├── LabelService.swift
├── LabelPickerView.swift
├── LabelBadgeView.swift
└── UserLabelsView.swift
```

## Implementation Details

### SearchService

**Purpose**: Local and server search coordination
**Type**: `@Observable` class

**Properties**:
- `searchQuery`: String
- `searchResults`: [Email]
- `isSearching`: Bool
- `searchScope`: enum (all, inbox, sent, drafts)
- `filters`: SearchFilters

**Public Interface**:
- `search(query:account:) async`
- `clearSearch()`

**Search Flow**:
1. Cancel any in-progress search (task cancellation)
2. Set isSearching=true
3. Determine search scope (single account vs all accounts)
4. Search local database first via EmailRepository
5. Evaluate server search trigger (see below)
6. If triggered, search server via Gmail API
7. Merge results avoiding duplicates (by gmailId)
8. Sort by relevance (exact match > partial match > snippet match) then by date
9. Set isSearching=false

**Server Search Trigger Conditions**:
| Condition | Trigger Server Search |
|-----------|----------------------|
| Local results < 10 | Yes |
| User explicitly requests "Search server" | Yes |
| Query uses Gmail-only operators (category:, newer_than:) | Yes |
| Local results ≥ 10 but user scrolls to bottom | Yes (pagination) |
| Query is simple text and local results ≥ 20 | No (local sufficient) |

**Multi-Account Search**:

When searching "All Accounts" (filters.accountIds is nil):

```swift
func searchAllAccounts(query: String, filters: SearchFilters) async throws -> [Email] {
    let accounts = await accountRepository.fetchAll()

    // Local search across all accounts
    var localResults: [Email] = []
    for account in accounts {
        let results = try await emailRepository.search(query: query, account: account)
        localResults.append(contentsOf: results)
    }

    // Dedupe and sort by date
    localResults = localResults
        .unique(by: \.gmailId)
        .sorted { $0.date > $1.date }

    // Server search if needed (parallel across accounts)
    if shouldTriggerServerSearch(localCount: localResults.count, query: query) {
        let serverResults = try await withThrowingTaskGroup(of: [Email].self) { group in
            for account in accounts {
                group.addTask {
                    try await self.gmailService.searchMessages(account: account, query: query)
                }
            }
            var all: [Email] = []
            for try await results in group {
                all.append(contentsOf: results)
            }
            return all
        }

        // Merge server results with local, dedupe
        localResults = (localResults + serverResults)
            .unique(by: \.gmailId)
            .sorted { $0.date > $1.date }
    }

    return Array(localResults.prefix(100))  // Cap at 100 results
}
```

**Account Badge in Results**:
- When searching all accounts, show AccountBadge on each result
- Color-coded by account for quick identification

**Gmail Query Building**:
- If query contains operators (e.g., "from:"), use as-is
- Otherwise, combine text query with filter values
- Supported filters: from, to, after date, before date, has:attachment, is:unread
- For multi-account: each account searched with same query

---

### SearchFilters

**Purpose**: Advanced search filter state
**Type**: Struct

**Properties**:
- `from`: String?
- `to`: String?
- `afterDate`: Date?
- `beforeDate`: Date?
- `hasAttachment`: Bool
- `isUnread`: Bool
- `labelIds`: [String]
- `accountIds`: [UUID]? (nil = all accounts)

**Computed**:
- `isActive`: Bool - true if any filter is set
- `isMultiAccount`: Bool - accountIds is nil or has multiple values

---

### SearchResultsView

**Purpose**: Display search results with highlighting
**Type**: SwiftUI View

**Layout**:
- Header: "Search Results" + count + Clear button
- Active filters bar (if any)
- Results list with SearchResultRow items
- EmptyStateView if no results

---

### SearchResultRow

**Purpose**: Search result with text highlighting
**Type**: SwiftUI View

**Elements**:
- Sender, date
- Subject with highlighted matches
- Snippet with highlighted matches
- Account badge

**Highlighting**:
- Use AttributedString to highlight matching text
- Yellow background at 30% opacity
- Bold font for matches

---

### HighlightedText

**Purpose**: Highlight search matches in text
**Type**: SwiftUI View

**Behavior**:
- Find all occurrences of highlight string (case-insensitive)
- Apply backgroundColor and bold font to ranges
- Return Text view with AttributedString

---

### SearchFiltersBar

**Purpose**: Display active filters as removable chips
**Type**: SwiftUI View

**Layout**:
- Horizontal ScrollView
- FilterChip for each active filter
- "Add filter..." button (opens FilterPickerPopover)

**FilterChip**:
- Label text describing filter
- X button to remove
- Capsule background

---

### FilterPickerPopover

**Purpose**: Add new search filters via popover menu
**Type**: SwiftUI View

**Filter Options**:
| Filter | Control | Format |
|--------|---------|--------|
| From | TextField | Email or name |
| To | TextField | Email or name |
| After date | DatePicker | Calendar picker |
| Before date | DatePicker | Calendar picker |
| Has attachment | Toggle | On/off |
| Unread only | Toggle | On/off |
| Label | LabelPicker | Multi-select |
| Account | AccountPicker | Multi-select (for multi-account search) |

**Layout**:
```
┌─────────────────────────────┐
│ Add Filter                  │
├─────────────────────────────┤
│ From:     [____________]    │
│ To:       [____________]    │
│ After:    [📅 Select date]  │
│ Before:   [📅 Select date]  │
│ ☐ Has attachment            │
│ ☐ Unread only               │
│ Labels:   [Select...]    ▼  │
│ Accounts: [All accounts] ▼  │
├─────────────────────────────┤
│        [Apply Filters]      │
└─────────────────────────────┘
```

---

### DateRangePickerView

**Purpose**: Select date range for search filters
**Type**: SwiftUI View

**Elements**:
- "After" DatePicker (optional, can be nil)
- "Before" DatePicker (optional, can be nil)
- Quick presets: Today, Last 7 days, Last 30 days, Last year

**Behavior**:
- Validate: afterDate must be before beforeDate
- Show error if invalid range
- Presets auto-fill both dates

**Date Format**:
- Display: Localized medium date (e.g., "Jan 15, 2024")
- Gmail query: yyyy/MM/dd format

---

### LabelFilterPicker

**Purpose**: Select labels to filter search results
**Type**: SwiftUI View

**Layout**:
- List of user labels with checkboxes
- "Select All" / "Clear All" buttons
- Color indicator for each label

**Behavior**:
- Load labels from LabelService
- Multi-select enabled
- Selected labels added to SearchFilters.labelIds

---

### Gmail Search Operators

For reference in documentation:
```
from:{email}        - From specific sender
to:{email}          - To specific recipient
subject:{text}      - Subject contains text
after:{yyyy/MM/dd}  - After date
before:{yyyy/MM/dd} - Before date
has:attachment      - Has attachments
is:unread           - Unread only
is:starred          - Starred only
label:{name}        - Has label
```

---

### LabelService

**Purpose**: Label fetching and management
**Type**: `@Observable` class

**Properties**:
- `labelsCache`: [UUID: [Label]] - Per-account cache

**Dependencies**:
- LabelRepository
- GmailAPIService

**Public Interface**:
- `getLabels(for:) async throws -> [Label]`
- `getUserLabels(for:) async throws -> [Label]`
- `getSystemLabels(for:) async throws -> [Label]`
- `applyLabel(_:to:account:) async throws`
- `removeLabel(_:from:account:) async throws`
- `refreshLabels(for:) async throws`

**Caching Behavior**:
- Check cache first
- If miss, fetch from local repository
- Store in cache
- `refreshLabels` clears cache after update

**Label Application**:
- Call Gmail API modifyMessage
- Update local email.labelIds

---

### LabelPickerView

**Purpose**: Select labels to apply to email
**Type**: SwiftUI View

**Layout**:
- Header: "Labels"
- Loading state: ProgressView
- List of labels with checkmarks
- Done button footer

**Behavior**:
- Load user labels on appear
- Track selected label IDs (from email.labelIds)
- Toggle adds/removes label via LabelService
- Update UI immediately

---

### LabelRowView

**Purpose**: Single label in picker
**Type**: SwiftUI View

**Elements**:
- Color indicator circle (from backgroundColor)
- Label name
- Checkmark if selected

---

### LabelBadgeView

**Purpose**: Display label as colored badge
**Type**: SwiftUI View

**Styling**:
- Background from label.backgroundColor (hex)
- Text color from label.textColor (hex)
- Caption2 font
- Rounded corners (4pt)

---

### UserLabelsView

**Purpose**: Display user labels in sidebar
**Type**: SwiftUI View

**Behavior**:
- Load user labels on appear
- Display each with color indicator
- Tap to filter by label

---

### Color from Hex Extension

**Purpose**: Parse Gmail hex color strings
**Type**: Color extension

**Behavior**:
- Remove # prefix if present
- Parse 6-character hex (RGB)
- Return nil if invalid format

---

### Key Considerations

- **Search Scope**: Search subject, sender, snippet locally
- **Gmail Search Syntax**: Support standard Gmail operators
- **Label Colors**: Gmail provides hex colors; display correctly
- **System vs User Labels**: Only show user labels in picker
- **Batch Label Operations**: Support applying labels to multiple emails (future)
- **Debouncing**: Debounce search input to avoid excessive queries

## Acceptance Criteria

- [ ] Search bar appears in toolbar with `.searchable()`
- [ ] Search queries local database first
- [ ] Search falls back to Gmail API for more results
- [ ] **Server search triggered** when local < 10 results or user requests
- [ ] **Multi-account search** works from "All Accounts" view
- [ ] **Parallel search** across accounts for server queries
- [ ] Search results highlight matching text
- [ ] Search supports Gmail operators (from:, to:, subject:)
- [ ] Advanced filters can be applied (date, attachment, unread)
- [ ] **Date range picker** allows selecting after/before dates
- [ ] **Date presets** (Today, Last 7 days, etc.) work correctly
- [ ] **Label filter picker** allows selecting multiple labels
- [ ] **FilterPickerPopover** accessible via "Add filter..." button
- [ ] Filter chips show active filters
- [ ] Label picker shows user labels
- [ ] Labels can be applied/removed from emails
- [ ] Label colors display correctly
- [ ] User labels appear in sidebar when account selected
- [ ] Label filtering works from sidebar
- [ ] **Account badge** shows on results in multi-account search
- [ ] Search is debounced to avoid excessive queries
- [ ] Empty state shows when no results
- [ ] Search can be cleared

## References

- [SwiftUI Searchable](https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:))
- [Gmail Search Operators](https://support.google.com/mail/answer/7190)
- [Gmail Labels API](https://developers.google.com/gmail/api/reference/rest/v1/users.labels)
