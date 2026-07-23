import SwiftUI
import SwiftData
import AppKit

/// Chevron frame width (14) + the HStack spacing to the label (10) in
/// SectionHeaderRow below — exposed so callers can indent their section's
/// content to line up with where the label's own text starts.
let sectionHeaderLabelIndent: CGFloat = 24

/// Indents a subaction's row so its checkbox lines up with where its
/// parent's own text starts — TaskRowView's fixed checkbox width plus the
/// HStack spacing between that checkbox and the text next to it there —
/// rather than whatever indent a system disclosure control would give.
let subactionIndent: CGFloat = TaskRowView.checkboxWidth + 8

/// Indents a project/tag/flagged section's task rows so their checkbox
/// (not just the row's outer frame) lines up with where the section
/// header's own label text starts. sectionHeaderLabelIndent marks that
/// text's x-position, but TaskRowView adds its own 6pt .padding(.horizontal)
/// inside that frame — subtracting it here cancels that back out so the
/// checkbox itself, not empty padding in front of it, is what starts there.
let sectionTaskIndent: CGFloat = sectionHeaderLabelIndent - 6

/// Matches OmniFocus's own selected+editing row look: a dark charcoal fill
/// with a muted blue border. Drawn entirely by hand (TaskRowView applies
/// these directly, keyed off its own isSelected) rather than via List's
/// native selection tint — macOS renders that as a fixed blue/gray
/// highlight no matter what `.tint`/`.listRowBackground` is set to, so
/// TaskListView's List no longer uses a `selection:` binding at all, and
/// this is the replacement.
let editingRowFillColor = Color(red: 40 / 255, green: 43 / 255, blue: 48 / 255)
let editingRowBorderColor = Color(red: 54 / 255, green: 81 / 255, blue: 111 / 255)

/// Project/Tag/Due labels and chips in a selected row's interactive
/// metadata sit on top of editingRowBorderColor's solid blue fill —
/// .secondary/.tertiary (calibrated for a plain window background) read as
/// nearly invisible there. These fixed, lighter tones replace them in that
/// context only, matching OmniFocus's own lighter-gray chip treatment.
let selectedMetadataLabelColor = Color.white.opacity(0.75)
let selectedChipBackground = Color.white.opacity(0.85)
let selectedChipTextColor = Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255)

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

/// NSTextField subclass that positions the cursor at the click point on first
/// focus instead of selecting all text (AppKit's default first-click behavior).
///
/// Root cause: NSTextField.becomeFirstResponder calls selectText(_:) which
/// selects all text synchronously. We suppress that call via a flag, then
/// manually position the insertion point after super.mouseDown returns.
final class CursorPositioningField: NSTextField {
    private var suppressSelectAll = false

    override func mouseDown(with event: NSEvent) {
        let alreadyEditing = currentEditor() != nil
        if !alreadyEditing { suppressSelectAll = true }
        super.mouseDown(with: event)
        suppressSelectAll = false
        // After first-click activation, place cursor at click position.
        if !alreadyEditing, let editor = currentEditor() as? NSTextView {
            let editorPt = editor.convert(event.locationInWindow, from: nil)
            let raw = editor.characterIndex(for: editorPt)
            let idx = raw == NSNotFound ? editor.string.count : raw
            editor.setSelectedRange(NSRange(location: idx, length: 0))
        }
    }

    override func selectText(_ sender: Any?) {
        guard !suppressSelectAll else { return }
        super.selectText(sender)
    }
}

/// NSViewRepresentable wrapping CursorPositioningField so EditableNameText
/// gets click-to-cursor behavior instead of click-to-select-all.
private struct CursorTextField: NSViewRepresentable {
    @Binding var text: String
    var nsFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var placeholder: String = ""
    var onCommit: (() -> Void)? = nil

    func makeNSView(context: Context) -> CursorPositioningField {
        let field = CursorPositioningField(string: text)
        field.isBezeled = false
        field.isBordered = false
        // Opaque, painted with the *actual* matching row color — not
        // drawsBackground = false / .clear. A `red` test proved this field
        // (and its field editor) render whatever color they're given
        // immediately and reliably; `.clear` specifically was the problem,
        // since on macOS a transparent NSTextField/NSTextView reveals
        // whatever's *behind* it at the raw AppKit compositing layer —
        // which turns out to be plain black here, not this row's SwiftUI
        // `.background()` (that SwiftUI layer apparently isn't actually
        // compositing behind this NSViewRepresentable the way it looks
        // like it should). Painting the real color directly sidesteps
        // that compositing question entirely.
        field.drawsBackground = true
        field.backgroundColor = NSColor(editingRowFillColor)
        field.focusRingType = .none
        field.font = nsFont
        field.placeholderString = placeholder.isEmpty ? nil : placeholder
        field.delegate = context.coordinator
        // This view is only ever created the moment a row becomes selected
        // (EditableNameText swaps Text for this field), so focusing here —
        // not just on click, unlike CursorPositioningField's own mouseDown
        // handling — is what puts the cursor in a freshly created row's
        // title immediately, with no click required.
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: CursorPositioningField, context: Context) {
        if !context.coordinator.isEditing { nsView.stringValue = text }
        nsView.font = nsFont
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CursorTextField
        var isEditing = false

        init(_ parent: CursorTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            // The field itself is already painted with the real matching
            // color (see makeNSView) — this covers the field editor too,
            // confirmed reliable by a red test earlier (it rendered
            // immediately and never reverted). No transparency involved
            // this time, so no reset-on-layout/relayout-invalidation
            // concerns either.
            guard let editor = (obj.object as? NSTextField)?.currentEditor() as? NSTextView else { return }
            editor.drawsBackground = true
            editor.backgroundColor = NSColor(editingRowFillColor)
            editor.enclosingScrollView?.drawsBackground = false
        }

        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSTextField { parent.text = f.stringValue }
        }
        func controlTextDidEndEditing(_ obj: Notification) {
            isEditing = false
            if let f = obj.object as? NSTextField {
                let t = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { parent.text = t }
            }
            parent.onCommit?()
        }
    }
}

/// Plain text that turns into an inline-editable field when the row is selected.
struct EditableNameText: View {
    @Binding var name: String
    var font: Font = .body
    var strikethrough: Bool = false
    var foregroundColor: Color = .primary
    var isSelected: Bool = false
    var placeholder: String = ""
    var onCommit: (() -> Void)? = nil
    var selectAllOnFocus: Bool = false

    var body: some View {
        if isSelected {
            CursorTextField(
                text: $name,
                nsFont: nsFont,
                placeholder: placeholder,
                onCommit: onCommit
            )
            .frame(maxWidth: .infinity)
        } else {
            Text(name)
                .font(font)
                .strikethrough(strikethrough)
                .foregroundStyle(foregroundColor)
        }
    }

    private var nsFont: NSFont {
        switch font {
        case .headline: return .boldSystemFont(ofSize: NSFont.systemFontSize)
        case .largeTitle: return .systemFont(ofSize: NSFont.systemFontSize + 10, weight: .bold)
        case .caption: return .systemFont(ofSize: NSFont.smallSystemFontSize)
        default: return .systemFont(ofSize: NSFont.systemFontSize)
        }
    }
}

struct TaskListView: View {
    let perspective: Perspective
    let title: String
    @Binding var selectedTaskID: UUID?
    var accentColorOverride: Color? = nil
    var reviewProject: Project? = nil

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
    @State private var pinnedIDs: Set<UUID> = []
    /// Collapsed-state per project, keyed by Project.id — absent means
    /// expanded (mirrors ForecastView's collapsedSectionIDs).
    @State private var collapsedProjectIDs: Set<UUID> = []
    /// Collapsed-state per tag, keyed by Tag.id — same shape as
    /// collapsedProjectIDs, for the .tags perspective's tag sections.
    @State private var collapsedTagIDs: Set<UUID> = []

    private var nodes: [TaskNode] {
        Perspectives.taskTree(for: perspective, allTasks: allTasks, allTaskTags: allTaskTags, pinnedIDs: pinnedIDs)
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

    private func reviewIntervalLabel(_ project: Project) -> String {
        switch project.reviewIntervalDays {
        case nil: return "No Review"
        case 1: return "Review Daily"
        case 7: return "Review Weekly"
        case 30: return "Review Monthly"
        case let days?: return "Review Every \(days) Days"
        }
    }

    private func lastReviewedLabel(_ project: Project) -> String {
        guard let date = project.lastReviewedAt else { return "never reviewed" }
        return "last reviewed \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func setReviewInterval(_ project: Project, _ days: Int?) {
        project.reviewIntervalDays = days
        project.updatedAt = Date()
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

    /// False only for .projects — every row there already sits under its
    /// own project's dropdown section (see projectSections), so the
    /// picker chip would be a redundant second way to say the same thing;
    /// affiliation there instead changes by dragging the row onto a
    /// different project section (or a project in the left pane). Every
    /// other perspective keeps the picker, since it's their only way to
    /// assign/reassign a project at all.
    private var showsProjectPicker: Bool {
        if case .projects = perspective { return false }
        return true
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

    /// Creates a new inbox item in place, matching OmniFocus rather than
    /// opening a popup: with nothing selected it lands at the bottom
    /// of the list (its default sortOrder, a fresh timestamp, already sorts
    /// after every existing task); with a row selected it's inserted right
    /// after it instead, using the same fractional-sortOrder scheme
    /// Mutations.reorder uses so no other row needs renumbering. Selecting
    /// the new task both deselects whatever was selected before and — via
    /// TaskRowView's isSelected-driven EditableNameText — immediately shows
    /// it in edit mode with the cursor ready for typing.
    private func createInboxTask() {
        let siblings = nodes.map(\.task)
        let newTask: TaskItem
        if let selectedIndex = siblings.firstIndex(where: { $0.id == selectedTaskID }) {
            let after = selectedIndex + 1 < siblings.count ? siblings[selectedIndex + 1].sortOrder : nil
            newTask = TaskItem(
                title: "",
                sortOrder: Mutations.sortOrder(after: siblings[selectedIndex].sortOrder, before: after)
            )
        } else {
            newTask = TaskItem(title: "")
        }
        modelContext.insert(newTask)
        selectedTaskID = newTask.id
    }

    /// The Projects pane's own "+". Unlike createInboxTask's sibling-insert,
    /// an existing selection here always adds a *subaction* nested under it
    /// (see subaction.png) — this pane mixes several projects' actions
    /// together, so "insert after the selected sibling" wouldn't have one
    /// obvious project to land in the way Inbox's flat list does. With
    /// nothing selected, it falls back to that same "lands at the bottom"
    /// idea applied to the last project section shown, appended after its
    /// own last top-level action.
    private func createProjectsTask() {
        let newTask: TaskItem
        if let selectedID = selectedTaskID, let parent = allTasks.first(where: { $0.id == selectedID }) {
            newTask = TaskItem(title: "", projectID: parent.projectID, parentTaskID: parent.id)
        } else if let lastSection = projectSections.last {
            let lastSortOrder = lastSection.nodes.map(\.task.sortOrder).max()
            newTask = TaskItem(
                title: "",
                projectID: lastSection.project.id,
                sortOrder: Mutations.sortOrder(after: lastSortOrder, before: nil)
            )
        } else {
            return
        }
        modelContext.insert(newTask)
        selectedTaskID = newTask.id
    }

    /// headerIndentCancel: only meaningful for a top-level row (the only
    /// depth this helper is ever called at — deeper nesting recurses inside
    /// TaskRow.body itself, not through here). Passed through so that if
    /// this particular node later gains a subaction and grows its own
    /// dropdown chevron, TaskRow can cancel out exactly this row's own
    /// section indent — see TaskRow's headerIndentCancel doc comment.
    private func taskRow(for node: TaskNode, siblings: [TaskItem], headerIndentCancel: CGFloat = 0) -> some View {
        TaskRow(
            node: node,
            selectedTaskID: $selectedTaskID,
            siblings: siblings,
            allTasks: allTasks,
            allProjects: allProjects,
            allTags: allTags,
            allTaskTags: allTaskTags,
            modelContext: modelContext,
            showsProjectBreadcrumb: showsProjectBreadcrumb,
            showsProjectPicker: showsProjectPicker,
            pinnedIDs: $pinnedIDs,
            onPin: { pinnedIDs.insert($0) },
            onAddSubtask: { subtaskParent = $0 },
            headerIndentCancel: headerIndentCancel
        )
        .listRowSeparator(.hidden)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(accentColor)
                Spacer()
                if perspective == .inbox {
                    Button {
                        createInboxTask()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Inbox Action")
                } else if case .projects = perspective {
                    Button {
                        createProjectsTask()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selectedTaskID == nil ? "New Action" : "New Subaction")
                }
                if let reviewProject {
                    Button("Mark Reviewed") {
                        reviewProject.lastReviewedAt = Date()
                        reviewProject.updatedAt = Date()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(accentColor, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, reviewProject == nil ? 2 : 4)

            if reviewProject == nil {
                Text(itemCountLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            if let reviewProject {
                HStack(spacing: 4) {
                    Menu {
                        Button("Daily") { setReviewInterval(reviewProject, 1) }
                        Button("Weekly") { setReviewInterval(reviewProject, 7) }
                        Button("Monthly") { setReviewInterval(reviewProject, 30) }
                        Button("Never") { setReviewInterval(reviewProject, nil) }
                    } label: {
                        Text(reviewIntervalLabel(reviewProject))
                            .font(.subheadline)
                            .foregroundStyle(accentColor)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Text("•  \(lastReviewedLabel(reviewProject))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            Divider()

            // `List(data, children:)` — the tree convenience initializer —
            // doesn't support `.onMove`, and `.dropDestination` inside a List
            // doesn't fire on macOS, so nested drag-to-reorder needs manual
            // ForEach+DisclosureGroup recursion (via TaskRow, a real
            // recursive View type). This List also has no `selection:`
            // binding at all (unlike other lists in this app) — macOS
            // renders a selected row's native highlight as a fixed
            // blue/gray fill no matter what `.tint`/`.listRowBackground`
            // it's given, so TaskRowView draws its own selected+editing
            // background by hand instead (see editingRowFillColor /
            // editingRowBorderColor), driven by tapping a row rather than
            // List's own selection. Reordering is therefore drag-and-drop
            // (.draggable/.dropDestination in TaskRow.rowContent) rather
            // than List's native move handles, which relied on that same
            // selection binding to initiate reliably.
            //
            // Wrapped in ScrollViewReader so a freshly created (or
            // otherwise newly selected) row scrolls into view automatically
            // — see the onChange below — instead of landing off-screen
            // when the list is long.
            ScrollViewReader { proxy in
            List {
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
                        // Dropping directly on the section's own header —
                        // not just on one of its rows — reassigns to this
                        // project too, appended at the end of its list.
                        .dropDestination(for: String.self) { items, _ in
                            guard let uuidString = items.first,
                                  let draggedID = UUID(uuidString: uuidString),
                                  let dragged = allTasks.first(where: { $0.id == draggedID })
                            else { return false }
                            if dragged.projectID != section.project.id {
                                dragged.projectID = section.project.id
                                dragged.updatedAt = Date()
                            }
                            let lastSortOrder = section.nodes.map(\.task.sortOrder).max()
                            dragged.sortOrder = Mutations.sortOrder(after: lastSortOrder, before: nil)
                            return true
                        }
                        if expanded.wrappedValue {
                            let siblings = section.nodes.map(\.task)
                            ForEach(Array(section.nodes.enumerated()), id: \.element.id) { rowIndex, node in
                                taskRow(for: node, siblings: siblings, headerIndentCancel: sectionTaskIndent)
                                    .padding(.top, rowIndex == 0 ? 6 : 0)
                            }
                            .padding(.leading, sectionTaskIndent)
                        }
                        if index < projectSections.count - 1 {
                            Divider()
                                .listRowSeparator(.hidden)
                        }
                    }
                } else if case .tags = perspective {
                    // Same header/indent/divider shape as Projects, but no
                    // drag-reorder — a task can appear under more than one
                    // tag section, so "reorder within this section" has no
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
                                taskRow(for: node, siblings: [], headerIndentCancel: sectionTaskIndent)
                                    .padding(.top, rowIndex == 0 ? 6 : 0)
                            }
                            .padding(.leading, sectionTaskIndent)
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
                    let siblings = nodes.map(\.task)
                    ForEach(nodes) { node in
                        taskRow(for: node, siblings: siblings, headerIndentCancel: isFlaggedPerspective ? sectionTaskIndent : 0)
                    }
                    .padding(.leading, isFlaggedPerspective ? sectionTaskIndent : 0)
                }
            }
            .listStyle(.inset)
            .overlay {
                if nodes.isEmpty {
                    ContentUnavailableView("No Actions", systemImage: "checkmark.circle")
                }
            }
            .onChange(of: selectedTaskID) { _, newValue in
                guard let newValue else { return }
                // Deferred a tick, and NOT animated — selecting a row also
                // expands it into edit mode (title field + Project/Tags/Due
                // chips) in this same update, so the row's geometry is
                // still settling right after. An animated scrollTo
                // interpolates against whatever frame is current when it
                // starts, which — while that geometry is still moving —
                // overshoots past the row instead of landing on it. Calling
                // it unanimated after a tick, once layout has caught up,
                // lands directly on the row's real, final position instead.
                DispatchQueue.main.async {
                    // Slightly above .bottom (y: 1.0 exactly) so a sliver
                    // of empty space is left below the row instead of it
                    // sitting flush against the very edge of the list.
                    proxy.scrollTo(newValue, anchor: UnitPoint(x: 0.5, y: 0.9))
                }
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
        .onChange(of: perspective) { _, _ in
            pinnedIDs = []
        }
    }
}

/// A task row that recursively renders its own subtasks — a real `View`
/// struct rather than a function, since a function returning `some View`
/// can't call itself (the opaque type would reference itself).
private struct TaskRow: View {
    let node: TaskNode
    @Binding var selectedTaskID: UUID?
    /// Every task at this row's own nesting level (its section, or its
    /// parent's subtasks) — used to compute where a drag-and-drop lands
    /// (see Mutations.moveTask), since dropping needs to know this row's
    /// actual neighbors, not just the row itself.
    let siblings: [TaskItem]
    /// Every task in the app, not just this section's — a cross-project
    /// drop (see rowContent's dropDestination) needs to find the dragged
    /// task even when it belongs to a different project than this row's,
    /// so it's absent from `siblings`.
    let allTasks: [TaskItem]
    let allProjects: [Project]
    let allTags: [Tag]
    let allTaskTags: [TaskTag]
    let modelContext: ModelContext
    let showsProjectBreadcrumb: Bool
    var showsProjectPicker: Bool = true
    @Binding var pinnedIDs: Set<UUID>
    let onPin: (UUID) -> Void
    let onAddSubtask: (TaskItem) -> Void
    /// How much of this row's own ambient leading indent (the section-level
    /// padding its caller applied — see TaskListView's three taskRow(for:)
    /// call sites) to cancel if this node turns out to have children. A
    /// root-level action with no subactions sits flush with its siblings at
    /// that ambient indent; the moment it gains one, it becomes a
    /// SectionHeaderRow itself and picks up a chevron's own width — without
    /// correction that pushes both the new chevron AND this row's checkbox
    /// an extra sectionTaskIndent+24pt to the right. Canceling exactly this
    /// row's own ambient indent brings the new chevron back flush with a
    /// project/tag section's own chevron; the additional fixed -6 below
    /// (on rowContent specifically) then cancels TaskRowView's own internal
    /// leading padding so the checkbox lands back in line with sibling rows
    /// that never grew a chevron. Left at its default (0) for every
    /// recursively-rendered child, which isn't asked to align with
    /// anything at this fixed depth.
    var headerIndentCancel: CGFloat = 0

    /// Expanded by default, matching Projects/Tags/Forecast's dropdown
    /// sections elsewhere in this file.
    @State private var isExpanded = true

    var body: some View {
        if let children = node.children {
            // Group (not DisclosureGroup) — a real DisclosureGroup indents
            // its nested rows by whatever fixed amount AppKit's outline
            // view happens to use, which isn't something we can compute or
            // override to line up exactly with the parent's text (see
            // subactionIndent). Group is transparent to List's row
            // flattening the same way a bare ForEach is, so the header and
            // each child below still become independently selectable rows.
            Group {
                SectionHeaderRow(isExpanded: $isExpanded) {
                    rowContent
                        .padding(.leading, headerIndentCancel > 0 ? -6 : 0)
                }
                .padding(.leading, -headerIndentCancel)
                .listRowSeparator(.hidden)
                if isExpanded {
                    let childSiblings = children.map(\.task)
                    ForEach(children) { child in
                        TaskRow(
                            node: child,
                            selectedTaskID: $selectedTaskID,
                            siblings: childSiblings,
                            allTasks: allTasks,
                            allProjects: allProjects,
                            allTags: allTags,
                            allTaskTags: allTaskTags,
                            modelContext: modelContext,
                            showsProjectBreadcrumb: showsProjectBreadcrumb,
                            showsProjectPicker: showsProjectPicker,
                            pinnedIDs: $pinnedIDs,
                            onPin: onPin,
                            onAddSubtask: onAddSubtask
                        )
                        .listRowSeparator(.hidden)
                    }
                    .padding(.leading, subactionIndent)
                }
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
            allTaskTags: allTaskTags,
            onToggleComplete: {
                if task.completed { pinnedIDs.remove(task.id) } else { pinnedIDs.insert(task.id) }
                Mutations.toggleCompleted(task, in: modelContext)
            },
            onWillLeaveInbox: { pinnedIDs.insert(task.id) },
            showsProjectPicker: showsProjectPicker,
            onSelect: { selectedTaskID = task.id }
        )
        // Drag-and-drop reordering — the replacement for List's native move
        // handles (see the List's own doc comment above for why those no
        // longer work here). Looks the dragged task up in allTasks (not
        // just siblings) so dropping one from a *different* project's
        // section onto this row also reassigns it to this row's project,
        // not just silently failing to find it.
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let draggedID = UUID(uuidString: uuidString),
                  let dragged = allTasks.first(where: { $0.id == draggedID })
            else { return false }
            if dragged.projectID != task.projectID {
                dragged.projectID = task.projectID
                dragged.updatedAt = Date()
            }
            Mutations.moveTask(dragged, beforeTask: task, in: siblings)
            return true
        }
        // Without this, SectionHeaderRow's label flattens the row
        // (including the checkbox button) into a single generic
        // accessibility element whenever the row has children — this keeps
        // the checkbox and title independently reachable for VoiceOver on
        // parent rows too.
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
                if task.completed {
                    pinnedIDs.remove(task.id)
                } else {
                    pinnedIDs.insert(task.id)
                }
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
