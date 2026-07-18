import SwiftUI

struct TaskRowView: View {
    let task: TaskItem
    let onToggleComplete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggleComplete) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.completed ? .secondary : .primary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.completed)
                    .foregroundStyle(task.completed ? .secondary : .primary)

                if task.dueDate != nil || task.deferDate != nil {
                    HStack(spacing: 8) {
                        if let dueDate = task.dueDate {
                            Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(dueDate < Date() && !task.completed ? .red : .secondary)
                        }
                        if let deferDate = task.deferDate {
                            Label(deferDate.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
}
