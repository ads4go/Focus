import SwiftUI
import SwiftData

struct InboxScreen: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil })
    private var allTags: [Tag]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

    @State private var isShowingQuickEntry = false
    /// Drives a sheet-presented TaskDetailView instead of a NavigationLink
    /// push — matches ProjectTaskListScreen's identical choice (and
    /// ProjectDetailView's own project-detail sheet), so tapping an action
    /// item looks and behaves the same everywhere in the app.
    @State private var selectedTaskForDetail: TaskItem?

    private var tasks: [TaskItem] {
        Perspectives.tasks(for: .inbox, allTasks: allTasks, allTaskTags: allTaskTags)
    }

    var body: some View {
        list
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Real nav bar toolbar items, matching
                // ProjectTaskListScreen's title+plus arrangement, rather
                // than custom-built header content — see this app's
                // comparison of the two approaches for why they render
                // differently (native toolbar buttons get the system's own
                // automatic chrome via .tint(), custom content doesn't).
                ToolbarItem(placement: .principal) {
                    Text("Inbox")
                        .font(.headline)
                        .foregroundStyle(PerspectiveTint.inbox)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingQuickEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    // Explicit, not inherited from the environment's .tint —
                    // RootTabView changes that ambient tint the instant the
                    // selected tab changes (to recolor the tab bar icon),
                    // which is *before* the outgoing tab's content finishes
                    // animating away, so a button relying on inherited tint
                    // can flash the *destination* tab's color for a frame.
                    .tint(PerspectiveTint.inbox)
                }
            }
            .sheet(isPresented: $isShowingQuickEntry) {
                QuickEntrySheet(defaultProjectID: nil)
            }
            .sheet(item: $selectedTaskForDetail) { task in
                NavigationStack {
                    TaskEditSheet(task: task, tint: PerspectiveTint.inbox)
                        .navigationTitle("Action")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { selectedTaskForDetail = nil }
                            }
                        }
                }
            }
    }

    private var list: some View {
        List {
            ForEach(tasks) { task in
                Button {
                    selectedTaskForDetail = task
                } label: {
                    MobileTaskRow(
                        task: task,
                        tagNames: Perspectives.tags(for: task, allTags: allTags, allTaskTags: allTaskTags).map(\.name),
                        onToggleComplete: { Mutations.toggleCompleted(task, in: modelContext) }
                    )
                }
                .buttonStyle(RowPressHighlightStyle(tint: PerspectiveTint.inbox))
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
                    // Flag swipe action hidden — uncomment to restore
                    // (Flagged is an excluded perspective in this app, see
                    // RootTabView's doc comment).
                    // Button {
                    //     task.flagged.toggle()
                    //     task.updatedAt = Date()
                    // } label: {
                    //     Label("Flag", systemImage: "flag.fill")
                    // }
                    // .tint(.orange)
                }
                .listRowSeparator(.hidden)
            }
            .onMove(perform: moveTask)
        }
        .listStyle(.plain)
    }

    private func moveTask(from offsets: IndexSet, to destination: Int) {
        Mutations.reorder(tasks, fromOffsets: offsets, toOffset: destination)
    }
}
