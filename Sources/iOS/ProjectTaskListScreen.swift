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
    /// Drives a sheet-presented TaskDetailView rather than embedding a
    /// NavigationLink directly in the row — both the closure-based and
    /// value-based NavigationLink forms hang on tap here specifically (a
    /// pushed, non-root screen combined with .swipeActions rows); a sheet
    /// sidesteps that push machinery entirely, and matches
    /// isShowingProjectDetail's identical sheet below for the project
    /// itself.
    @State private var selectedTaskForDetail: TaskItem?

    private var tasks: [TaskItem] {
        Perspectives.tasks(for: .projects([project.id]), allTasks: allTasks, allTaskTags: allTaskTags)
    }

    var body: some View {
        taskList
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Tapping the title opens ProjectDetailView, replacing the
                // separate "i" info button this used to be — a custom
                // .principal item can be any tappable view, unlike a plain
                // .navigationTitle string, and sits on the same nav bar
                // line as the back button instead of in a separate header
                // row below it.
                ToolbarItem(placement: .principal) {
                    Button {
                        isShowingProjectDetail = true
                    } label: {
                        Text(project.name)
                            .font(.headline)
                            .foregroundStyle(PerspectiveTint.projects)
                            .lineLimit(1)
                    }
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
            }
        .sheet(item: $selectedTaskForDetail) { task in
            NavigationStack {
                TaskEditSheet(task: task, tint: PerspectiveTint.projects)
                    .navigationTitle("Action")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedTaskForDetail = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $isShowingQuickEntry) {
            QuickEntrySheet(defaultProjectID: project.id, tint: PerspectiveTint.projects)
        }
        .sheet(isPresented: $isShowingProjectDetail) {
            NavigationStack {
                ProjectEditSheet(project: project, tint: PerspectiveTint.projects)
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

    private var taskList: some View {
        List {
            ForEach(tasks) { task in
                // Tap sets selectedTaskForDetail, which the .sheet below
                // turns into a sheet presentation — see that property's own
                // doc comment for why this isn't a NavigationLink directly
                // on the row.
                Button {
                    selectedTaskForDetail = task
                } label: {
                    MobileTaskRow(
                        task: task,
                        tagNames: Perspectives.tags(for: task, allTags: allTags, allTaskTags: allTaskTags).map(\.name),
                        onToggleComplete: { Mutations.toggleCompleted(task, in: modelContext) }
                    )
                }
                .buttonStyle(RowPressHighlightStyle(tint: PerspectiveTint.projects))
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
                .listRowSeparator(.hidden)
            }
            .onMove(perform: moveTask)
        }
        .listStyle(.plain)
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView("No Actions", systemImage: "circle.grid.2x2")
            }
        }
    }

    private func moveTask(from offsets: IndexSet, to destination: Int) {
        Mutations.reorder(tasks, fromOffsets: offsets, toOffset: destination)
    }
}
