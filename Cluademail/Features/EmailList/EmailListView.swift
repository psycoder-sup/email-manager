import SwiftUI
import os.log

/// Main email list view displaying emails or threads with selection and actions.
struct EmailListView: View {
    @Environment(AppState.self) private var appState
    @Environment(DatabaseService.self) private var databaseService

    @State private var viewModel: EmailListViewModel?
    @State private var searchText = ""
    @State private var showFilterPicker = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isListFocused: Bool

    /// Task ID for reactive reloading when account or folder changes.
    private var taskId: String {
        "\(appState.selectedAccount?.id.uuidString ?? "all")-\(appState.selectedFolder.rawValue)"
    }

    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = EmailListViewModel(databaseService: databaseService, appState: appState)
            }
        }
        .task(id: taskId) {
            await viewModel?.loadData(account: appState.selectedAccount, folder: appState.selectedFolder)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search emails")
        .onChange(of: searchText) { _, newValue in
            // Cancel previous debounce task
            searchTask?.cancel()

            // Debounce search input (300ms)
            searchTask = Task {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    viewModel?.searchQuery = newValue
                } catch {
                    // Task was cancelled, ignore
                }
            }
        }
        .onSubmit(of: .search) {
            // Save to history when user submits search
            viewModel?.saveSearchToHistory()
        }
        .popover(isPresented: $showFilterPicker) {
            if let vm = viewModel {
                FilterPickerPopover(
                    filters: Binding(
                        get: { vm.searchFilters },
                        set: { vm.searchFilters = $0 }
                    ),
                    isPresented: $showFilterPicker
                )
            }
        }
        .onChange(of: viewModel?.selectedIds) { _, newIds in
            // Update appState.selectedEmail when a single email is selected
            guard let newIds, newIds.count == 1, let selectedId = newIds.first else {
                // Clear selection if none or multiple selected
                if newIds?.isEmpty ?? true {
                    appState.selectedEmail = nil
                }
                return
            }
            // Find the selected email and update appState
            if let email = viewModel?.emails.first(where: { $0.gmailId == selectedId }) {
                appState.selectedEmail = email
            }
        }
        .onChange(of: appState.isSyncing) { oldValue, newValue in
            // Reload data when sync completes (isSyncing changes from true to false)
            if oldValue && !newValue {
                // Explicitly refresh context before reloading data
                databaseService.refreshMainContext()
                Task {
                    await viewModel?.loadData(account: appState.selectedAccount, folder: appState.selectedFolder)
                }
            }
        }
        .onChange(of: appState.unreadCountVersion) { _, _ in
            // Force re-render by triggering observable change
            viewModel?.triggerUIRefresh()
        }
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private func contentView(viewModel: EmailListViewModel) -> some View {
        if let errorMessage = viewModel.errorMessage {
            errorView(message: errorMessage, viewModel: viewModel)
        } else if viewModel.isLoading && viewModel.displayedItems.isEmpty {
            loadingView
        } else if viewModel.displayedItems.isEmpty {
            EmptyStateView(folder: appState.selectedFolder, searchQuery: searchText.isEmpty ? nil : searchText)
        } else {
            listContent(viewModel: viewModel)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading emails...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String, viewModel: EmailListViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Try Again") {
                Task {
                    await viewModel.loadData(account: appState.selectedAccount, folder: appState.selectedFolder)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List Content

    @ViewBuilder
    private func listContent(viewModel: EmailListViewModel) -> some View {
        VStack(spacing: 0) {
            // Search filters bar (shown when filters are active)
            if viewModel.searchFilters.isActive {
                SearchFiltersBar(
                    filters: Binding(
                        get: { viewModel.searchFilters },
                        set: { viewModel.searchFilters = $0 }
                    ),
                    onAddFilter: { showFilterPicker = true }
                )
            }

            List(selection: Binding(
                get: { viewModel.selectedIds },
                set: { viewModel.selectedIds = $0 }
            )) {
                switch viewModel.displayMode {
                case .emails:
                    emailsList(viewModel: viewModel)
                case .threads:
                    threadsList(viewModel: viewModel)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .focused($isListFocused)
            .onKeyPress { keyPress in
                handleKeyPress(keyPress, viewModel: viewModel)
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.isMultiSelectMode {
                    bulkActionToolbar(viewModel: viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private func emailsList(viewModel: EmailListViewModel) -> some View {
        ForEach(viewModel.emails, id: \.gmailId) { email in
            EmailRowView(
                email: email,
                showAccountBadge: appState.selectedAccount == nil,
                onStarToggle: {
                    Task { await viewModel.toggleStar(emailIds: [email.gmailId]) }
                }
            )
            .tag(email.gmailId)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task { await viewModel.moveToTrash(emailIds: [email.gmailId]) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    Task { await viewModel.archive(emailIds: [email.gmailId]) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await viewModel.toggleReadStatus(emailIds: [email.gmailId]) }
                } label: {
                    Label(
                        email.isRead ? "Mark Unread" : "Mark Read",
                        systemImage: email.isRead ? "envelope.badge" : "envelope.open"
                    )
                }
                .tint(.purple)
            }
            .contextMenu {
                emailContextMenu(email: email, viewModel: viewModel)
            }
            .onAppear {
                triggerPaginationIfNeeded(email: email, viewModel: viewModel)
            }
        }

        if viewModel.isLoadingMore {
            loadingMoreIndicator
        }

        // Server search section (shown when search is active)
        if viewModel.isSearchActive {
            serverSearchSection(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func serverSearchSection(viewModel: EmailListViewModel) -> some View {
        if viewModel.isLoadingFromServer {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Searching server...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        } else if viewModel.hasSearchedServer {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Searched all emails on server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        } else if viewModel.emails.count >= 10 {
            Button {
                Task { await viewModel.loadMoreFromServer() }
            } label: {
                HStack {
                    Image(systemName: "cloud")
                    Text("Load more from server")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private func triggerPaginationIfNeeded(email: Email, viewModel: EmailListViewModel) {
        guard email.gmailId == viewModel.emails.suffix(5).first?.gmailId else { return }
        Task {
            await viewModel.loadMore(account: appState.selectedAccount, folder: appState.selectedFolder)
        }
    }

    private var loadingMoreIndicator: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func threadsList(viewModel: EmailListViewModel) -> some View {
        ForEach(viewModel.threads, id: \.threadId) { thread in
            ThreadRowView(
                thread: thread,
                showAccountBadge: appState.selectedAccount == nil,
                onStarToggle: {
                    Logger.ui.info("Thread star toggle not implemented yet")
                }
            )
            .tag(thread.threadId)
            .contextMenu {
                threadContextMenu(thread: thread)
            }
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func emailContextMenu(email: Email, viewModel: EmailListViewModel) -> some View {
        Button {
            Task { await viewModel.toggleStar(emailIds: [email.gmailId]) }
        } label: {
            Label(email.isStarred ? "Unstar" : "Star", systemImage: email.isStarred ? "star.fill" : "star")
        }

        Button {
            Task { await viewModel.toggleReadStatus(emailIds: [email.gmailId]) }
        } label: {
            Label(
                email.isRead ? "Mark as Unread" : "Mark as Read",
                systemImage: email.isRead ? "envelope.badge" : "envelope.open"
            )
        }

        Divider()

        Button {
            Logger.ui.info("Reply tapped")
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }

        Button {
            Logger.ui.info("Forward tapped")
        } label: {
            Label("Forward", systemImage: "arrowshape.turn.up.right")
        }

        Divider()

        Button {
            Task { await viewModel.archive(emailIds: [email.gmailId]) }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }

        Button(role: .destructive) {
            Task { await viewModel.moveToTrash(emailIds: [email.gmailId]) }
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func threadContextMenu(thread: EmailThread) -> some View {
        Button {
            Logger.ui.info("Thread star toggle - not implemented")
        } label: {
            Label(thread.isStarred ? "Unstar" : "Star", systemImage: thread.isStarred ? "star.fill" : "star")
        }
        .disabled(true)

        Divider()

        Button {
            Logger.ui.info("Archive thread - not implemented")
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .disabled(true)

        Button(role: .destructive) {
            Logger.ui.info("Delete thread - not implemented")
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
        .disabled(true)
    }

    // MARK: - Bulk Action Toolbar

    private func bulkActionToolbar(viewModel: EmailListViewModel) -> some View {
        HStack {
            Text("\(viewModel.selectedIds.count) selected")
                .foregroundStyle(.secondary)

            Spacer()

            Button("Mark Read") {
                Task { await viewModel.markAsRead(emailIds: viewModel.selectedIds) }
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            Button("Archive") {
                Task { await viewModel.archive(emailIds: viewModel.selectedIds) }
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            Button("Delete", role: .destructive) {
                Task { await viewModel.moveToTrash(emailIds: viewModel.selectedIds) }
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            Button("Clear") {
                viewModel.clearSelection()
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .glassEffect(.regular)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if let viewModel {
                // Filter button (shown when search is active)
                if viewModel.isSearchActive || !searchText.isEmpty {
                    Button {
                        showFilterPicker.toggle()
                    } label: {
                        Label("Filters", systemImage: viewModel.searchFilters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .help("Add search filters")

                    // Clear search button
                    Button {
                        searchText = ""
                        viewModel.clearSearch()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .help("Clear search")
                }

                Picker("View", selection: Binding(
                    get: { viewModel.displayMode },
                    set: { viewModel.displayMode = $0 }
                )) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            sortMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            if let viewModel {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    // MARK: - Keyboard Navigation

    private func handleKeyPress(_ keyPress: KeyPress, viewModel: EmailListViewModel) -> KeyPress.Result {
        switch keyPress.key {
        case .downArrow, KeyEquivalent("j"):
            viewModel.selectNextItem()
            return .handled

        case .upArrow, KeyEquivalent("k"):
            viewModel.selectPreviousItem()
            return .handled

        case KeyEquivalent("s") where !viewModel.selectedIds.isEmpty:
            Task { await viewModel.toggleStar(emailIds: viewModel.selectedIds) }
            return .handled

        case KeyEquivalent("u") where !viewModel.selectedIds.isEmpty:
            Task { await viewModel.toggleReadStatus(emailIds: viewModel.selectedIds) }
            return .handled

        case KeyEquivalent("e") where !viewModel.selectedIds.isEmpty:
            Task { await viewModel.archive(emailIds: viewModel.selectedIds) }
            return .handled

        case .delete, KeyEquivalent("#"):
            if !viewModel.selectedIds.isEmpty {
                Task { await viewModel.moveToTrash(emailIds: viewModel.selectedIds) }
            }
            return .handled

        case KeyEquivalent("a") where keyPress.modifiers.contains(.command):
            viewModel.selectAll()
            return .handled

        case .escape:
            viewModel.clearSelection()
            return .handled

        default:
            return .ignored
        }
    }
}

#Preview {
    EmailListView()
        .environment(AppState())
        .environment(DatabaseService(isStoredInMemoryOnly: true))
        .frame(width: 400, height: 600)
}
