import SwiftUI
import SwiftData

/// A compact floating card — title, an inline Project/Tags/Due metadata row,
/// and a notes field — matching OmniFocus's Quick Entry panel rather than a
/// bare title-only prompt.
struct QuickEntryPanel: View {
    let defaultProjectID: UUID?
    var parentTaskID: UUID? = nil
    var onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var projectID: UUID?
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var dueDate: Date?
    @FocusState private var isFocused: Bool

    private var headerText: String {
        parentTaskID == nil ? "New Action" : "New Subaction"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headerText)
                .font(.headline)

            TextField("Action title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(commit)

            HStack(spacing: 6) {
                projectMenu
                tagsMenu
                dueButton
                Spacer()
            }

            TextField("Add note", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            isFocused = true
            projectID = defaultProjectID
        }
    }

    private var projectMenu: some View {
        Menu {
            Button("Inbox") { projectID = nil }
            ForEach(allProjects) { project in
                Button(project.name) { projectID = project.id }
            }
        } label: {
            metadataPillLabel(
                text: allProjects.first { $0.id == projectID }?.name ?? "Project",
                systemImage: "folder"
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var tagsMenu: some View {
        Menu {
            ForEach(allTags) { tag in
                Button {
                    if selectedTagIDs.contains(tag.id) {
                        selectedTagIDs.remove(tag.id)
                    } else {
                        selectedTagIDs.insert(tag.id)
                    }
                } label: {
                    if selectedTagIDs.contains(tag.id) {
                        Label(tag.name, systemImage: "checkmark")
                    } else {
                        Text(tag.name)
                    }
                }
            }
        } label: {
            metadataPillLabel(
                text: selectedTagIDs.isEmpty ? "Tags" : "\(selectedTagIDs.count) Tag\(selectedTagIDs.count == 1 ? "" : "s")",
                systemImage: "tag"
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var dueButton: some View {
        Button {
            dueDate = dueDate == nil ? Date() : nil
        } label: {
            metadataPillLabel(
                text: dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "Due",
                systemImage: "calendar"
            )
        }
        .buttonStyle(.plain)
    }

    private func metadataPillLabel(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: .capsule)
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = TaskItem(
            title: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            projectID: projectID,
            parentTaskID: parentTaskID,
            dueDate: dueDate
        )
        modelContext.insert(task)
        for tagID in selectedTagIDs {
            modelContext.insert(TaskTag(taskID: task.id, tagID: tagID))
        }
        onDismiss()
    }
}
