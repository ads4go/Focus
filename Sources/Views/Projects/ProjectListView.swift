import SwiftUI
import SwiftData

struct ProjectListView: View {
    let onSelectionChange: (Set<UUID>) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }, sort: \Folder.sortOrder)
    private var folders: [Folder]

    @State private var isAddingProject = false
    @State private var isAddingFolder = false
    @State private var newProjectName = ""
    @State private var newFolderName = ""
    /// Unified selection — holds both project IDs and folder IDs.
    /// The List renders highlights for all of them natively so adjacent
    /// selected rows (project or folder) blend into one continuous shape.
    /// onChange expands any folder IDs to their contained project IDs before
    /// forwarding to onSelectionChange.
    @State private var listSelection: Set<UUID> = []
    @State private var collapsedFolderIDs: Set<UUID> = []
    @State private var dropTargetFolderID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $listSelection) {
                let rootProjects = projects.filter { $0.folderID == nil }
                ForEach(rootProjects) { project in
                    projectRow(for: project, indent: 18)
                }
                .onMove { offsets, dest in
                    Mutations.reorder(rootProjects, fromOffsets: offsets, toOffset: dest)
                }

                ForEach(folders) { folder in
                    folderHeader(for: folder)
                    if !collapsedFolderIDs.contains(folder.id) {
                        let folderProjects = projects.filter { $0.folderID == folder.id }
                        ForEach(folderProjects) { project in
                            projectRow(for: project, indent: 36)
                        }
                        .onMove { offsets, dest in
                            Mutations.reorder(folderProjects, fromOffsets: offsets, toOffset: dest)
                        }
                    }
                }

                if isAddingProject {
                    TextField("Project name", text: $newProjectName)
                        .onSubmit(commitNewProject)
                        .listRowSeparator(.hidden)
                }
                if isAddingFolder {
                    TextField("Folder name", text: $newFolderName)
                        .onSubmit(commitNewFolder)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .padding(.top, 12)
            .padding(.leading, -6)
            .padding(.trailing, -10)
            .overlay {
                if projects.isEmpty && folders.isEmpty && !isAddingProject && !isAddingFolder {
                    ContentUnavailableView("No Projects", systemImage: "square.grid.2x2")
                }
            }

            HStack {
                Menu {
                    Button("Add Project") { isAddingProject = true }
                    Button("Add Folder") { isAddingFolder = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .onChange(of: listSelection) { _, newIDs in
            // Expand any selected folder IDs to their contained project IDs,
            // then union with directly-selected project IDs.
            let folderIDs = newIDs.filter { id in folders.contains { $0.id == id } }
            let directProjectIDs = newIDs.filter { id in projects.contains { $0.id == id } }
            let folderProjectIDs = Set(
                projects
                    .filter { $0.folderID.map { folderIDs.contains($0) } ?? false }
                    .map { $0.id }
            )
            onSelectionChange(directProjectIDs.union(folderProjectIDs))
        }
    }

    // MARK: - Row builders

    @ViewBuilder
    private func folderHeader(for folder: Folder) -> some View {
        let isExpanded = !collapsedFolderIDs.contains(folder.id)
        let isSelected = listSelection.contains(folder.id)
        let isDropTarget = dropTargetFolderID == folder.id
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded { collapsedFolderIDs.insert(folder.id) }
                    else { collapsedFolderIDs.remove(folder.id) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.gray))
                    .frame(width: 14)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .buttonStyle(.plain)

            Image(systemName: "folder")
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.blue))
            Text(folder.name)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary))
            Spacer()
        }
        // Tag makes the List own this row's selection highlight — same
        // rendering as project rows, so adjacent selections blend together.
        .tag(folder.id)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .background(isDropTarget ? Color.accentColor.opacity(0.15) : Color.clear)
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let projectID = UUID(uuidString: uuidString),
                  let project = projects.first(where: { $0.id == projectID }) else { return false }
            project.folderID = folder.id
            project.updatedAt = Date()
            collapsedFolderIDs.remove(folder.id)
            return true
        } isTargeted: { targeted in
            dropTargetFolderID = targeted ? folder.id : nil
        }
        .listRowSeparator(.hidden)
        .contextMenu {
            Button("Delete Folder", role: .destructive) {
                Mutations.deleteFolder(folder, in: modelContext)
            }
        }
    }

    @ViewBuilder
    private func projectRow(for project: Project, indent: CGFloat = 18) -> some View {
        HStack {
            if indent > 0 {
                Spacer().frame(width: indent)
            }
            Image(systemName: "circle.grid.3x3.fill")
                .foregroundStyle(.blue)
            EditableNameText(
                name: nameBinding(for: project),
                isSelected: listSelection.contains(project.id)
            )
            Spacer()
            if project.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .tag(project.id)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .draggable(project.id.uuidString)
        .contextMenu {
            Menu("Move to Folder") {
                Button("No Folder") {
                    project.folderID = nil
                    project.updatedAt = Date()
                }
                ForEach(folders) { folder in
                    Button(folder.name) {
                        project.folderID = folder.id
                        project.updatedAt = Date()
                    }
                }
            }
            Menu("Review Interval") {
                Button("Daily") { setReviewInterval(project, 1) }
                Button("Weekly") { setReviewInterval(project, 7) }
                Button("Monthly") { setReviewInterval(project, 30) }
                Button("Never") { setReviewInterval(project, nil) }
            }
            Divider()
            Button("Delete Project", role: .destructive) {
                Mutations.deleteProject(project, in: modelContext)
            }
        }
        .listRowSeparator(.hidden)
    }

    // MARK: - Helpers

    private func nameBinding(for project: Project) -> Binding<String> {
        Binding(
            get: { project.name },
            set: { project.name = $0; project.updatedAt = Date() }
        )
    }

    private func setReviewInterval(_ project: Project, _ days: Int?) {
        project.reviewIntervalDays = days
        project.updatedAt = Date()
    }

    private func commitNewProject() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        newProjectName = ""
        isAddingProject = false
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Project(name: trimmed))
    }

    private func commitNewFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        isAddingFolder = false
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Folder(name: trimmed))
    }
}
