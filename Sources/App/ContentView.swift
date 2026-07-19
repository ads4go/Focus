import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionStore.self) private var authStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var railSelection: RailItem? = .inbox
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    /// Toggled by re-tapping the already-selected Projects rail button —
    /// hides/shows the leftmost Projects-list pane within its HSplitView.
    @State private var isProjectsListCollapsed = false
    @State private var selectedProjectID: UUID?
    @State private var selectedTagID: UUID?
    @State private var selectedTaskID: UUID?
    @State private var isShowingQuickEntry = false
    @State private var pushDebounceTask: Task<Void, Never>?

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil })
    private var allTags: [Tag]

    private var rail: RailItem { railSelection ?? .inbox }

    var body: some View {
        HStack(spacing: 0) {
            RailView(selection: railSelection, onSelect: handleRailTap)
            Divider()
            NavigationSplitView(columnVisibility: $columnVisibility) {
                browseTier
            } content: {
                taskTier
            } detail: {
                detailTier
            }
        }
        .sheet(isPresented: $isShowingQuickEntry) {
            QuickEntryPanel(defaultProjectID: defaultProjectIDForQuickEntry) {
                isShowingQuickEntry = false
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingQuickEntry = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem {
                Button {
                    Task { await SyncEngine.syncNow(context: modelContext) }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            ToolbarItem {
                Button("Sign Out") {
                    Task { await authStore.signOut() }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await SyncEngine.syncNow(context: modelContext)
                try? await Task.sleep(for: .seconds(25))
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await SyncEngine.syncNow(context: modelContext) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave, object: modelContext)) { _ in
            schedulePush()
        }
    }

    /// Re-tapping the already-selected rail item is repurposed as a toggle
    /// (currently only meaningful for Projects, whose list pane it
    /// shows/hides); tapping a different item switches to it normally.
    private func handleRailTap(_ item: RailItem) {
        guard item == railSelection else {
            railSelection = item
            // Projects no longer needs its own browse column — its list is
            // now a section stacked inside the content column instead — so
            // it only needs the two-column layout, like Inbox/Forecast/Flagged.
            columnVisibility = (item == .tags || item == .review) ? .all : .doubleColumn
            selectedProjectID = nil
            selectedTagID = nil
            selectedTaskID = nil
            return
        }
        if item == .projects {
            isProjectsListCollapsed.toggle()
        }
    }

    // MARK: - Tiers
    //
    // Rail (outside the NavigationSplitView, never collapses) picks a mode.
    // For Tags/Review, browseTier lists names and taskTier shows the
    // selected one's tasks — three real columns. Projects instead folds its
    // list into taskTier as a plain section (see taskTier's .projects case),
    // and Inbox/Forecast/Flagged have no name list at all — both cases
    // collapse browseTier away (columnVisibility above) for the simpler
    // two-column layout.

    @ViewBuilder
    private var browseTier: some View {
        switch rail {
        case .tags:
            TagListView { id in
                selectedTagID = id
                selectedTaskID = nil
            }
        case .review:
            ReviewView { id in
                selectedProjectID = id
                selectedTaskID = nil
            }
        case .inbox, .forecast, .flagged, .projects:
            EmptyView()
        }
    }

    @ViewBuilder
    private var taskTier: some View {
        switch rail {
        case .projects:
            // The Projects list sits beside the selected project's tasks,
            // both in this one column — not a separate NavigationSplitView
            // sidebar column with its own collapse-toggle chrome, just a
            // plain resizable split. HSplitView gives a real draggable
            // divider without any of NavigationSplitView's "this is the
            // app's navigation sidebar" behavior.
            HSplitView {
                if !isProjectsListCollapsed {
                    ProjectListView { id in
                        selectedProjectID = id
                        selectedTaskID = nil
                    }
                    .frame(minWidth: 180, idealWidth: 260, maxWidth: 400)
                }
                projectDetailOrPlaceholder
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        case .review:
            projectDetailOrPlaceholder
        case .tags:
            if let selectedTagID {
                TaskListView(
                    perspective: .tag(selectedTagID),
                    title: allTags.first { $0.id == selectedTagID }?.name ?? "Tag",
                    selectedTaskID: $selectedTaskID
                )
            } else {
                ContentUnavailableView("Select a Tag", systemImage: "tag")
            }
        case .inbox:
            TaskListView(perspective: .inbox, title: "Inbox", selectedTaskID: $selectedTaskID)
        case .forecast:
            ForecastView(selectedTaskID: $selectedTaskID)
        case .flagged:
            TaskListView(perspective: .flagged, title: "Flagged", selectedTaskID: $selectedTaskID)
        }
    }

    @ViewBuilder
    private var projectDetailOrPlaceholder: some View {
        if let selectedProjectID {
            TaskListView(
                perspective: .project(selectedProjectID),
                title: allProjects.first { $0.id == selectedProjectID }?.name ?? "Project",
                selectedTaskID: $selectedTaskID
            )
        } else {
            ContentUnavailableView("Select a Project", systemImage: "folder")
        }
    }

    @ViewBuilder
    private var detailTier: some View {
        // HSplitView gives a real draggable divider (see taskTier's
        // .projects case for why, versus a plain HStack + Divider).
        HSplitView {
            // Left half is intentionally blank for now — just the
            // structural split; content may move here later.
            Color.clear
                .frame(minWidth: 100, maxWidth: .infinity, maxHeight: .infinity)
            Group {
                if let task = selectedTask {
                    TaskDetailView(task: task) { projectID in
                        railSelection = .projects
                        selectedProjectID = projectID
                        selectedTaskID = nil
                    }
                } else {
                    ContentUnavailableView("No Task Selected", systemImage: "checklist")
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedTask: TaskItem? {
        selectedTaskID.flatMap { id in allTasks.first { $0.id == id } }
    }

    private var defaultProjectIDForQuickEntry: UUID? {
        (rail == .projects || rail == .review) ? selectedProjectID : nil
    }

    private func schedulePush() {
        pushDebounceTask?.cancel()
        pushDebounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await SyncEngine.pushAll(context: modelContext)
        }
    }
}
