import SwiftUI
import SwiftData

/// The iPhone quick-add sheet — adapts QuickEntryPanel's state/commit logic
/// (already AppKit-clean) into a full-screen sheet instead of a floating
/// desktop card, matching the reference screenshots' bottom quick-entry bar
/// (project/tags/due-date pills, flag toggle) presented over the keyboard.
struct QuickEntrySheet: View {
    let defaultProjectID: UUID?
    var parentTaskID: UUID? = nil

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
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Action title", text: $title)
                        .focused($isFocused)
                        .onSubmit(commit)
                    TextField("Add note", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    projectPicker
                    // Tags and Flagged hidden — this app excludes the
                    // Tags/Flagged perspectives entirely, so their fields
                    // are dropped from quick entry too. Uncomment both here
                    // and tagsPicker below to restore.
                    // tagsPicker
                    dueDateToggleRow
                    // Toggle(isOn: $flagged) {
                    //     Label("Flagged", systemImage: "flag.fill")
                    // }
                }
            }
            .navigationTitle(parentTaskID == nil ? "New Action" : "New Subaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
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

    private var projectPicker: some View {
        Picker(selection: $projectID) {
            Text("Inbox").tag(UUID?.none)
            ForEach(allProjects) { project in
                Text(project.name).tag(UUID?.some(project.id))
            }
        } label: {
            Label("Project", systemImage: "circle.grid.2x2.fill")
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

    private var dueDateToggleRow: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { dueDate != nil },
                set: { dueDate = $0 ? (dueDate ?? Date()) : nil }
            )) {
                Label("Due Date", systemImage: "calendar")
            }
            if let due = dueDate {
                DatePicker("", selection: Binding(get: { due }, set: { dueDate = $0 }), displayedComponents: [.date])
                    .labelsHidden()
            }
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
