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
let editingRowFillColor = Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
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
        // .top (not the default .center) so the chevron stays on the
        // label's first line — matters once a selected project's label
        // grows taller with its own Tag/Due chips underneath the name
        // (see ProjectSectionHeader); for a single-line label like a tag
        // section's own header, .top and .center look identical anyway.
        HStack(alignment: .top) {
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

/// A project section's own selectable header — mirrors TaskRowView's
/// selected-row look (blue fill when merely selected, dark fill + blue
/// border when actively typing into a chip) and, when selected, shows the
/// same kind of interactive Tag/Due Date chips a selected action does (see
/// TaskRowView's interactiveMetadataRow), so a project's own tags/due date
/// can be set right here instead of only from ProjectDetailView.
private struct ProjectSectionHeader: View {
    let project: Project
    let nameBinding: Binding<String>
    @Binding var isExpanded: Bool
    let isSelected: Bool
    let isPaneFocused: Bool
    let allTags: [Tag]
    let allProjectTags: [ProjectTag]
    let modelContext: ModelContext
    var onSelect: () -> Void = {}

    @State private var showingDueDatePicker = false
    // Tags hidden — uncomment to restore
    // @State private var isEditingTag = false
    // @State private var tagFieldDraft = ""
    /// Decoupled from `isSelected` on purpose — a first click only selects
    /// this row; renaming the project needs a second, deliberate click on
    /// the already-selected name, matching Finder (same pattern as
    /// TaskRowView's own title and ProjectListView's project/folder rows).
    @State private var isEditingName = false

    private var isEditingAnything: Bool { isEditingName }

    var body: some View {
        SectionHeaderRow(isExpanded: $isExpanded) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                nameView
                Spacer(minLength: 0)
                if isSelected {
                    dueDateChip
                } else if let dueDate = project.dueDate {
                    Text(dueDateLabel(dueDate))
                        .font(.system(size: 13))
                        .foregroundStyle(dueDateTint(dueDate, dimColor: .secondary))
                        .fixedSize()
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.trailing, 6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? (isEditingAnything ? editingRowFillColor : (isPaneFocused ? editingRowBorderColor : Color(red: 70/255, green: 70/255, blue: 70/255))) : Color.clear)
                .overlay {
                    if isSelected && isEditingAnything {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(editingRowBorderColor, lineWidth: 1)
                    }
                }
        }
        .padding(.top, -4)
        .padding(.bottom, isSelected ? -3 : -1.9)
        .contentShape(Rectangle())
        // simultaneousGesture (not .onTapGesture) so this still coexists
        // with the chevron's own toggle Button and the caller's
        // .draggable/.dropDestination — same reasoning as TaskRowView's own
        // row-level tap.
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .onChange(of: isSelected) { _, stillSelected in
            if !stillSelected {
                isEditingName = false
            }
        }
    }

    /// The project name itself only enters rename mode on a second,
    /// deliberate click on an already-selected row's name (matching
    /// Finder) — a first click just selects the row (via onSelect, same as
    /// clicking anywhere else in it). Mirrors TaskRowView's own titleView.
    @ViewBuilder
    private var nameView: some View {
        let text = EditableNameText(name: nameBinding, font: .headline, isSelected: isEditingName)
        if isEditingName {
            text
        } else {
            text
                .transaction { $0.animation = nil }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if isSelected && isPaneFocused { isEditingName = true }
                    }
                )
        }
    }

    // MARK: - Tags (hidden — uncomment to restore)
    /*
    private var assignedTagIDs: Set<UUID> {
        Set(allProjectTags.filter { $0.projectID == project.id }.map(\.tagID))
    }
    private var assignedTags: [Tag] { allTags.filter { assignedTagIDs.contains($0.id) } }
    private var unassignedTags: [Tag] { allTags.filter { !assignedTagIDs.contains($0.id) } }

    @ViewBuilder
    private var tagChips: some View {
        ForEach(assignedTags) { tag in
            Button {
                Mutations.removeTag(tag, fromProject: project, in: modelContext)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 9))
                    Text(tag.name)
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.caption)
                .foregroundStyle(selectedChipTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(selectedChipBackground, in: .capsule)
            }
            .buttonStyle(.plain)
        }

        addTagChip
    }

    private var addTagChip: some View {
        HStack(spacing: 3) {
            if isEditingTag {
                Image(systemName: "tag")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                EditableNameText(
                    name: $tagFieldDraft,
                    font: .caption,
                    isSelected: true,
                    placeholder: "Tag",
                    onCommit: commitTagField
                )
                .frame(width: 50)
            } else {
                Button {
                    tagFieldDraft = ""
                    isEditingTag = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: assignedTags.isEmpty ? "tag" : "plus")
                        if assignedTags.isEmpty {
                            Text("Tag")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(assignedTags.isEmpty ? selectedMetadataLabelColor : selectedChipTextColor)
                    .padding(.horizontal, assignedTags.isEmpty ? 0 : 6)
                    .padding(.vertical, assignedTags.isEmpty ? 0 : 2)
                    .background(assignedTags.isEmpty ? Color.clear : selectedChipBackground, in: .capsule)
                }
                .buttonStyle(.plain)
                .frame(width: assignedTags.isEmpty ? 40 : nil)
            }

            if !unassignedTags.isEmpty {
                Menu {
                    ForEach(unassignedTags) { tag in
                        Button(tag.name) {
                            Mutations.addTag(tag, toProject: project, in: modelContext)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(selectedMetadataLabelColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(selectedMetadataLabelColor)
                .fixedSize()
            }
        }
    }

    private func commitTagField() {
        isEditingTag = false
        let trimmed = tagFieldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let matchedTag = allTags.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        let tag = matchedTag ?? {
            let newTag = Tag(name: trimmed)
            modelContext.insert(newTag)
            return newTag
        }()
        Mutations.addTag(tag, toProject: project, in: modelContext)
    }
    */

    // MARK: - Due date

    @ViewBuilder
    private var dueDateChip: some View {
        Group {
            if let due = project.dueDate {
                HStack(spacing: 3) {
                    Button {
                        showingDueDatePicker = true
                    } label: {
                        Label(due.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                            .font(.system(size: 13))
                            .foregroundStyle(dueDateTint(due, dimColor: selectedMetadataLabelColor))
                    }
                    .buttonStyle(.plain)
                    Button {
                        project.dueDate = nil
                        project.updatedAt = Date()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(dueDateTint(due, dimColor: selectedMetadataLabelColor))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    showingDueDatePicker = true
                } label: {
                    Label("Due", systemImage: "calendar.badge.plus")
                        .font(.system(size: 13))
                        .foregroundStyle(selectedMetadataLabelColor)
                }
                .buttonStyle(.plain)
            }
        }
        .popover(isPresented: $showingDueDatePicker) {
            dueDatePopover
        }
    }

    private var dueDatePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(
                "Due Date",
                selection: Binding(
                    get: { project.dueDate ?? Date() },
                    set: { project.dueDate = $0; project.updatedAt = Date() }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            if project.dueDate != nil {
                Button("Clear") {
                    project.dueDate = nil
                    project.updatedAt = Date()
                    showingDueDatePicker = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.callout)
            }
        }
        .padding()
        .frame(minWidth: 260)
    }

    /// Matches TaskRowView's dueDateTint: today = orange, tomorrow = yellow,
    /// overdue = red, otherwise the given dim color.
    private func dueDateTint(_ dueDate: Date, dimColor: Color) -> Color {
        guard !project.isCompleted else { return dimColor }
        let cal = Calendar.current
        if cal.isDateInToday(dueDate) { return .orange }
        if cal.isDateInTomorrow(dueDate) { return .yellow }
        if dueDate < Date() { return .red }
        return dimColor
    }

    private func dueDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
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
            // makeFirstResponder alone triggers NSTextField's own default
            // becomeFirstResponder, which selects all text — fine for a
            // freshly created (empty) title, but for renaming existing text
            // (a project/folder/task name entering edit mode via a second
            // click) that reads as "about to overwrite everything" rather
            // than "ready to edit". Placing the cursor at the very start
            // instead matches the latter.
            //
            // A click-position-aware version was tried (reusing the
            // SwiftUI tap's local coordinates against the field editor)
            // but consistently landed at the end instead — the tapped
            // label and the field editor's own coordinate spaces don't
            // actually line up (text-container insets, possible Y-axis
            // flip between SwiftUI's top-left convention and AppKit's
            // default bottom-left one, etc.), so that point isn't
            // meaningful to characterIndex(for:) here. Getting real
            // click-position accuracy would need capturing an actual
            // AppKit mouseDown (in window/screen coordinates) instead of
            // reusing a SwiftUI gesture's local-space point.
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
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
    /// Called when a project section header is selected (or deselected).
    /// ContentView uses this to drive the right pane's ProjectDetailView.
    var onProjectSelect: ((UUID?) -> Void)? = nil
    /// When false, selected pills render gray (left pane has focus).
    var isPaneFocused: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]
    /// Only needed so a selected project's own tag chips (see
    /// ProjectMetadataRow) can show/edit its assignments the same way
    /// TaskRowView's tagChips does for a selected task.
    @Query(filter: #Predicate<ProjectTag> { $0.deletedAt == nil })
    private var allProjectTags: [ProjectTag]
    /// Only needed so projectSections can match the left pane's own
    /// flattened folder/project order (see leftPaneProjectOrder) — this
    /// pane never shows folders themselves, just borrows their ordering.
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }, sort: \Folder.sortOrder)
    private var allFolders: [Folder]

    @State private var subtaskParent: TaskItem?
    @State private var pinnedIDs: Set<UUID> = []
    /// The .projects perspective's own selection, separate from
    /// selectedTaskID — a project section's header row is selectable the
    /// same way a task row is (see the SectionHeaderRow wrapper below), and
    /// the two are mutually exclusive: selecting one clears the other (see
    /// the onChange below and the header's own tap handler). Also lets
    /// createProjectsTask's "+" target a specific project directly instead
    /// of always falling back to the last section.
    @State private var selectedProjectID: UUID?
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

    /// The exact order projects appear in when reading top-to-bottom
    /// through the left pane (ProjectListView) — folder header rows
    /// themselves aren't represented (this pane has no equivalent of them),
    /// but every project keeps its place relative to the others, including
    /// staying grouped with its own folder-mates: a root-level folder and a
    /// root-level project interleave by sortOrder (mirrors
    /// ProjectListView.rootItems), and each folder's own projects are
    /// inserted in place, sorted by their own sortOrder among just that
    /// folder's siblings — plain sortOrder alone can't do this, since a
    /// folder's projects are renumbered on their own scale (see
    /// Mutations.moveOrderable) that doesn't necessarily interleave
    /// correctly against sibling root-level projects' own sortOrder values.
    private var leftPaneProjectOrder: [UUID] {
        enum RootItem {
            case project(Project)
            case folder(Folder)
            var sortOrder: Int {
                switch self {
                case .project(let project): return project.sortOrder
                case .folder(let folder): return folder.sortOrder
                }
            }
        }
        let rootProjects = allProjects.filter { $0.folderID == nil }
        let rootItems = (rootProjects.map(RootItem.project) + allFolders.map(RootItem.folder))
            .sorted { $0.sortOrder < $1.sortOrder }
        return rootItems.flatMap { item -> [UUID] in
            switch item {
            case .project(let project):
                return [project.id]
            case .folder(let folder):
                return allProjects
                    .filter { $0.folderID == folder.id }
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map(\.id)
            }
        }
    }

    private var projectSections: [ProjectSection] {
        let grouped = Dictionary(grouping: nodes) { $0.task.projectID }
        // Every project the current filter includes gets its own section,
        // even with zero tasks (nodes: []) — previously a project with no
        // matching tasks was skipped entirely (guard ... !groupNodes.isEmpty
        // else return nil), which is also what made a brand-new empty
        // project impossible to target from this pane at all (see
        // singleFilteredProjectID's own doc comment on createProjectsTask).
        let filterIDs: Set<UUID>? = {
            if case .projects(let ids) = perspective, !ids.isEmpty { return ids }
            return nil
        }()
        let relevantProjects = filterIDs.map { ids in allProjects.filter { ids.contains($0.id) } } ?? allProjects
        let sections = relevantProjects.map { project in
            ProjectSection(id: project.id, project: project, nodes: grouped[project.id] ?? [])
        }
        // allProjects itself stays sorted by name (its @Query sort) since
        // that's still the right order for the project-picker menu in
        // TaskRowView's interactiveMetadataRow — reordering just this
        // returned copy to leftPaneProjectOrder instead matches this
        // pane's own section order to the left pane's without touching
        // that picker's alphabetical order.
        let order = leftPaneProjectOrder
        return sections.sorted { lhs, rhs in
            let lhsIndex = order.firstIndex(of: lhs.id) ?? .max
            let rhsIndex = order.firstIndex(of: rhs.id) ?? .max
            return lhsIndex < rhsIndex
        }
    }

    /// When the left pane's filter narrows to exactly one project, that's
    /// the obvious target for a new task even if it has no ProjectSection
    /// yet — a brand-new, still-empty project has no section to click (see
    /// projectSections above), so selectedProjectID alone can never be set
    /// for it, and createProjectsTask's "+" had no way to target it either.
    private var singleFilteredProjectID: UUID? {
        guard case .projects(let ids) = perspective, ids.count == 1 else { return nil }
        return ids.first
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
        case .inbox: return Color(red: 90 / 255, green: 90 / 255, blue: 128 / 255)
        case .flagged: return .orange
        case .projects: return .blue
        case .tags: return .pink
        case .done: return Color(white: 0.52)
        }
    }

    /// A project breadcrumb only makes sense where tasks from multiple
    /// projects are mixed together with no other indication which is
    /// which — Inbox tasks have no project by definition, and .projects
    /// groups its rows under a per-project dropdown header instead (see
    /// projectSections), so a breadcrumb on each row would be redundant.
    private var showsProjectBreadcrumb: Bool {
        switch perspective {
        case .flagged, .tags, .done: return true
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
        if case .done = perspective { return false }
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
        case .done: noun = "action"
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
    /// an existing task selection here always adds a *subaction* nested
    /// under it (see subaction.png) — this pane mixes several projects'
    /// actions together, so "insert after the selected sibling" wouldn't
    /// have one obvious project to land in the way Inbox's flat list does.
    /// A selected *project* — its section header row (selectedProjectID),
    /// or the left pane narrowing the filter to exactly one project
    /// (singleFilteredProjectID), which matters because a brand-new,
    /// still-empty project has no section header to click in the first
    /// place — instead adds a new top-level action straight to that
    /// project. With nothing selected at all, it falls back to that same
    /// "lands at the bottom" idea applied to the last project section
    /// shown, appended after its own last top-level action.
    private func createProjectsTask() {
        let newTask: TaskItem
        if let selectedID = selectedTaskID, let parent = allTasks.first(where: { $0.id == selectedID }) {
            // If the selected task is itself a subaction, use its parent so
            // the new task becomes a sibling (same level), not a sub-subaction.
            let effectiveParentID = parent.parentTaskID ?? parent.id
            newTask = TaskItem(title: "", projectID: parent.projectID, parentTaskID: effectiveParentID)
        } else if let projectID = selectedProjectID ?? singleFilteredProjectID {
            // .first(where:) rather than requiring a match — a brand-new,
            // still-empty project has no section yet (see
            // singleFilteredProjectID's own doc comment), so this must
            // tolerate nil and fall back to Mutations.sortOrder's own
            // both-nil default instead of insisting on an existing section.
            let lastSortOrder = projectSections.first(where: { $0.id == projectID })?.nodes.map(\.task.sortOrder).max()
            newTask = TaskItem(
                title: "",
                projectID: projectID,
                sortOrder: Mutations.sortOrder(after: lastSortOrder, before: nil)
            )
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

    /// leadingIndent: how far this top-level row's own content should sit
    /// from the left edge (0 for Inbox's flat, ungrouped list; sectionTaskIndent
    /// under a project/tag section header or in Flagged). Passed to TaskRow
    /// as an explicit value baked into TaskRowView's own leading padding
    /// (see its doc comment) instead of external `.padding(.leading:)`, so
    /// every row's selection background is the same full width regardless
    /// of how indented its content is — project header, top-level action,
    /// or (via TaskRow's own recursion) subaction all end up the same.
    private func taskRow(for node: TaskNode, siblings: [TaskItem], leadingIndent: CGFloat = 0) -> some View {
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
            leadingIndent: leadingIndent,
            isPaneFocused: isPaneFocused
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

            // A plain Divider() renders at its native ~1pt thickness (2px on
            // a Retina display); this hairline is tuned to half that so the
            // line under the header reads as a single device pixel instead.
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 0.5)

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
                        ProjectSectionHeader(
                            project: section.project,
                            nameBinding: nameBinding(for: section.project),
                            isExpanded: expanded,
                            isSelected: selectedProjectID == section.project.id,
                            isPaneFocused: isPaneFocused,
                            allTags: allTags,
                            allProjectTags: allProjectTags,
                            modelContext: modelContext,
                            onSelect: {
                                selectedProjectID = section.project.id
                                selectedTaskID = nil
                                onProjectSelect?(section.project.id)
                            }
                        )
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
                                // Cascades to every subtask too — see
                                // moveToProject's own doc comment.
                                Mutations.moveToProject(dragged, projectID: section.project.id, in: modelContext)
                            }
                            // Dropped on the section header itself, not a
                            // specific row — see ProjectListView's identical
                            // parentTaskID reset for why.
                            dragged.parentTaskID = nil
                            let lastSortOrder = section.nodes.map(\.task.sortOrder).max()
                            dragged.sortOrder = Mutations.sortOrder(after: lastSortOrder, before: nil)
                            return true
                        }
                        if expanded.wrappedValue {
                            let siblings = section.nodes.map(\.task)
                            ForEach(Array(section.nodes.enumerated()), id: \.element.id) { rowIndex, node in
                                taskRow(for: node, siblings: siblings, leadingIndent: sectionTaskIndent)
                                    .padding(.top, rowIndex == 0 ? 0 : 0)
                            }
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
                                taskRow(for: node, siblings: [], leadingIndent: sectionTaskIndent)
                                    .padding(.top, rowIndex == 0 ? 0 : 0)
                            }
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
                        taskRow(for: node, siblings: siblings, leadingIndent: isFlaggedPerspective ? sectionTaskIndent : 0)
                    }
                }
            }
            .listStyle(.inset)
            // .listStyle(.inset) reserves its own fixed horizontal margin
            // on macOS — leading padding here used to cancel that back out
            // (-12: the same compensation ProjectListView/TagListView
            // apply, plus an extra -6 since every row here (TaskRowView)
            // also bakes in its own 6pt leading padding for its selection
            // background), but that negative padding lays this List's real
            // backing NSTableView out that much further left than this
            // pane's nominal bounds — and neither .clipped() (this one or
            // ContentView's ancestor one) actually shrinks the table
            // view's real NSView frame, only its rendering — so the
            // oversized real frame was swallowing hover/drag for the
            // ResizableDivider immediately to its left (between this pane
            // and ProjectListView). Dropped to 0: trades away that margin
            // compensation (expect some extra blank space along this
            // List's left edge) for the divider actually working again.
            .padding(.leading, 0)
            .padding(.trailing, -10)
            .clipped()
            .overlay {
                if nodes.isEmpty {
                    ContentUnavailableView("No Actions", systemImage: "checkmark.circle")
                }
            }
            .onChange(of: selectedTaskID) { _, newValue in
                guard let newValue else { return }
                selectedProjectID = nil
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
                    // anchor: nil = scroll only the minimum needed to make
                    // the row fully visible; no-op if it's already on screen.
                    proxy.scrollTo(newValue, anchor: nil)
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
    /// How far this row's own content sits from the left edge, baked into
    /// TaskRowView's own leading padding (see its doc comment) rather than
    /// external `.padding(.leading:)` — that's what keeps this row's
    /// selection background the same full width a project header's or any
    /// other action's is, regardless of nesting depth. TaskListView's three
    /// taskRow(for:) call sites pass sectionTaskIndent (or 0) for a
    /// top-level row; recursing into a child below passes this same value
    /// plus subactionIndent, so depth keeps accumulating exactly as it did
    /// under the old external-padding scheme.
    var leadingIndent: CGFloat = 0
    var isPaneFocused: Bool = true

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
                // The chevron renders as part of rowContent itself (see
                // TaskRowView's hasChildren) rather than this row being
                // wrapped as a separate SectionHeaderRow's label — that kept
                // the chevron outside rowContent's own selection background
                // entirely. TaskRowView's chevron+checkbox pairing reserves
                // the same 24pt (14 chevron + 10 spacing) a SectionHeaderRow
                // would have, so subtracting it back out of leadingIndent
                // here (it can go negative, e.g. for a top-level row) still
                // lands this row's checkbox in line with sibling rows that
                // never grew a chevron.
                rowContent(leadingIndent: leadingIndent - 24, hasChildren: true)
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
                            onAddSubtask: onAddSubtask,
                            leadingIndent: leadingIndent + subactionIndent,
                            isPaneFocused: isPaneFocused
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                }
            }
        } else {
            rowContent(leadingIndent: leadingIndent)
        }
    }

    private var projectName: String? {
        guard showsProjectBreadcrumb, let projectID = node.task.projectID else { return nil }
        return allProjects.first { $0.id == projectID }?.name
    }

    private var tagNames: [String] {
        Perspectives.tags(for: node.task, allTags: allTags, allTaskTags: allTaskTags).map(\.name)
    }

    private func rowContent(leadingIndent: CGFloat, hasChildren: Bool = false) -> some View {
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
            onSelect: { selectedTaskID = task.id },
            leadingIndent: leadingIndent,
            hasChildren: hasChildren,
            isExpanded: isExpanded,
            onToggleExpanded: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } },
            isPaneFocused: isPaneFocused
        )
        // Drag-and-drop reordering — the replacement for List's native move
        // handles (see the List's own doc comment above for why those no
        // longer work here). Looks the dragged task up in allTasks (not
        // just siblings) so dropping one from a *different* project's
        // section onto this row also reassigns it to this row's project,
        // not just silently failing to find it.
        // (.draggable itself now lives in TaskRowView, co-located with its
        // own tap gesture — see that file's doc comment for why.)
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let draggedID = UUID(uuidString: uuidString),
                  let dragged = allTasks.first(where: { $0.id == draggedID })
            else { return false }
            if dragged.projectID != task.projectID {
                // Cascades to every subtask too — see moveToProject's own
                // doc comment.
                Mutations.moveToProject(dragged, projectID: task.projectID, in: modelContext)
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
