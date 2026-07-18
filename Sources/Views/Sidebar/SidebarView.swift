import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: Perspective?

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var projects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var tags: [Tag]

    @State private var isAddingProject = false
    @State private var isAddingTag = false
    @State private var newProjectName = ""
    @State private var newTagName = ""

    var body: some View {
        List(selection: $selection) {
            Section("Perspectives") {
                Label("Inbox", systemImage: "tray").tag(Perspective.inbox)
                Label("Today", systemImage: "calendar").tag(Perspective.today)
                Label("Flagged", systemImage: "flag").tag(Perspective.flagged)
                Label("Projects", systemImage: "folder").tag(Perspective.projects)
            }

            Section("Projects") {
                ForEach(projects) { project in
                    Label(project.name, systemImage: "folder.fill")
                        .tag(Perspective.project(project.id))
                        .contextMenu {
                            Button("Delete Project", role: .destructive) {
                                deleteProject(project)
                            }
                        }
                }
                if isAddingProject {
                    TextField("Project name", text: $newProjectName)
                        .onSubmit(commitNewProject)
                } else {
                    Button {
                        isAddingProject = true
                    } label: {
                        Label("New Project", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Tags") {
                ForEach(tags) { tag in
                    Label(tag.name, systemImage: "tag.fill")
                        .tag(Perspective.tag(tag.id))
                        .contextMenu {
                            Button("Delete Tag", role: .destructive) {
                                deleteTag(tag)
                            }
                        }
                }
                if isAddingTag {
                    TextField("Tag name", text: $newTagName)
                        .onSubmit(commitNewTag)
                } else {
                    Button {
                        isAddingTag = true
                    } label: {
                        Label("New Tag", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Focus")
    }

    private func commitNewProject() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        newProjectName = ""
        isAddingProject = false
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Project(name: trimmed))
    }

    private func commitNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        isAddingTag = false
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Tag(name: trimmed))
    }

    private func deleteProject(_ project: Project) {
        if selection == .project(project.id) { selection = .inbox }
        Mutations.deleteProject(project, in: modelContext)
    }

    private func deleteTag(_ tag: Tag) {
        if selection == .tag(tag.id) { selection = .inbox }
        Mutations.deleteTag(tag, in: modelContext)
    }
}
