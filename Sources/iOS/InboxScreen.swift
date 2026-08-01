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

    private var tasks: [TaskItem] {
        Perspectives.tasks(for: .inbox, allTasks: allTasks, allTaskTags: allTaskTags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            list
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingQuickEntry) {
            QuickEntrySheet(defaultProjectID: nil)
        }
    }

    // Big colored perspective title, matching TaskListView's own header on
    // macOS (Text(title).font(.largeTitle.bold()).foregroundStyle(accentColor),
    // "+" button on the same line) instead of a separate native toolbar
    // button floating above it — the native nav bar is hidden entirely so
    // this row sits right at the top, same as Forecast's own header.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Inbox")
                .font(.largeTitle.bold())
                .foregroundStyle(PerspectiveTint.inbox)
            Spacer()
            // Toggles the ambient \.editMode that List reads to show
            // reorder handles for the .onMove below — inline here rather
            // than in a .toolbar so it stays on the title's own line, same
            // reasoning as the "+" button next to it.
            EditButton()
                .foregroundStyle(PerspectiveTint.inbox)
            Button {
                isShowingQuickEntry = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    // Explicit, not inherited from the environment's .tint —
                    // RootTabView changes that ambient tint the instant the
                    // selected tab changes (to recolor the tab bar icon),
                    // which is *before* the outgoing tab's content finishes
                    // animating away, so a button relying on inherited tint
                    // can flash the *destination* tab's color for a frame.
                    .foregroundStyle(PerspectiveTint.inbox)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var list: some View {
        List {
            ForEach(tasks) { task in
                NavigationLink {
                    TaskDetailView(task: task)
                } label: {
                    MobileTaskRow(
                        task: task,
                        tagNames: Perspectives.tags(for: task, allTags: allTags, allTaskTags: allTaskTags).map(\.name),
                        onToggleComplete: { Mutations.toggleCompleted(task, in: modelContext) }
                    )
                }
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
                    Button {
                        task.flagged.toggle()
                        task.updatedAt = Date()
                    } label: {
                        Label("Flag", systemImage: "flag.fill")
                    }
                    .tint(.orange)
                }
            }
            .onMove(perform: moveTask)
        }
        .listStyle(.plain)
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView("No Inbox Items", systemImage: "tray")
            }
        }
    }

    private func moveTask(from offsets: IndexSet, to destination: Int) {
        Mutations.reorder(tasks, fromOffsets: offsets, toOffset: destination)
    }
}
