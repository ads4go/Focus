import SwiftUI
import SwiftData

struct TaskRowView: View {
    let task: TaskItem
    let isSelected: Bool
    /// Shown as a breadcrumb below the title — only meaningful in lists that
    /// mix tasks from multiple projects (Flagged, a Tag's tasks), where the
    /// project isn't already implied by the list itself.
    var projectName: String? = nil
    var tagNames: [String] = []
    /// Full model arrays — only needed when isSelected to power the
    /// interactive project/tag/due-date controls shown inline.
    var allProjects: [Project] = []
    var allTags: [Tag] = []
    var allTaskTags: [TaskTag] = []
    let onToggleComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showingDueDatePicker = false

    private var isOverdue: Bool {
        !task.completed && (task.dueDate.map { $0 < Date() } ?? false)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggleComplete) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(checkboxTint)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                EditableNameText(
                    name: titleBinding,
                    strikethrough: task.completed,
                    foregroundColor: task.completed ? .secondary : .primary,
                    isSelected: isSelected
                )

                if isSelected {
                    interactiveMetadataRow
                } else if projectName != nil || !tagNames.isEmpty || task.dueDate != nil || task.deferDate != nil {
                    staticMetadataRow
                }

                if isSelected && !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(.top, 2)
                }
            }

            Spacer()

            if task.flagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Static metadata (unselected)

    private var staticMetadataRow: some View {
        HStack(spacing: 6) {
            if let projectName {
                Label(projectName, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !tagNames.isEmpty {
                Label(tagNames.joined(separator: ", "), systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let dueDate = task.dueDate {
                DateChip(text: dueDate.formatted(date: .abbreviated, time: .omitted),
                         systemImage: "calendar", tint: dueDateTint(dueDate))
            }
            if let deferDate = task.deferDate {
                DateChip(text: deferDate.formatted(date: .abbreviated, time: .omitted),
                         systemImage: "clock", tint: .secondary)
            }
        }
    }

    // MARK: - Interactive metadata (selected)

    private var interactiveMetadataRow: some View {
        HStack(spacing: 6) {
            projectPickerChip
            tagChips
            dueDateChip
        }
        .padding(.top, 2)
    }

    private var projectPickerChip: some View {
        let current = allProjects.first { $0.id == task.projectID }
        return Menu {
            Button("Inbox") {
                task.projectID = nil
                task.updatedAt = Date()
            }
            Divider()
            ForEach(allProjects) { project in
                Button {
                    task.projectID = project.id
                    task.updatedAt = Date()
                } label: {
                    if project.id == task.projectID {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            Label(current?.name ?? "Project", systemImage: current == nil ? "folder.badge.plus" : "folder")
                .font(.caption)
                .foregroundStyle(current == nil ? .tertiary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(current == nil ? 0.07 : 0.12), in: .capsule)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var tagChips: some View {
        let assignedIDs = Set(allTaskTags.filter { $0.taskID == task.id }.map(\.tagID))
        let assigned = allTags.filter { assignedIDs.contains($0.id) }
        let unassigned = allTags.filter { !assignedIDs.contains($0.id) }

        ForEach(assigned) { tag in
            Button {
                Mutations.removeTag(tag, from: task, in: modelContext)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 9))
                    Text(tag.name)
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.caption)
                .foregroundStyle(.pink)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.pink.opacity(0.12), in: .capsule)
            }
            .buttonStyle(.plain)
        }

        if !unassigned.isEmpty {
            Menu {
                ForEach(unassigned) { tag in
                    Button(tag.name) {
                        Mutations.addTag(tag, to: task, in: modelContext)
                    }
                }
            } label: {
                Label(assigned.isEmpty ? "Tag" : "", systemImage: assigned.isEmpty ? "tag.badge.plus" : "plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.07), in: .capsule)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var dueDateChip: some View {
        Group {
            if let due = task.dueDate {
                HStack(spacing: 3) {
                    Button {
                        showingDueDatePicker = true
                    } label: {
                        Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(dueDateTint(due))
                    }
                    .buttonStyle(.plain)
                    Button {
                        task.dueDate = nil
                        task.updatedAt = Date()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(dueDateTint(due))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(dueDateTint(due).opacity(0.15), in: .capsule)
            } else {
                Button {
                    showingDueDatePicker = true
                } label: {
                    Label("Due Date", systemImage: "calendar.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.07), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .popover(isPresented: $showingDueDatePicker) {
            dueDatePopover
        }
    }

    private var dueDatePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(
                "Due Date",
                selection: Binding(
                    get: { task.dueDate ?? Date() },
                    set: { task.dueDate = $0; task.updatedAt = Date() }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            if task.dueDate != nil {
                Button("Clear") {
                    task.dueDate = nil
                    task.updatedAt = Date()
                    showingDueDatePicker = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.callout)
            }
        }
        .padding()
        .frame(minWidth: 260)
    }

    // MARK: - Helpers

    private var titleBinding: Binding<String> {
        Binding(
            get: { task.title },
            set: { task.title = $0; task.updatedAt = Date() }
        )
    }

    private var checkboxTint: Color {
        if task.completed { return .secondary }
        return isOverdue ? .red : .secondary
    }

    /// Matches OmniFocus's proximity-based due-date coloring: overdue is
    /// red, due today/tomorrow is orange, anything further out is neutral.
    private func dueDateTint(_ dueDate: Date) -> Color {
        guard !task.completed else { return .secondary }
        let calendar = Calendar.current
        if dueDate < Date() { return .red }
        if let tomorrowEnd = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: Date())),
           dueDate < tomorrowEnd {
            return .orange
        }
        return .secondary
    }
}

/// A small rounded pill for a date label, matching OmniFocus's colored
/// due/defer chips rather than plain inline text.
private struct DateChip: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: .capsule)
    }
}
