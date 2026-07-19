import SwiftUI

struct TaskRowView: View {
    let task: TaskItem
    let isSelected: Bool
    /// Shown as a breadcrumb below the title — only meaningful in lists that
    /// mix tasks from multiple projects (Flagged, a Tag's tasks), where the
    /// project isn't already implied by the list itself.
    var projectName: String? = nil
    let onToggleComplete: () -> Void

    private var isOverdue: Bool {
        !task.completed && (task.dueDate.map { $0 < Date() } ?? false)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggleComplete) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checkboxTint)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.completed)
                    .foregroundStyle(task.completed ? .secondary : .primary)

                if let projectName {
                    Label(projectName, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if task.dueDate != nil || task.deferDate != nil {
                    HStack(spacing: 6) {
                        if let dueDate = task.dueDate {
                            DateChip(
                                text: dueDate.formatted(date: .abbreviated, time: .omitted),
                                systemImage: "calendar",
                                tint: dueDateTint(dueDate)
                            )
                        }
                        if let deferDate = task.deferDate {
                            DateChip(
                                text: deferDate.formatted(date: .abbreviated, time: .omitted),
                                systemImage: "clock",
                                tint: .secondary
                            )
                        }
                    }
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

    private var checkboxTint: Color {
        if task.completed { return .secondary }
        return isOverdue ? .red : .primary
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
