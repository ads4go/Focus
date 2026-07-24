import SwiftUI
import SwiftData
import AppKit

struct ProjectListView: View {
    /// Whether this pane is the one the user most recently interacted
    /// with, as opposed to the middle pane's own task list or a rail
    /// button — plain SwiftUI @FocusState didn't track this reliably since
    /// these rows are hand-drawn (custom taps, not native List selection),
    /// so a real click on one doesn't naturally request AppKit first
    /// responder for the List the way a native row would. The caller
    /// (ContentView) owns the actual bookkeeping — true whenever this
    /// pane's own onSelectionChange just fired, false on a rail switch or a
    /// middle-pane task selection — and just hands the result back in.
    /// Drives selectedIdleFillColor going gray when this isn't the pane
    /// last interacted with, matching how a selected-but-not-first-
    /// responder NSTableView row looks gray rather than blue in AppKit.
    let isPaneFocused: Bool
    let onSelectionChange: (Set<UUID>) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.controlActiveState) private var controlActiveState
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }, sort: \Folder.sortOrder)
    private var folders: [Folder]
    /// Only needed so a task dragged from the middle pane can be looked up
    /// by id and reassigned when dropped on a project row here — see
    /// projectRow's .dropDestination.
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]

    @State private var isAddingProject = false
    @State private var isAddingFolder = false
    @State private var newProjectName = ""
    @State private var newFolderName = ""
    /// Unified selection — holds both project IDs and folder IDs. Driven
    /// entirely by hand now (see toggleSelection) rather than List's own
    /// `selection:` binding — that native selection tint can't be recolored
    /// *or* reshaped into the pill (fully rounded, semi-circle ends) this
    /// pane's rows want, matching how TaskListView's own rows already
    /// dropped native selection for the same reason. onChange expands any
    /// selected folder IDs to their contained project IDs before
    /// forwarding to onSelectionChange.
    @State private var listSelection: Set<UUID> = []
    @State private var collapsedFolderIDs: Set<UUID> = []
    @State private var dropTargetFolderID: UUID?
    /// Decoupled from selection on purpose — a first click only selects a
    /// row; renaming its name needs a second, deliberate click on the
    /// already-selected name itself (see folderHeader/projectRow), matching
    /// Finder rather than dropping straight into edit mode on selection.
    /// Shared between folders and projects since only one name can ever be
    /// mid-rename at a time. Cleared below whenever selection changes away
    /// from whatever this was pointing at.
    @State private var editingItemID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(rootItems) { item in
                    switch item {
                    case .project(let project):
                        projectRow(for: project, indent: 23)
                    case .folder(let folder):
                        folderHeader(for: folder)
                        if !collapsedFolderIDs.contains(folder.id) {
                            let folderProjects = projects.filter { $0.folderID == folder.id }
                            ForEach(folderProjects) { project in
                                projectRow(for: project, indent: 41)
                            }
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
            // .plain instead of .inset: .inset reserves its own fixed
            // horizontal margin on macOS regardless of padding, which is
            // what the old negative .padding(.trailing, -15) was fighting
            // — but that trick pushed this List's real backing NSTableView
            // frame wider than this pane's nominal bounds (neither this
            // view's own .clipped() nor ContentView's ancestor one
            // actually shrinks an embedded AppKit control's real NSView
            // frame, only its rendering), which is what silently swallowed
            // hover/drag for the ResizableDivider just to the right. .plain
            // doesn't reserve that margin in the first place, so there's
            // nothing to fight — the pill can sit close to the true right
            // edge with ordinary, non-negative padding.
            .listStyle(.plain)
            .padding(.top, 6)
            // .plain still reserves a small margin of its own on each side
            // — smaller than .inset's, but not actually zero, hence the
            // visible gap around the pill at .padding 0. Tuned by eye:
            // -4 leading, -8 trailing. Trailing lands exactly at the
            // ResizableDivider's own 8pt width, right at the edge of
            // where -15/-12 previously reached past it and broke its
            // hover/drag — worth re-checking that divider still works.
            .padding(.leading, -4)
            .padding(.trailing, -8)
            .clipped()
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
        // This VStack only reports its own natural (content-hugging)
        // height by default — ContentView's own taskTier wrapper proposes
        // the full pane height but top-aligns whatever it gets back (see
        // leftAndMiddleSection's `.frame(maxHeight: .infinity,
        // alignment: .top)`), so without this, any blank margin below a
        // short list is genuinely outside this view's own bounds and no
        // gesture attached in here could ever see a click that lands
        // there. Actually filling the proposed height is what makes that
        // margin part of *this* view instead.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Clicking anywhere in this pane that isn't an actual row (or
        // another control, like the "+" menu below) deselects everything —
        // a real click on a row/control hits that view first, well before
        // this background ever sees it (this MUST stay a .background, not
        // a plain .onTapGesture/.contentShape on the VStack itself — rows
        // use .simultaneousGesture specifically so their own tap coexists
        // with ancestors instead of being blocked by them, which means a
        // plain gesture attached directly to this VStack would *also* fire
        // on every row click, clearing the selection the row just made).
        // A real AppKit click-catcher (plain SwiftUI Color+onTapGesture
        // attempts here didn't reliably catch clicks in this empty area,
        // for reasons that didn't fully pan out under inspection) — this
        // sidesteps SwiftUI's own gesture-recognition/hit-testing entirely
        // by handling the raw mouseDown ourselves.
        .background {
            EmptyAreaClickCatcher { listSelection = [] }
        }
        .onChange(of: listSelection) { _, newIDs in
            if let editing = editingItemID, !newIDs.contains(editing) {
                editingItemID = nil
            }
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

    // MARK: - Root ordering

    /// A root-level project and a root-level folder now share one ordering
    /// (interleaved by sortOrder) rather than always showing every root
    /// project before every folder — this wraps whichever one a given slot
    /// actually is so body's own ForEach can render either kind in the
    /// same pass, in the right relative position.
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
        let rootProjects = projects.filter { $0.folderID == nil }
        return (rootProjects.map(RootItem.project) + folders.map(RootItem.folder))
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Mutations.moveOrderable's cross-type equivalent: a project and a
    /// folder can't share one Orderable siblings array (moveOrderable is
    /// generic over a single T), but they do share one numeric sortOrder
    /// scale, so this repositions whichever one draggedID actually is
    /// (looked up directly, since the caller may not know) to sit
    /// immediately before targetID in rootItems' shared order — used when
    /// a project or folder is dragged onto a *root-level* row of either
    /// kind. Nested (inside-a-folder) reordering doesn't need this since
    /// folders can't nest — projectRow's own moveOrderable call there is
    /// enough.
    private func reorderRootItem(draggedID: UUID, beforeTargetID targetID: UUID) {
        guard draggedID != targetID else { return }
        let remaining = rootItems.filter { $0.id != draggedID }
        guard let targetIndex = remaining.firstIndex(where: { $0.id == targetID }) else { return }
        let before = targetIndex > 0 ? remaining[targetIndex - 1].sortOrder : nil
        let newSortOrder = Mutations.sortOrder(after: before, before: remaining[targetIndex].sortOrder)
        if let project = projects.first(where: { $0.id == draggedID }) {
            project.sortOrder = newSortOrder
            project.updatedAt = Date()
        } else if let folder = folders.first(where: { $0.id == draggedID }) {
            folder.sortOrder = newSortOrder
            folder.updatedAt = Date()
        }
    }

    // MARK: - Selection

    /// Finder-style: a plain tap replaces the selection with just this row;
    /// ⌘-click toggles this row in/out of the existing selection instead —
    /// the hand-rolled replacement for List's native Cmd-click handling now
    /// that these rows manage `listSelection` themselves (see its own doc
    /// comment). Shift-range-select isn't replicated.
    private func toggleSelection(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.command) {
            if listSelection.contains(id) {
                listSelection.remove(id)
            } else {
                listSelection.insert(id)
            }
        } else {
            listSelection = [id]
        }
    }

    // MARK: - Row builders

    /// A selected-but-not-editing row's pill fill: OmniFocus's own blue
    /// while Focus's window is key AND this is the pane last interacted
    /// with, falling back to a neutral gray if the window is inactive
    /// (some other app is frontmost) or focus moved to the middle pane /
    /// a rail button (see isPaneFocused) — same idea as RailView's own
    /// key-vs-inactive fill split, plus the pane-focus check.
    private var selectedIdleFillColor: Color {
        controlActiveState == .key && isPaneFocused
            ? editingRowBorderColor
            : Color(red: 70 / 255, green: 70 / 255, blue: 70 / 255)
    }

    @ViewBuilder
    private func folderHeader(for folder: Folder) -> some View {
        let isExpanded = !collapsedFolderIDs.contains(folder.id)
        let isSelected = listSelection.contains(folder.id)
        let isEditingName = editingItemID == folder.id
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
                    // A little breathing room from the pill's own left
                    // curve — without it the chevron sits flush against
                    // the rounded edge.
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)

            Image(systemName: "folder")
                .foregroundStyle(Color.blue)
            // EditableNameText (not a plain Text) — matches projectRow's
            // own name field, so a folder's name can be renamed in place.
            // isSelected here drives *edit* mode specifically (isEditingName),
            // decoupled from row selection (isSelected) — a first click only
            // selects the row; renaming needs a second, deliberate click on
            // the already-selected name, matching Finder (see editingItemID).
            Group {
                let nameText = EditableNameText(
                    name: nameBinding(for: folder),
                    foregroundColor: isSelected ? .white : .primary,
                    isSelected: isEditingName
                )
                if isEditingName {
                    nameText
                } else {
                    nameText
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                if isSelected { editingItemID = folder.id }
                            }
                        )
                }
            }
            // Shifts just the text — the icon's own position is fine.
            .padding(.leading, 2)
            Spacer()
        }
        // Gives the capsule below real pill proportions instead of just
        // hugging the text tightly (see omniPill.png).
        .padding(.vertical, 3)
        // Hand-drawn pill (Capsule, fully rounded semi-circle ends) —
        // List's native selection tint can't be recolored or reshaped (see
        // this file's own listSelection doc comment), so this row draws its
        // own instead, the same way TaskRowView's selected rows already do.
        .background {
            Capsule().fill(isSelected ? (isEditingName ? editingRowFillColor : selectedIdleFillColor) : (isDropTarget ? Color.accentColor.opacity(0.15) : Color.clear))
                .overlay {
                    if isSelected && isEditingName {
                        Capsule().strokeBorder(editingRowBorderColor, lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { toggleSelection(folder.id) })
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .draggable(folder.id.uuidString)
        // Two things can land here: a project dragged onto this folder
        // (reassigned into it, same as before), or another folder row being
        // reordered/moved into this one's position (this pane's own
        // replacement for List's native onMove — see projectRow's identical
        // pattern and Mutations.moveOrderable's own doc comment).
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first, let draggedID = UUID(uuidString: uuidString) else { return false }
            if let project = projects.first(where: { $0.id == draggedID }) {
                project.folderID = folder.id
                project.updatedAt = Date()
                collapsedFolderIDs.remove(folder.id)
                return true
            }
            // Folders are always root-level (no nesting), so this always
            // uses the shared project+folder order (rootItems) rather than
            // folders-only siblings — otherwise an interleaved root
            // project neighbor would get skipped over when computing
            // where the dragged folder actually lands.
            if let draggedFolder = folders.first(where: { $0.id == draggedID }), draggedFolder.id != folder.id {
                reorderRootItem(draggedID: draggedFolder.id, beforeTargetID: folder.id)
                return true
            }
            return false
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
    private func projectRow(for project: Project, indent: CGFloat = 23) -> some View {
        let isSelected = listSelection.contains(project.id)
        let isEditingName = editingItemID == project.id
        HStack {
            if indent > 0 {
                Spacer().frame(width: indent)
            }
            Image(systemName: "circle.grid.2x2.fill")
                .foregroundStyle(Color.blue)
            // isSelected here drives *edit* mode specifically (isEditingName),
            // decoupled from row selection — see folderHeader's identical
            // pattern/comment for why.
            Group {
                let nameText = EditableNameText(
                    name: nameBinding(for: project),
                    isSelected: isEditingName
                )
                if isEditingName {
                    nameText
                } else {
                    nameText
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                if isSelected { editingItemID = project.id }
                            }
                        )
                }
            }
            // Shifts just the text — the icon's own position is fine.
            .padding(.leading, -2)
            Spacer()
            if project.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        // See folderHeader's identical padding for why this is here.
        .padding(.vertical, 3)
        // Hand-drawn pill (Capsule) instead of List's native selection tint
        // — see folderHeader's identical background for why.
        .background {
            Capsule().fill(isSelected ? (isEditingName ? editingRowFillColor : selectedIdleFillColor) : Color.clear)
                .overlay {
                    if isSelected && isEditingName {
                        Capsule().strokeBorder(editingRowBorderColor, lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { toggleSelection(project.id) })
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .draggable(project.id.uuidString)
        // Two things can land here: a task dragged from the middle pane
        // (reassigned to this project, appended at the end of its list —
        // the left-pane half of the same drag-and-drop affiliation change
        // TaskListView's own rows/section headers support), or another
        // project row being reordered/moved into this one's group (this
        // pane's own replacement for List's native onMove — see
        // Mutations.moveOrderable's doc comment).
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first, let draggedID = UUID(uuidString: uuidString) else { return false }
            if let draggedTask = allTasks.first(where: { $0.id == draggedID }) {
                if draggedTask.projectID != project.id {
                    draggedTask.projectID = project.id
                    draggedTask.updatedAt = Date()
                }
                let lastSortOrder = allTasks
                    .filter { $0.projectID == project.id && $0.id != draggedTask.id }
                    .map(\.sortOrder)
                    .max()
                draggedTask.sortOrder = Mutations.sortOrder(after: lastSortOrder, before: nil)
                return true
            }
            if let draggedProject = projects.first(where: { $0.id == draggedID }), draggedProject.id != project.id {
                if draggedProject.folderID != project.folderID {
                    draggedProject.folderID = project.folderID
                    draggedProject.updatedAt = Date()
                }
                // Root-level target: use the shared project+folder
                // ordering (rootItems) so this lands correctly relative to
                // an interleaved folder neighbor, not just other projects.
                // Nested (inside a folder) targets keep the plain
                // project-only siblings comparison, since folders can't
                // nest there anyway.
                if project.folderID == nil {
                    reorderRootItem(draggedID: draggedProject.id, beforeTargetID: project.id)
                } else {
                    let siblings = projects.filter { $0.folderID == project.folderID }
                    Mutations.moveOrderable(draggedProject, beforeTarget: project, in: siblings)
                }
                return true
            }
            // A folder dragged onto a root-level project row — reorders
            // the folder to sit next to it in rootItems' shared order.
            // Meaningless against a project nested inside a folder (no
            // shared order to slot into there), so that case no-ops.
            if let draggedFolder = folders.first(where: { $0.id == draggedID }), project.folderID == nil {
                reorderRootItem(draggedID: draggedFolder.id, beforeTargetID: project.id)
                return true
            }
            return false
        }
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

    private func nameBinding(for folder: Folder) -> Binding<String> {
        Binding(
            get: { folder.name },
            set: { folder.name = $0; folder.updatedAt = Date() }
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

/// Reaches into the List's own backing NSTableView (found by searching the
/// view hierarchy near this invisible placeholder) and adds a click
/// recognizer directly to *it* — a plain SwiftUI background sitting behind
/// the List (Color+.contentShape+.onTapGesture, or even a raw NSView with
/// its own mouseDown) never actually receives these clicks: the table view
/// fills essentially the whole pane and intercepts every click within its
/// own bounds for itself, including genuinely row-free space below the
/// last row, well before anything "behind" it in z-order terms ever sees
/// them. Attaching straight to the table view sidesteps that; checking
/// `tableView.row(at:) == -1` in the handler is how empty space is told
/// apart from an actual row click (which the recognizer still receives,
/// but harmlessly no-ops on).
private struct EmptyAreaClickCatcher: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(near: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onClick = onClick
    }

    func makeCoordinator() -> Coordinator { Coordinator(onClick: onClick) }

    @MainActor
    final class Coordinator: NSObject {
        var onClick: () -> Void
        private weak var attachedTableView: NSTableView?

        init(onClick: @escaping () -> Void) {
            self.onClick = onClick
        }

        /// Walks up from `view` one ancestor at a time, and at each level
        /// searches *down* through that ancestor's own subviews for the
        /// first NSTableView — the smallest enclosing scope that contains
        /// one wins, which should reliably be this pane's own List and not
        /// some other List elsewhere in the window (e.g. the app's middle
        /// pane has its own).
        func attach(near view: NSView) {
            guard attachedTableView == nil else { return }
            var ancestor = view.superview
            while let candidate = ancestor {
                if let tableView = Self.findTableView(in: candidate) {
                    let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
                    tableView.addGestureRecognizer(recognizer)
                    attachedTableView = tableView
                    return
                }
                ancestor = candidate.superview
            }
        }

        private static func findTableView(in view: NSView) -> NSTableView? {
            if let tableView = view as? NSTableView { return tableView }
            for subview in view.subviews {
                if let found = findTableView(in: subview) { return found }
            }
            return nil
        }

        @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let tableView = attachedTableView else { return }
            // A click on a real row reaches AppKit's normal event path (the
            // row's own hosted content), which activates the app/window as
            // a side effect for free. A click on empty space below the
            // rows is only ever seen by this gesture recognizer, which
            // sits outside that path, so activation has to be requested
            // by hand here or an inactive window just silently deselects
            // without ever coming to the front.
            if let window = tableView.window, !window.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            let point = recognizer.location(in: tableView)
            let row = tableView.row(at: point)
            if row == -1 {
                onClick()
            }
        }
    }
}
