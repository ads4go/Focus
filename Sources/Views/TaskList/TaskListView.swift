import SwiftUI
import SwiftData

struct TaskListView: View {
    let perspective: Perspective
    let title: String
    @Binding var selectedTaskID: UUID?

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

    private var tasks: [TaskItem] {
        Perspectives.tasks(for: perspective, allTasks: allTasks, allTaskTags: allTaskTags)
    }

    var body: some View {
        List(tasks, id: \.id, selection: $selectedTaskID) { task in
            TaskRowView(task: task) {
                Mutations.toggleCompleted(task)
            }
            .tag(task.id)
        }
        .listStyle(.inset)
        .navigationTitle(title)
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checkmark.circle")
            }
        }
    }
}
