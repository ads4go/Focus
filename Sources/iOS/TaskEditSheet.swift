import SwiftUI
import SwiftData
import UIKit

/// The iPhone's action-item detail sheet, styled like QuickEntrySheet's
/// single-container Form (same icons/colors/tap-to-open-calendar pattern)
/// but bound to an existing task instead of creating a new one.
/// Sources/Views/Detail/TaskDetailView.swift is left untouched — it's
/// shared with the Mac app, so restyling it here would also change the
/// Mac detail pane; this is a separate, iOS-only presentation used from
/// InboxScreen and ProjectTaskListScreen instead.
struct TaskEditSheet: View {
    @Bindable var task: TaskItem
    /// Matches whichever screen presents this sheet — see QuickEntrySheet's
    /// identical parameter for why this can't just read the ambient .tint().
    var tint: Color = PerspectiveTint.inbox

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]

    @State private var isShowingDueDateCalendar = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Action title", text: $task.title)
                    .focused($isTitleFocused)
                    .onChange(of: task.title) { touch() }
                dueDateRow
                TextField("Add note", text: $task.notes, axis: .vertical)
                    .lineLimit(1...4)
                    .onChange(of: task.notes) { touch() }
                projectPicker
                statusRow
            }
        }
        // Matches QuickEntrySheet's identical top-margin fix.
        .contentMargins(.top, 0, for: .scrollContent)
    }

    private var statusRow: some View {
        HStack(spacing: 4) {
            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(tint)
            Button(task.completed ? "Complete" : "Active") {
                Mutations.toggleCompleted(task, in: modelContext)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            Spacer()
        }
    }

    // Identical pattern to QuickEntrySheet's dueDateRow — a plain Button
    // (not a native DatePicker directly) opening a .popover with a real,
    // visible graphical DatePicker; see that view's own doc comments for
    // why (separator suppression, tap-on-already-selected-day not firing).
    private var dueDateRow: some View {
        HStack {
            Button {
                isTitleFocused = false
                if task.dueDate == nil {
                    task.dueDate = Date()
                    touch()
                }
                isShowingDueDateCalendar = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.body)
                        .foregroundStyle(tint)
                    Text(task.dueDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Due Date")
                        .foregroundStyle(task.dueDate == nil ? Color(uiColor: .placeholderText) : Color.primary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            Spacer()
            if task.dueDate != nil {
                Button {
                    task.dueDate = nil
                    touch()
                    isShowingDueDateCalendar = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .popover(isPresented: $isShowingDueDateCalendar, arrowEdge: .top) {
            DatePicker(
                "",
                selection: Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0; touch() }),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            .frame(width: 320, height: 360)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var projectPicker: some View {
        Menu {
            Picker("", selection: Binding(get: { task.projectID }, set: { task.projectID = $0; touch() })) {
                Text("Inbox").tag(UUID?.none)
                ForEach(allProjects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.body)
                    .foregroundStyle(tint)
                Text(allProjects.first { $0.id == task.projectID }?.name ?? "Inbox")
                    .foregroundStyle(.white)
                Spacer()
            }
        }
    }

    private func touch() { task.updatedAt = Date() }
}
