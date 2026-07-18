import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $task.title)
                    .font(.title3)
                    .onChange(of: task.title) { touch() }
                TextField("Notes", text: $task.notes, axis: .vertical)
                    .lineLimit(3...8)
                    .onChange(of: task.notes) { touch() }
            }

            Section("Project") {
                Picker("Project", selection: projectBinding) {
                    Text("Inbox").tag(UUID?.none)
                    ForEach(allProjects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .labelsHidden()
            }

            Section("Dates") {
                Toggle("Due Date", isOn: dueToggleBinding)
                if task.dueDate != nil {
                    DatePicker("Due", selection: dueDateBinding, displayedComponents: [.date])
                        .labelsHidden()
                }
                Toggle("Defer Date", isOn: deferToggleBinding)
                if task.deferDate != nil {
                    DatePicker("Defer", selection: deferDateBinding, displayedComponents: [.date])
                        .labelsHidden()
                }
            }

            Section {
                Toggle("Flagged", isOn: $task.flagged)
                    .onChange(of: task.flagged) { touch() }
                Toggle("Completed", isOn: completedBinding)
            }

            Section("Tags") {
                TagPickerView(task: task, allTags: allTags, allTaskTags: allTaskTags)
            }

            Section {
                Button("Delete Task", role: .destructive) {
                    Mutations.deleteTask(task, in: modelContext)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(task.title.isEmpty ? "Untitled Task" : task.title)
    }

    private func touch() {
        task.updatedAt = Date()
    }

    private var projectBinding: Binding<UUID?> {
        Binding(
            get: { task.projectID },
            set: { task.projectID = $0; touch() }
        )
    }

    private var dueToggleBinding: Binding<Bool> {
        Binding(
            get: { task.dueDate != nil },
            set: { isOn in
                task.dueDate = isOn ? Date() : nil
                touch()
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { task.dueDate ?? Date() },
            set: { task.dueDate = $0; touch() }
        )
    }

    private var deferToggleBinding: Binding<Bool> {
        Binding(
            get: { task.deferDate != nil },
            set: { isOn in
                task.deferDate = isOn ? Date() : nil
                touch()
            }
        )
    }

    private var deferDateBinding: Binding<Date> {
        Binding(
            get: { task.deferDate ?? Date() },
            set: { task.deferDate = $0; touch() }
        )
    }

    private var completedBinding: Binding<Bool> {
        Binding(
            get: { task.completed },
            set: { isOn in Mutations.setCompleted(task, isOn) }
        )
    }
}
