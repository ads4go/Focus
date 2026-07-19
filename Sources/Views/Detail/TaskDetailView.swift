import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    var onJumpToProject: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Title", text: $task.title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .onChange(of: task.title) { touch() }

                statusSection
                projectSection
                tagsSection
                OptionalDateField(label: "Defer", date: deferDateOptionalBinding, touch: touch)
                OptionalDateField(label: "Due", date: dueDateOptionalBinding, touch: touch)
                notesSection

                HStack {
                    Spacer()
                    Menu {
                        Button("Delete Task", role: .destructive) {
                            Mutations.deleteTask(task, in: modelContext)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        // Deliberately no .navigationTitle — see TaskListView's comment: it
        // would show as a redundant plain-text title above the task's own
        // title field, which already serves that purpose.
    }

    // MARK: - Sections

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Status").font(.headline)
                Spacer()
                Text(task.completed ? "Completed" : "Active")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Picker("", selection: completedBinding) {
                    Image(systemName: "play.fill").tag(false)
                    Image(systemName: "checkmark").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 160)

                Button {
                    task.flagged.toggle()
                    touch()
                } label: {
                    Image(systemName: task.flagged ? "flag.fill" : "flag")
                }
                .buttonStyle(.bordered)
                .tint(task.flagged ? .orange : .secondary)
            }
        }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project").font(.headline)
            HStack {
                Picker("", selection: projectBinding) {
                    Text("Inbox").tag(UUID?.none)
                    ForEach(allProjects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .labelsHidden()

                if let projectID = task.projectID {
                    Button {
                        onJumpToProject(projectID)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.headline)
            TagPickerView(task: task, allTags: allTags, allTaskTags: allTaskTags)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(.headline)
            TextField("Add notes…", text: $task.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...8)
                .onChange(of: task.notes) { touch() }
        }
    }

    // MARK: - Bindings

    private func touch() {
        task.updatedAt = Date()
    }

    private var projectBinding: Binding<UUID?> {
        Binding(
            get: { task.projectID },
            set: { task.projectID = $0; touch() }
        )
    }

    private var deferDateOptionalBinding: Binding<Date?> {
        Binding(
            get: { task.deferDate },
            set: { task.deferDate = $0; touch() }
        )
    }

    private var dueDateOptionalBinding: Binding<Date?> {
        Binding(
            get: { task.dueDate },
            set: { task.dueDate = $0; touch() }
        )
    }

    private var completedBinding: Binding<Bool> {
        Binding(
            get: { task.completed },
            set: { isOn in Mutations.setCompleted(task, isOn, in: modelContext) }
        )
    }
}

/// A date field styled after OmniFocus's Defer/Due rows: the current value
/// (or "None"), a tap target that opens a picker, and a quick-set chip row
/// (today / +1d / +1w / +1m / clear) below it.
private struct OptionalDateField: View {
    let label: String
    @Binding var date: Date?
    let touch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.headline)

            if let date {
                DatePicker(
                    "",
                    selection: Binding(get: { date }, set: { self.date = $0; touch() }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
            } else {
                Button {
                    date = Date()
                    touch()
                } label: {
                    HStack {
                        Text("None").foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "calendar").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                QuickDateChip(systemImage: "sun.max") { date = Date(); touch() }
                QuickDateChip(text: "+1d") { addDays(1) }
                QuickDateChip(text: "+1w") { addDays(7) }
                QuickDateChip(text: "+1m") { addMonths(1) }
                Spacer()
                if date != nil {
                    Button {
                        date = nil
                        touch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addDays(_ n: Int) {
        let base = date ?? Date()
        date = Calendar.current.date(byAdding: .day, value: n, to: base)
        touch()
    }

    private func addMonths(_ n: Int) {
        let base = date ?? Date()
        date = Calendar.current.date(byAdding: .month, value: n, to: base)
        touch()
    }
}

private struct QuickDateChip: View {
    var text: String? = nil
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let text {
                    Text(text)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
