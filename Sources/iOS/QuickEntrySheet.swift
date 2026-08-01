import SwiftUI
import SwiftData
import UIKit

/// The iPhone quick-add sheet — adapts QuickEntryPanel's state/commit logic
/// (already AppKit-clean) into a full-screen sheet instead of a floating
/// desktop card, matching the reference screenshots' bottom quick-entry bar
/// (project/tags/due-date pills, flag toggle) presented over the keyboard.
struct QuickEntrySheet: View {
    let defaultProjectID: UUID?
    var parentTaskID: UUID? = nil
    /// Matches whichever screen presented this sheet — the Cancel button
    /// already got this right for free (it inherits the ambient .tint()
    /// from the presenting screen's toolbar), but the calendar/project
    /// icons are hardcoded colors, not tint-derived, so they need this
    /// passed in explicitly instead.
    var tint: Color = PerspectiveTint.inbox

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var projectID: UUID?
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var dueDate: Date?
    @State private var flagged: Bool = false
    @State private var isShowingDueDateCalendar = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Action title", text: $title)
                        .focused($isFocused)
                        .onSubmit(commit)
                    dueDateRow
                    TextField("Add note", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                    projectPicker
                    // Tags and Flagged hidden — this app excludes the
                    // Tags/Flagged perspectives entirely, so their fields
                    // are dropped from quick entry too. Uncomment both here
                    // and tagsPicker below to restore.
                    // tagsPicker
                    // Toggle(isOn: $flagged) {
                    //     Label("Flagged", systemImage: "flag.fill")
                    // }
                }
            }
            // Form's default top inset leaves a noticeably large gap above
            // the section since there's no header text occupying it —
            // shrink it explicitly instead.
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle(parentTaskID == nil ? "New Action" : "New Subaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: commit)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isFocused = true
                projectID = defaultProjectID
            }
        }
    }

    // A Menu wrapping a Picker, not a plain Picker — SwiftUI's own
    // .automatic Picker style renders its trailing "current value" text
    // (e.g. "Inbox") as fixed system chrome we can't restyle directly; this
    // gets the same tap-to-select behavior (complete with checkmarks) while
    // letting us color the label and the selected value independently.
    private var projectPicker: some View {
        Menu {
            Picker("", selection: $projectID) {
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
                Text(allProjects.first { $0.id == projectID }?.name ?? "Inbox")
                    .foregroundStyle(.white)
                Spacer()
            }
        }
    }

    private var tagsPicker: some View {
        NavigationLink {
            List(allTags) { tag in
                Button {
                    if selectedTagIDs.contains(tag.id) {
                        selectedTagIDs.remove(tag.id)
                    } else {
                        selectedTagIDs.insert(tag.id)
                    }
                } label: {
                    HStack {
                        Text(tag.name)
                        Spacer()
                        if selectedTagIDs.contains(tag.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Tags")
        } label: {
            Label(
                selectedTagIDs.isEmpty ? "Tags" : "\(selectedTagIDs.count) Tag\(selectedTagIDs.count == 1 ? "" : "s")",
                systemImage: "tag"
            )
        }
    }

    // A plain Button + .popover, not an invisible DatePicker overlaid with
    // custom content — that approach (opacity ~0 DatePicker underneath a
    // hit-test-disabled label) fought the system in two ways: the row's
    // separator line stopped rendering under the leftover DatePicker
    // content, and SwiftUI's DatePicker binding never fires its set
    // closure for a tap that doesn't change the value (so tapping the day
    // already shown as "selected" — today, before you've picked anything
    // else — silently did nothing, and a .simultaneousGesture layered on
    // top of the native control couldn't reliably intercept that first
    // tap either). A normal Button sidesteps all of it: its action runs
    // unconditionally on tap, so committing today (if nothing's set yet)
    // and opening the popover happen together, synchronously, before the
    // calendar ever appears — no dependence on the picker's own change
    // detection at all.
    private var dueDateRow: some View {
        HStack {
            Button {
                // Dismisses the title field's keyboard first — with it
                // still up, there's less room below than above, so the
                // system can still flip the popover's placement despite
                // the arrowEdge hint below.
                isFocused = false
                if dueDate == nil { dueDate = Date() }
                isShowingDueDateCalendar = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.body)
                        .foregroundStyle(tint)
                    Text(dueDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Due Date")
                        // Matches TextField's own placeholder gray while
                        // unset (Color(uiColor: .placeholderText) is the
                        // exact system placeholder color, same as "Action
                        // title"/"Add note" show before you type anything),
                        // reverting to normal text color once a date is set.
                        .foregroundStyle(dueDate == nil ? Color(uiColor: .placeholderText) : Color.primary)
                }
            }
            // Without this, the button uses Form's default style, which
            // applies its own chrome tied exactly to this button's own
            // bounds — that's what was covering the row separator
            // specifically under the icon+text (the Spacer/clear-button
            // area past it, never wrapped in a Button, showed the
            // separator fine the whole time).
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            Spacer()
            if dueDate != nil {
                Button {
                    dueDate = nil
                    isShowingDueDateCalendar = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        // A leading icon shifts where Form/List starts this row's
        // separator (matching the Settings.app convention of aligning it
        // with the text, not the icon) — forcing it back to the true
        // leading edge here instead.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        // Attached to the whole row rather than just the inner Button —
        // a presentation modifier (.popover/.sheet) directly on a Form
        // row's own interactive content was suppressing that row's
        // separator line; moving it here avoids that.
        .popover(isPresented: $isShowingDueDateCalendar, arrowEdge: .top) {
            DatePicker(
                "",
                selection: Binding(get: { dueDate ?? Date() }, set: { dueDate = $0 }),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            // Without an explicit size, the popover shrinks to fit its
            // content awkwardly (squeezed against the trailing edge)
            // instead of laying out the calendar at its normal size.
            .frame(width: 320, height: 360)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = TaskItem(
            title: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            projectID: projectID,
            parentTaskID: parentTaskID,
            dueDate: dueDate,
            flagged: flagged
        )
        modelContext.insert(task)
        for tagID in selectedTagIDs {
            modelContext.insert(TaskTag(taskID: task.id, tagID: tagID))
        }
        dismiss()
    }
}
