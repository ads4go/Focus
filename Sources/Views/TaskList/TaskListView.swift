import SwiftUI
import SwiftData

/// Chevron frame width (14) + the HStack spacing to the label (10) in
/// SectionHeaderRow below — exposed so callers can indent their section's
/// content to line up with where the label's own text starts.
let sectionHeaderLabelIndent: CGFloat = 24

/// A collapsible section header row — gray chevron + label — used for this
/// app's "dropdown" sections (Projects grouping here, Forecast's date
/// sections). Deliberately NOT a real DisclosureGroup: giving a
/// DisclosureGroup a custom DisclosureGroupStyle inside a List collapses
/// its nested content into a single selectable row on macOS instead of
/// List's normal per-row selection (each action lost its own selection
/// highlight, selecting the whole project's worth of rows at once) — so
/// the caller manages expand/collapse itself with a plain `if`, and this
/// is just the header row above that.
struct SectionHeaderRow<Label: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.gray)
                    .frame(width: 14)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .buttonStyle(.plain)

            label()
        }
    }
}

/// Plain text that turns into an inline-editable TextField when clicked —
/// used for project and action names across the list panes. A real Button
/// (not a bare tap gesture) wraps the display state, matching how the
/// checkbox/flag buttons elsewhere in these rows already reliably take
/// priority over List's own row-selection click.
struct EditableNameText: View {
    @Binding var name: String
    var font: Font = .body
    var strikethrough: Bool = false
    var foregroundColor: Color = .primary
    /// When true the field is shown as an editable TextField immediately.
    var isSelected: Bool = false

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isSelected {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .focused($isFocused)
                .onAppear { draft = name }
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .onChange(of: isSelected) { _, selected in
                    if selected { isFocused = true }
                }
        } else {
            Text(name)
                .font(font)
                .strikethrough(strikethrough)
                .foregroundStyle(foregroundColor)
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { name = trimmed }
    }
}

struct TaskListView: View {
    let perspective: Perspective
    let title: String
    @Binding var selectedTaskID: UUID?
    var accentColorOverride: Color? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]

    @State private var subtaskParent: TaskItem?
    @State private var isAddingInboxTask = false
    /// Collapsed-state per project, keyed by Project.id — absent means
    /// expanded (mirrors ForecastView's collapsedSectionIDs).
    @State private var collapsedProjectIDs: Set<UUID> = []
    /// Collapsed-state per tag, keyed by Tag.id — same shape as
    /// collapsedProjectIDs, for the .tags perspective's tag sections.
    @State private var collapsedTagIDs: Set<UUID> = []

    private var nodes: [TaskNode] {
        Perspectives.taskTree(for: perspective, allTasks: allTasks, allTaskTags: allTaskTags)
    }

    /// A dropdown section for one project, used only by the .projects
    /// perspective — each project gets its own DisclosureGroup with its
    /// actions nested underneath, rather than the header naming a single
    /// selected project (see ContentView.projectsDetailTitle).
    private struct ProjectSection: Identifiable {
        let id: UUID
        let project: Project
        let nodes: [TaskNode]
    }

    private var projectSections: [ProjectSection] {
        let grouped = Dictionary(grouping: nodes) { $0.task.projectID }
        return allProjects.compactMap { project in
            guard let groupNodes = grouped[project.id], !groupNodes.isEmpty else { return nil }
            return ProjectSection(id: project.id, project: project, nodes: groupNodes)
        }
    }

    private func nameBinding(for project: Project) -> Binding<String> {
        Binding(
            get: { project.name },
            set: { project.name = $0; project.updatedAt = Date() }
        )
    }

    private func isProjectExpandedBinding(for projectID: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsedProjectIDs.contains(projectID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedProjectIDs.remove(projectID)
                } else {
                    collapsedProjectIDs.insert(projectID)
                }
            }
        )
    }

    /// A dropdown section for one tag, used only by the .tags perspective.
    /// Unlike projects (one per task), a task can carry several tags, so a
    /// task can legitimately appear under more than one tag's section here
    /// — matching OmniFocus's own Tags perspective, which does the same.
    private struct TagSection: Identifiable {
        let id: UUID
        let tag: Tag
        let nodes: [TaskNode]
    }

    private var tagSections: [TagSection] {
        guard case .tags(let selectedTagIDs) = perspective else { return [] }
        return allTags.compactMap { tag in
            guard selectedTagIDs.isEmpty || selectedTagIDs.contains(tag.id) else { return nil }
            let groupNodes = nodes.filter { node in
                allTaskTags.contains { $0.taskID == node.task.id && $0.tagID == tag.id }
            }
            guard !groupNodes.isEmpty else { return nil }
            return TagSection(id: tag.id, tag: tag, nodes: groupNodes)
        }
    }

    private func isTagExpandedBinding(for tagID: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsedTagIDs.contains(tagID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedTagIDs.remove(tagID)
                } else {
                    collapsedTagIDs.insert(tagID)
                }
            }
        )
    }

    /// True for the .flagged perspective specifically — it stays a flat
    /// list (unlike Projects/Tags, flagged items aren't grouped by
    /// anything), but its rows still indent to the same depth a dropdown
    /// section's rows would, for visual consistency with the other tabs.
    private var isFlaggedPerspective: Bool {
        if case .flagged = perspective { return true }
        return false
    }

    /// Mirrors RailItem.tint so a perspective's task list carries the same
    /// accent color as its rail entry (Project/Tag detail lists use the
    /// rail color for the whole category rather than a per-item color).
    private var accentColor: Color {
        if let accentColorOverride { return accentColorOverride }
        switch perspective {
        case .inbox: return .purple
        case .flagged: return .orange
        case .projects: return .blue
        case .tags: return .pink
        }
    }

    /// A project breadcrumb only makes sense where tasks from multiple
    /// projects are mixed together with no other indication which is
    /// which — Inbox tasks have no project by definition, and .projects
    /// groups its rows under a per-project dropdown header instead (see
    /// projectSections), so a breadcrumb on each row would be redundant.
    private var showsProjectBreadcrumb: Bool {
        switch perspective {
        case .flagged, .tags: return true
        case .inbox, .projects: return false
        }
    }

    private var itemCountLabel: String {
        let count = nodes.count
        let noun: String
        switch perspective {
        case .inbox: noun = "inbox item"
        case .flagged: noun = "action"
        case .projects: noun = "action"
        case .tags: noun = "action"
        }
        let actionsText = "\(count) \(noun)\(count == 1 ? "" : "s")"

        // Projects perspective also mixes tasks from several projects
        // together (same reasoning as showsProjectBreadcrumb above), so its
        // header additionally surfaces how many distinct projects are
        // represented — matching OmniFocus's "30 actions, 5 projects".
        if case .projects = perspective {
            let projectCount = Set(nodes.compactMap(\.task.projectID)).count
            return "\(actionsText), \(projectCount) project\(projectCount == 1 ? "" : "s")"
        }
        return actionsText
    }

    private func taskRow(for node: TaskNode) -> some View {
        TaskRow(
            node: node,
            selectedTaskID: selectedTaskID,
            allProjects: allProjects,
            allTags: allTags,
            allTaskTags: allTaskTags,
            modelContext: modelContext,
            showsProjectBreadcrumb: showsProjectBreadcrumb,
            onAddSubtask: { subtaskParent = $0 }
        )
        .listRowSeparator(.hidden)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(accentColor)
                    Text(itemCountLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if perspective == .inbox {
                    Button {
                        isAddingInboxTask = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Inbox Action")
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Divider()

            // `List(data, children:)` — the tree convenience initializer —
            // doesn't support `.onMove`, and `.dropDestination` inside a List
            // doesn't fire on macOS, so nested drag-to-reorder needs manual
            // ForEach+DisclosureGroup recursion (via TaskRow, a real
            // recursive View type) with `.onMove` at each level.
            List(selection: $selectedTaskID) {
                if case .projects = perspective {
                    // One header + conditionally-shown rows per project
                    // (matching ForecastView's date sections) rather than a
                    // flat list, so the header above can stay fixed at
                    // "Projects" instead of naming whichever single project
                    // happens to be selected.
                    ForEach(Array(projectSections.enumerated()), id: \.element.id) { index, section in
                        let expanded = isProjectExpandedBinding(for: section.id)
                        SectionHeaderRow(isExpanded: expanded) {
                            EditableNameText(name: nameBinding(for: section.project), font: .headline)
                        }
                        .listRowSeparator(.hidden)
                        if expanded.wrappedValue {
                            ForEach(Array(section.nodes.enumerated()), id: \.element.id) { rowIndex, node in
                                taskRow(for: node)
                                    .padding(.top, rowIndex == 0 ? 6 : 0)
                            }
                            .onMove { offsets, destination in
                                Mutations.reorder(section.nodes.map(\.task), fromOffsets: offsets, toOffset: destination)
                            }
                            .padding(.leading, sectionHeaderLabelIndent)
                        }
                        if index < projectSections.count - 1 {
                            Divider()
                                .listRowSeparator(.hidden)
                        }
                    }
                } else if case .tags = perspective {
                    // Same header/indent/divider shape as Projects, but no
                    // .onMove — a task can appear under more than one tag
                    // section, so "reorder within this section" has no
                    // single well-defined meaning the way it does for a
                    // task's one project.
                    ForEach(Array(tagSections.enumerated()), id: \.element.id) { index, section in
                        let expanded = isTagExpandedBinding(for: section.id)
                        SectionHeaderRow(isExpanded: expanded) {
                            Text(section.tag.name)
                                .font(.headline)
                        }
                        .listRowSeparator(.hidden)
                        if expanded.wrappedValue {
                            ForEach(Array(section.nodes.enumerated()), id: \.element.id) { rowIndex, node in
                                taskRow(for: node)
                                    .padding(.top, rowIndex == 0 ? 6 : 0)
                            }
                            .padding(.leading, sectionHeaderLabelIndent)
                        }
                        if index < tagSections.count - 1 {
                            Divider()
                                .listRowSeparator(.hidden)
                        }
                    }
                } else {
                    // .inbox and .flagged: no grouping, but .flagged still
                    // indents to the same depth a dropdown section's rows
                    // would, matching Projects/Tags visually even without
                    // a header above it.
                    ForEach(nodes) { node in taskRow(for: node) }
                        .onMove { offsets, destination in
                            Mutations.reorder(nodes.map(\.task), fromOffsets: offsets, toOffset: destination)
                        }
                        .padding(.leading, isFlaggedPerspective ? sectionHeaderLabelIndent : 0)
                }
            }
            .listStyle(.inset)
            .overlay {
                if nodes.isEmpty {
                    ContentUnavailableView("No Actions", systemImage: "checkmark.circle")
                }
            }
        }
        // Deliberately no .navigationTitle: on macOS, NavigationSplitView
        // surfaces a content/detail column's navigationTitle as a second,
        // redundant plain-text title crammed into the toolbar above the
        // custom colored header below it — OmniFocus doesn't show a
        // duplicate title like that, only the styled header.
        .sheet(item: $subtaskParent) { parent in
            QuickEntryPanel(defaultProjectID: parent.projectID, parentTaskID: parent.id) {
                subtaskParent = nil
            }
        }
        .sheet(isPresented: $isAddingInboxTask) {
            QuickEntryPanel(defaultProjectID: nil, parentTaskID: nil) {
                isAddingInboxTask = false
            }
        }
    }
}

/// A task row that recursively renders its own subtasks — a real `View`
/// struct rather than a function, since a function returning `some View`
/// can't call itself (the opaque type would reference itself).
private struct TaskRow: View {
    let node: TaskNode
    let selectedTaskID: UUID?
    let allProjects: [Project]
    let allTags: [Tag]
    let allTaskTags: [TaskTag]
    let modelContext: ModelContext
    let showsProjectBreadcrumb: Bool
    let onAddSubtask: (TaskItem) -> Void

    var body: some View {
        if let children = node.children {
            DisclosureGroup {
                ForEach(children) { child in
                    TaskRow(
                        node: child,
                        selectedTaskID: selectedTaskID,
                        allProjects: allProjects,
                        allTags: allTags,
                        allTaskTags: allTaskTags,
                        modelContext: modelContext,
                        showsProjectBreadcrumb: showsProjectBreadcrumb,
                        onAddSubtask: onAddSubtask
                    )
                    .listRowSeparator(.hidden)
                }
                .onMove { offsets, destination in
                    Mutations.reorder(children.map(\.task), fromOffsets: offsets, toOffset: destination)
                }
            } label: {
                rowContent
            }
        } else {
            rowContent
        }
    }

    private var projectName: String? {
        guard showsProjectBreadcrumb, let projectID = node.task.projectID else { return nil }
        return allProjects.first { $0.id == projectID }?.name
    }

    private var tagNames: [String] {
        Perspectives.tags(for: node.task, allTags: allTags, allTaskTags: allTaskTags).map(\.name)
    }

    private var rowContent: some View {
        let task = node.task
        return TaskRowView(
            task: task,
            isSelected: task.id == selectedTaskID,
            projectName: projectName,
            tagNames: tagNames,
            allProjects: allProjects,
            allTags: allTags,
            allTaskTags: allTaskTags
        ) {
            Mutations.toggleCompleted(task, in: modelContext)
        }
        .tag(task.id)
        // Without this, DisclosureGroup's label flattens the row (including
        // the checkbox button) into a single generic accessibility element
        // whenever the row has children — this keeps the checkbox and title
        // independently reachable for VoiceOver on parent rows too.
        .accessibilityElement(children: .contain)
        .contextMenu {
            if task.parentTaskID == nil {
                Button("Add Subaction") {
                    onAddSubtask(task)
                }
            }
            Button("Duplicate") {
                Mutations.duplicateTask(task, in: modelContext)
            }
            Divider()
            Button(task.flagged ? "Unflag" : "Flag") {
                task.flagged.toggle()
                task.updatedAt = Date()
            }
            Button(task.completed ? "Mark Incomplete" : "Complete") {
                Mutations.toggleCompleted(task, in: modelContext)
            }
            Menu("Move to Project") {
                Button("Inbox") {
                    task.projectID = nil
                    task.updatedAt = Date()
                }
                ForEach(allProjects) { project in
                    Button(project.name) {
                        task.projectID = project.id
                        task.updatedAt = Date()
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                Mutations.deleteTask(task, in: modelContext)
            }
        }
    }
}
