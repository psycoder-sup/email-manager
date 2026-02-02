import SwiftUI
import os.log

/// Type alias to avoid conflict with Core/Models/Label.swift
private typealias ActionLabel = SwiftUI.Label<Text, Image>

/// Main email list view displaying emails or threads with selection and actions.
struct EmailListView: View {
    @Environment(AppState.self) private var appState
    @Environment(DatabaseService.self) private var databaseService

    @State private var viewModel: EmailListViewModel?
    @State private var searchText = ""
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
                viewModel = EmailListViewModel(databaseService: databaseService)
            }
        }
        .task(id: taskId) {
            await viewModel?.loadData(account: appState.selectedAccount, folder: appState.selectedFolder)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search emails")
        .onChange(of: searchText) { _, newValue in
            viewModel?.searchQuery = newValue
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
                Task {
                    await viewModel?.loadData(account: appState.selectedAccount, folder: appState.selectedFolder)
                }
            }
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
                    ActionLabel("Delete", systemImage: "trash")
                }

                Button {
                    Task { await viewModel.archive(emailIds: [email.gmailId]) }
                } label: {
                    ActionLabel("Archive", systemImage: "archivebox")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await viewModel.toggleReadStatus(emailIds: [email.gmailId]) }
                } label: {
                    ActionLabel(
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
            ActionLabel(email.isStarred ? "Unstar" : "Star", systemImage: email.isStarred ? "star.fill" : "star")
        }

        Button {
            Task { await viewModel.toggleReadStatus(emailIds: [email.gmailId]) }
        } label: {
            ActionLabel(
                email.isRead ? "Mark as Unread" : "Mark as Read",
                systemImage: email.isRead ? "envelope.badge" : "envelope.open"
            )
        }

        Divider()

        Button {
            Logger.ui.info("Reply tapped")
        } label: {
            ActionLabel("Reply", systemImage: "arrowshape.turn.up.left")
        }

        Button {
            Logger.ui.info("Forward tapped")
        } label: {
            ActionLabel("Forward", systemImage: "arrowshape.turn.up.right")
        }

        Divider()

        Button {
            Task { await viewModel.archive(emailIds: [email.gmailId]) }
        } label: {
            ActionLabel("Archive", systemImage: "archivebox")
        }

        Button(role: .destructive) {
            Task { await viewModel.moveToTrash(emailIds: [email.gmailId]) }
        } label: {
            ActionLabel("Move to Trash", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func threadContextMenu(thread: EmailThread) -> some View {
        Button {
            Logger.ui.info("Thread star toggle - not implemented")
        } label: {
            ActionLabel(thread.isStarred ? "Unstar" : "Star", systemImage: thread.isStarred ? "star.fill" : "star")
        }
        .disabled(true)

        Divider()

        Button {
            Logger.ui.info("Archive thread - not implemented")
        } label: {
            ActionLabel("Archive", systemImage: "archivebox")
        }
        .disabled(true)

        Button(role: .destructive) {
            Logger.ui.info("Delete thread - not implemented")
        } label: {
            ActionLabel("Move to Trash", systemImage: "trash")
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
            ActionLabel("Sort", systemImage: "arrow.up.arrow.down")
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
