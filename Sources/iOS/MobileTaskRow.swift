import SwiftUI

/// The iPhone app's task row — a from-scratch rewrite rather than a port of
/// TaskRowView (see project plan): that view's inline rename/selection
/// machinery is built on EditableNameText's NSTextField cursor hack, which
/// doesn't exist on iOS and isn't needed there anyway — native SwiftUI
/// TextField (in TaskDetailView, pushed on tap) already handles text editing
/// well on iOS. Visually modeled on TaskRowView's layout: checkbox, title,
/// project breadcrumb + tag chips, due-date label, flag glyph.
struct MobileTaskRow: View {
    let task: TaskItem
    var tagNames: [String] = []
    let onToggleComplete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggleComplete) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(checkboxTint)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 6) {
                    Text(task.title.isEmpty ? "Untitled Item" : task.title)
                        .font(.body)
                        .foregroundStyle(task.completed ? .secondary : .primary)
                        .strikethrough(task.completed)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let dueDate = task.dueDate {
                        Text(dueDateLabel(dueDate))
                            .font(.caption)
                            .foregroundStyle(dueDateTint(dueDate))
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }

                if !tagNames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tagNames, id: \.self) { name in
                            Text(name)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2), in: .capsule)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Flag glyph hidden — uncomment to restore (Flagged is an
            // excluded perspective in this app, see RootTabView's doc
            // comment).
            // if task.flagged {
            //     Image(systemName: "flag.fill")
            //         .foregroundStyle(.orange)
            //         .font(.caption)
            //         .padding(.top, 3)
            // }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }

    private var checkboxTint: Color {
        if task.completed { return .secondary }
        if let dueDate = task.dueDate { return dueDateTint(dueDate) }
        return .secondary
    }

    /// Matches TaskRowView's proximity-based due-date coloring/labeling
    /// (Today/Tomorrow special-cased, overdue red, today/tomorrow orange).
    private func dueDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func dueDateTint(_ dueDate: Date) -> Color {
        guard !task.completed else { return .secondary }
        let cal = Calendar.current
        if cal.isDateInToday(dueDate) { return .orange }
        if cal.isDateInTomorrow(dueDate) { return .yellow }
        if dueDate < Date() { return .red }
        return .secondary
    }
}
