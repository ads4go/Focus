import SwiftUI
import SwiftData

/// The iPhone Projects tab — a native List/Section replacement for
/// ProjectListView's AppKit-hacked pill rows (that view's NSTableView
/// click-catcher and hand-drawn Capsule selection exist purely to work
/// around macOS List quirks; plain SwiftUI List selection/swipe/sections
/// already do the right thing on iOS, so this is a from-scratch rewrite).
struct ProjectsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }, sort: \Folder.sortOrder)
    private var folders: [Folder]

    /// A root-level project and a root-level folder share one interleaved
    /// order by sortOrder — mirrors ProjectListView.RootItem on macOS.
    private enum RootItem: Identifiable {
        case project(Project)
        case folder(Folder)

        var id: UUID {
            switch self {
            case .project(let project): return project.id
            case .folder(let folder): return folder.id
            }
        }
        var sortOrder: Int {
            switch self {
            case .project(let project): return project.sortOrder
            case .folder(let folder): return folder.sortOrder
            }
        }
    }

    private var rootItems: [RootItem] {
        // Falls back to root for a project whose folderID doesn't match
        // any currently-existing folder (an orphaned reference — e.g. the
        // folder it pointed to got soft-deleted without un-parenting this
        // particular project, a real scenario across two syncing devices)
        // rather than letting it silently vanish: previously such a
        // project matched neither this root filter (folderID != nil) nor
        // any folderSection's own filter (folderID != any real folder.id),
        // so it rendered nowhere at all despite still being a live row.
        let validFolderIDs = Set(folders.map(\.id))
        let rootProjects = projects.filter { $0.folderID == nil || !validFolderIDs.contains($0.folderID!) }
        return (rootProjects.map(RootItem.project) + folders.map(RootItem.folder))
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @State private var isAddingProject = false
    @State private var isAddingFolder = false
    @State private var newProjectName = ""
    @State private var newFolderName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            list
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("New Project", isPresented: $isAddingProject) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) {}
            Button("Add", action: commitNewProject)
        }
        .alert("New Folder", isPresented: $isAddingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Add", action: commitNewFolder)
        }
    }

    // Big colored perspective title, matching TaskListView's own header on
    // macOS — title and "+" menu share one line, instead of the "+" sitting
    // alone in the native toolbar above a separate title further down.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Projects")
                .font(.largeTitle.bold())
                .foregroundStyle(PerspectiveTint.projects)
            Spacer()
            // Toggles the ambient \.editMode List reads for the .onMove
            // handlers below — same reasoning as InboxScreen's own EditButton.
            EditButton()
                .foregroundStyle(PerspectiveTint.projects)
            Menu {
                Button("Add Project") {
                    newProjectName = ""
                    isAddingProject = true
                }
                Button("Add Folder") {
                    newFolderName = ""
                    isAddingFolder = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    // Explicit, not inherited — see InboxScreen's header for why.
                    .foregroundStyle(PerspectiveTint.projects)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var list: some View {
        List {
            ForEach(rootItems) { item in
                switch item {
                case .project(let project):
                    projectRow(project)
                case .folder(let folder):
                    folderSection(folder)
                }
            }
            .onMove(perform: moveRootItem)
        }
        .overlay {
            if projects.isEmpty && folders.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "square.grid.2x2")
            }
        }
    }

    /// Root-level reorder — folders and projects share one interleaved
    /// sortOrder scale (see rootItems), so this can't use the generic
    /// Mutations.reorder<T: Orderable> (that needs one homogeneous array);
    /// mirrors ProjectListView's own reorderRootItem on macOS instead.
    private func moveRootItem(from offsets: IndexSet, to destination: Int) {
        guard let sourceIndex = offsets.first else { return }
        var reordered = rootItems
        let dragged = reordered[sourceIndex]
        reordered.move(fromOffsets: offsets, toOffset: destination)
        guard let newIndex = reordered.firstIndex(where: { $0.id == dragged.id }) else { return }
        let before = newIndex > 0 ? reordered[newIndex - 1].sortOrder : nil
        let after = newIndex < reordered.count - 1 ? reordered[newIndex + 1].sortOrder : nil
        let newSortOrder = Mutations.sortOrder(after: before, before: after)
        switch dragged {
        case .project(let project):
            project.sortOrder = newSortOrder
            project.updatedAt = Date()
        case .folder(let folder):
            folder.sortOrder = newSortOrder
            folder.updatedAt = Date()
        }
    }

    private func commitNewProject() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Project(name: trimmed))
    }

    private func commitNewFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Folder(name: trimmed))
    }

    private func projectRow(_ project: Project) -> some View {
        NavigationLink {
            ProjectTaskListScreen(project: project)
        } label: {
            HStack {
                Image(systemName: "circle.grid.2x2.fill")
                    .foregroundStyle(.blue)
                Text(project.name)
                Spacer()
                if project.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Mutations.deleteProject(project, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // Long-press menu, not drag-and-drop — moving a project into/out of
        // a folder is a re-filing action, not a reorder, and this app's one
        // prior attempt at custom drag gestures in this exact screen hung
        // on iOS (see ProjectTaskListScreen history); a menu sidesteps that
        // entirely. Mirrors ProjectListView's identical contextMenu on
        // macOS (there triggered by right-click instead of long-press).
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
        }
    }

    @ViewBuilder
    private func folderSection(_ folder: Folder) -> some View {
        let folderProjects = projects.filter { $0.folderID == folder.id }
        Section {
            ForEach(folderProjects) { project in
                projectRow(project)
            }
            .onMove { offsets, destination in
                Mutations.reorder(folderProjects, fromOffsets: offsets, toOffset: destination)
            }
        } header: {
            Label(folder.name, systemImage: "folder")
        }
    }
}
