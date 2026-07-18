import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionStore.self) private var authStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Perspective? = .inbox
    @State private var selectedTaskID: UUID?
    @State private var isShowingQuickEntry = false
    @State private var pushDebounceTask: Task<Void, Never>?

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil })
    private var allTags: [Tag]

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } content: {
            Group {
                switch selection {
                case .none:
                    ContentUnavailableView("Select a Perspective", systemImage: "sidebar.left")
                case .some(.projects):
                    ProjectListView { projectID in
                        selection = .project(projectID)
                    }
                case .some(let perspective):
                    TaskListView(
                        perspective: perspective,
                        title: title(for: perspective),
                        selectedTaskID: $selectedTaskID
                    )
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
            }
        } detail: {
            if let task = selectedTaskID.flatMap({ id in allTasks.first { $0.id == id } }) {
                TaskDetailView(task: task)
            } else {
                ContentUnavailableView("No Task Selected", systemImage: "checklist")
            }
        }
        .onChange(of: selection) {
            selectedTaskID = nil
        }
        .sheet(isPresented: $isShowingQuickEntry) {
            QuickEntryPanel(defaultProjectID: defaultProjectIDForQuickEntry) {
                isShowingQuickEntry = false
            }
        }
        .toolbar {
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

    private func schedulePush() {
        pushDebounceTask?.cancel()
        pushDebounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await SyncEngine.pushAll(context: modelContext)
        }
    }

    private var defaultProjectIDForQuickEntry: UUID? {
        if case .project(let id) = selection { return id }
        return nil
    }

    private func title(for perspective: Perspective) -> String {
        switch perspective {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .flagged: return "Flagged"
        case .projects: return "Projects"
        case .project(let id):
            return allProjects.first { $0.id == id }?.name ?? "Project"
        case .tag(let id):
            return allTags.first { $0.id == id }?.name ?? "Tag"
        }
    }
}
