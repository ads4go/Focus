import SwiftUI
import SwiftData

/// The iPhone Projects tab — a native List/Section replacement for
/// ProjectListView's AppKit-hacked pill rows (that view's NSTableView
/// click-catcher and hand-drawn Capsule selection exist purely to work
/// around macOS List quirks; plain SwiftUI List selection/swipe/sections
/// already do the right thing on iOS, so this is a from-scratch rewrite).
struct ProjectsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil && !$0.isCompleted }, sort: \Project.sortOrder)
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

    @State private var isAddingFolder = false
    @State private var newFolderName = ""
    /// Drives a sheet-presented ProjectEditSheet for the "+" > "Add Project"
    /// flow, matching how adding an action looks (a Form sheet with the
    /// title auto-focused) instead of a name-only alert — see the "+"
    /// button's own action for why the project is inserted immediately
    /// rather than deferred until a commit step.
    @State private var newProjectDraft: Project?
    /// Drives a sheet-presented ProjectDetailView from a row's "Edit"
    /// context menu action — mirrors ProjectTaskListScreen's identical
    /// info-button sheet, just reachable straight from this list too
    /// instead of only after already drilling into the project.
    @State private var selectedProjectForDetail: Project?
    @State private var collapsedFolderIDs: Set<UUID> = []

    var body: some View {
        list
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Real nav bar toolbar items — see InboxScreen's identical
                // conversion for why, versus the custom header row this
                // used to be.
                ToolbarItem(placement: .principal) {
                    Text("Projects")
                        .font(.headline)
                        .foregroundStyle(PerspectiveTint.projects)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add Project") {
                            let project = Project(name: "")
                            modelContext.insert(project)
                            newProjectDraft = project
                        }
                        Button("Add Folder") {
                            newFolderName = ""
                            isAddingFolder = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(PerspectiveTint.projects)
                }
            }
            .sheet(item: $newProjectDraft) { project in
                NavigationStack {
                    ProjectEditSheet(project: project, tint: PerspectiveTint.projects, isNewProject: true)
                        .navigationTitle("New Project")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(role: .cancel) {
                                    modelContext.delete(project)
                                    newProjectDraft = nil
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") { newProjectDraft = nil }
                            }
                        }
                }
            }
            .alert("New Folder", isPresented: $isAddingFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) {}
                Button("Add", action: commitNewFolder)
            }
            .sheet(item: $selectedProjectForDetail) { project in
                NavigationStack {
                    ProjectEditSheet(project: project, tint: PerspectiveTint.projects)
                        .navigationTitle("Project")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { selectedProjectForDetail = nil }
                            }
                        }
                }
            }
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
            }
        }
        .buttonStyle(RowPressHighlightStyle(tint: PerspectiveTint.projects))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Mutations.deleteProject(project, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // Moving a project between folders now happens via the Folder row
        // in ProjectEditSheet (opened by "Edit" here) instead of this
        // menu directly.
        .contextMenu {
            Button {
                selectedProjectForDetail = project
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }

    @ViewBuilder
    private func folderSection(_ folder: Folder) -> some View {
        let folderProjects = projects.filter { $0.folderID == folder.id }
        let isExpanded = !collapsedFolderIDs.contains(folder.id)
        Section {
            if isExpanded {
                ForEach(folderProjects) { project in
                    projectRow(project)
                }
                .onMove { offsets, destination in
                    Mutations.reorder(folderProjects, fromOffsets: offsets, toOffset: destination)
                }
            }
        } header: {
            // Tapping anywhere on the header collapses/expands its
            // projects — mirrors ProjectListView's identical chevron
            // toggle on macOS.
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        collapsedFolderIDs.insert(folder.id)
                    } else {
                        collapsedFolderIDs.remove(folder.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Label(folder.name, systemImage: "folder")
                }
            }
            .buttonStyle(.plain)
        }
    }
}
