import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionStore.self) private var authStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var railSelection: RailItem? = .inbox
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
            HSplitView {
                taskTier
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                detailTier
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
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
    // App-wide two-pane layout:
    // - taskTier: mode content (Projects/Review/Tags/Inbox/Forecast/Flagged)
    // - detailTier: selected list for Review/Tags and task details.

    @ViewBuilder
    private var taskTier: some View {
        switch rail {
        case .projects:
            VStack(alignment: .leading, spacing: 0) {
                Text("TEMP MARKER: TASK PANE / PROJECTS (LIVE EDIT)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue, in: Capsule())
                    .padding(8)

                if !isProjectsListCollapsed {
                    ProjectListView { id in
                        selectedProjectID = id
                        selectedTaskID = nil
                    }
                } else {
                    ContentUnavailableView("Projects Collapsed", systemImage: "sidebar.left")
                }
            }
        case .review:
            VStack(alignment: .leading, spacing: 0) {
                Text("TEMP MARKER: TASK PANE / REVIEW")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.teal, in: Capsule())
                    .padding(8)
                ReviewView { id in
                    selectedProjectID = id
                    selectedTaskID = nil
                }
            }
        case .tags:
            VStack(alignment: .leading, spacing: 0) {
                Text("TEMP MARKER: TASK PANE / TAGS")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.pink, in: Capsule())
                    .padding(8)
                TagListView { id in
                    selectedTagID = id
                    selectedTaskID = nil
                }
            }
        case .inbox:
            VStack(alignment: .leading, spacing: 0) {
                Text("TEMP MARKER: TASK PANE / INBOX")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.purple, in: Capsule())
                    .padding(8)
                TaskListView(perspective: .inbox, title: "Inbox", selectedTaskID: $selectedTaskID)
            }
        case .forecast:
            VStack(alignment: .leading, spacing: 0) {
                Text("TEMP MARKER: TASK PANE / FORECAST")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red, in: Capsule())
                    .padding(8)
                ForecastCalendarView()
            }
        case .flagged:
            VStack(alignment: .leading, spacing: 0) {
                Text("TEMP MARKER: TASK PANE / FLAGGED")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange, in: Capsule())
                    .padding(8)
                TaskListView(perspective: .flagged, title: "Flagged", selectedTaskID: $selectedTaskID)
            }
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
            Group {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TEMP MARKER: DETAIL LEFT PANE")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.gray, in: Capsule())
                        .padding(8)

                    switch rail {
                    case .projects, .review:
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
                    case .forecast:
                        ForecastView(selectedTaskID: $selectedTaskID)
                    default:
                        Color.clear
                    }
                }
            }
            .frame(minWidth: 100, maxWidth: .infinity, maxHeight: .infinity)

            Group {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TEMP MARKER: DETAIL RIGHT PANE")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black, in: Capsule())
                        .padding(8)

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
