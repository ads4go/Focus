import SwiftUI
import SwiftData

/// A single project's task list, pushed from ProjectsScreen — mirrors the
/// macOS middle pane's .projects([id]) perspective, plus a sheet-presented
/// ProjectDetailView (reused as-is) for editing the project itself.
struct ProjectTaskListScreen: View {
    // Plain, not @Bindable — nothing here ever does $project.something (its
    // fields are only ever read, and ProjectDetailView wraps its own
    // @Bindable internally), so there's no reason for this screen to also
    // hold live SwiftData observation on it. Pushing forward into
    // TaskDetailView (which *does* need @Bindable for its own task) while
    // this screen's own @Bindable was also alive across two stacked
    // navigation levels is the most likely source of the freeze reported
    // when opening an action from a project (vs. directly from the Inbox/
    // Forecast tab roots, where only one @Bindable model is ever alive).
    let project: Project

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil })
    private var allTags: [Tag]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

    @State private var isShowingQuickEntry = false
    @State private var isShowingProjectDetail = false
    /// Drives TaskDetailView via .navigationDestination(item:) below rather
    /// than embedding a NavigationLink directly in the row — both the
    /// closure-based and value-based NavigationLink forms hang on tap here
    /// specifically (a pushed, non-root screen combined with .swipeActions
    /// rows); keeping the row itself a plain Button (already proven not to
    /// hang, via the sheet this replaces) and triggering the push from a
    /// separate modifier avoids whatever gesture-recognition conflict
    /// NavigationLink-in-row hit.
    @State private var selectedTaskForDetail: TaskItem?

    private var tasks: [TaskItem] {
        Perspectives.tasks(for: .projects([project.id]), allTasks: allTasks, allTaskTags: allTaskTags)
    }

    var body: some View {
        List {
            ForEach(tasks) { task in
                // Tap sets selectedTaskForDetail, which
                // .navigationDestination(item:) below turns into a push —
                // see that property's own doc comment for why this isn't a
                // NavigationLink directly on the row.
                Button {
                    selectedTaskForDetail = task
                } label: {
                    MobileTaskRow(
                        task: task,
                        tagNames: Perspectives.tags(for: task, allTags: allTags, allTaskTags: allTaskTags).map(\.name),
                        onToggleComplete: { Mutations.toggleCompleted(task, in: modelContext) }
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button {
                        Mutations.toggleCompleted(task, in: modelContext)
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle.fill")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Mutations.deleteTask(task, in: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove(perform: moveTask)
        }
        .listStyle(.plain)
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView("No Actions", systemImage: "circle.grid.2x2")
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
                    .tint(PerspectiveTint.projects)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingQuickEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                // Explicit, not inherited — see InboxScreen's header for why.
                .tint(PerspectiveTint.projects)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingProjectDetail = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .tint(PerspectiveTint.projects)
            }
        }
        .navigationDestination(item: $selectedTaskForDetail) { task in
            TaskDetailView(task: task)
                .navigationTitle("Action")
                .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $isShowingQuickEntry) {
            QuickEntrySheet(defaultProjectID: project.id)
        }
        .sheet(isPresented: $isShowingProjectDetail) {
            NavigationStack {
                ProjectDetailView(project: project)
                    .navigationTitle("Project")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingProjectDetail = false }
                        }
                    }
            }
        }
    }

    private func moveTask(from offsets: IndexSet, to destination: Int) {
        Mutations.reorder(tasks, fromOffsets: offsets, toOffset: destination)
    }
}
