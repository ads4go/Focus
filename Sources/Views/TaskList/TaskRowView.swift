import SwiftUI
import SwiftData

struct TaskRowView: View {
    /// Fixed so a subaction's row can be indented to align exactly with
    /// this row's own text (see TaskListView.subactionIndent) — SF
    /// Symbols' circle glyphs have no other reliable/known width otherwise.
    /// nonisolated because it's read from a plain top-level `let` in
    /// TaskListView.swift, which isn't @MainActor-isolated.
    nonisolated static let checkboxWidth: CGFloat = 20

    let task: TaskItem
    let isSelected: Bool
    /// Shown as a breadcrumb below the title — only meaningful in lists that
    /// mix tasks from multiple projects (Flagged, a Tag's tasks), where the
    /// project isn't already implied by the list itself.
    var projectName: String? = nil
    var tagNames: [String] = []
    /// Full model arrays — only needed when isSelected to power the
    /// interactive project/tag/due-date controls shown inline.
    var allProjects: [Project] = []
    var allTags: [Tag] = []
    var allTaskTags: [TaskTag] = []
    let onToggleComplete: () -> Void
    var onWillLeaveInbox: (() -> Void)? = nil
    /// False in the Projects tab specifically — every row there already
    /// sits under its own project's dropdown section, so the picker chip
    /// would just be a redundant second way to say the same thing;
    /// affiliation there instead changes by dragging the row onto a
    /// different project (see TaskListView/ProjectListView's
    /// .dropDestination handling).
    var showsProjectPicker: Bool = true
    /// Called on tap anywhere in the row not already claimed by one of its
    /// own controls (checkbox, chips, menus) — this row's only path to
    /// becoming selected, now that selection isn't List's native binding
    /// (see TaskListView's List doc comment).
    var onSelect: () -> Void = {}
    /// How far to inset this row's own content (checkbox onward) from its
    /// left edge — folded into this view's own leading padding (see body)
    /// rather than applied as external padding by the caller. That
    /// distinction is what keeps every row's selection background the same
    /// width regardless of nesting: external padding shrinks the space List
    /// proposes to this view before it ever sees it, so its own
    /// full-width-filling background would end up narrower for a more
    /// deeply-indented row; internal padding only pushes the *content*
    /// rightward, leaving this view's (and its background's) overall
    /// reported width untouched. See TaskListView's TaskRow, which computes
    /// this per row (accumulating subactionIndent per nesting level) and
    /// passes it in instead of wrapping rows in `.padding(.leading:)`.
    var leadingIndent: CGFloat = 0
    /// Whether this task has subactions — when true, a disclosure chevron
    /// renders as part of THIS row's own content (see body), sharing its
    /// background/selection highlight and layout, rather than this row
    /// being wrapped as a separate SectionHeaderRow's label the way it used
    /// to be. That older approach left the chevron outside the selection
    /// fill entirely (it belonged to the wrapping SectionHeaderRow, not
    /// this view) and, being a second, differently-sized sibling row
    /// stacked via an outer HStack, could report a taller-than-expected
    /// combined height — both fixed by folding the chevron into this same
    /// view instead.
    var hasChildren: Bool = false
    var isExpanded: Bool = false
    var onToggleExpanded: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var showingDueDatePicker = false
    @State private var isEditingProject = false
    @State private var projectFieldDraft = ""
    @State private var isEditingTag = false
    @State private var tagFieldDraft = ""
    /// Decoupled from `isSelected` on purpose — selecting a row (a single
    /// click) used to also immediately drop its title into rename mode,
    /// which meant just clicking an unselected item to look at it started
    /// editing its name. Now a first click only selects; renaming needs a
    /// second, deliberate click on the already-selected title (see
    /// titleView), matching Finder. The one exception is a freshly created
    /// task (title still empty) — see the onAppear below — which should
    /// still drop straight into edit mode with no extra click.
    @State private var isEditingTitle = false

    private var isOverdue: Bool {
        !task.completed && (task.dueDate.map { $0 < Date() } ?? false)
    }

    /// Whether any of this row's own inline text fields (title, project,
    /// tag) is actively being typed into — drives the dark-fill+border
    /// "editing" look; a merely-selected-but-idle row instead gets the
    /// solid blue fill below (see body's .background).
    private var isEditingAnything: Bool {
        isEditingTitle || isEditingProject || isEditingTag
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Nested at spacing 10 (matching SectionHeaderRow's own
            // chevron+label spacing exactly) so a childless row's checkbox
            // and a has-children row's checkbox land at the identical
            // position — the inner HStack just has one fewer element when
            // there's no chevron to show, rather than changing any offset.
            HStack(spacing: 10) {
                if hasChildren {
                    Button(action: onToggleExpanded) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.gray)
                            .frame(width: 14)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onToggleComplete) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(checkboxTint)
                        .frame(width: Self.checkboxWidth)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                titleView

                if isSelected {
                    interactiveMetadataRow
                } else if projectName != nil || !tagNames.isEmpty || task.dueDate != nil || task.deferDate != nil {
                    staticMetadataRow
                }

                if isSelected && !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(.top, 2)
                }
            }

            Spacer()

            if task.flagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 6 + leadingIndent)
        .padding(.trailing, 6)
        .background {
            // OmniFocus draws selection two ways, hand-drawn here since
            // List's native selection tint can't be recolored to match
            // either: a merely-selected-but-idle row gets a solid blue
            // fill (selected.png), while actually typing into one of this
            // row's own text fields (title, project, tag) switches to a
            // dark charcoal fill with a blue border instead (omni.png).
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? (isEditingAnything ? editingRowFillColor : editingRowBorderColor) : Color.clear)
                .overlay {
                    if isSelected && isEditingAnything {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(editingRowBorderColor, lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        // .simultaneousGesture (not .onTapGesture) — .onTapGesture
        // recognizes exclusively, competing with .draggable (applied by
        // the caller, TaskListView's rowContent, around this whole view)
        // for the same initial press, which was enough to stop dragging
        // from being recognized at all. simultaneousGesture explicitly
        // lets both recognize side by side instead of one blocking the
        // other.
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .onAppear {
            // Freshly created tasks start with an empty title and are
            // already selected at the moment they appear — those should
            // still drop straight into edit mode with the cursor ready,
            // same as before, with no extra click needed. Nothing else
            // legitimately has an empty title (committing an emptied-out
            // title reverts instead — see CursorTextField's Coordinator),
            // so this only ever fires for that one case.
            if isSelected && task.title.isEmpty {
                isEditingTitle = true
            }
        }
        .onChange(of: isSelected) { _, stillSelected in
            if !stillSelected { isEditingTitle = false }
        }
    }

    /// The title itself only enters rename mode on a second, deliberate
    /// click on an already-selected row's name (matching Finder) — a
    /// first click just selects the row (via onSelect, same as clicking
    /// anywhere else in it). No tap gesture is attached at all once
    /// actually editing, so it can't ever compete with the hosted text
    /// field's own click-to-position-cursor handling.
    @ViewBuilder
    private var titleView: some View {
        let text = EditableNameText(
            name: titleBinding,
            strikethrough: task.completed,
            foregroundColor: task.completed ? .secondary : .primary,
            isSelected: isEditingTitle,
            placeholder: "Untitled Item"
        )
        if isEditingTitle {
            text
        } else {
            // A Button here (SwiftUI's default press appearance) was
            // what made the title visibly "flash" dark on every click —
            // even at .buttonStyle(.plain). simultaneousGesture avoids
            // that entirely, and (like the row-level tap below) doesn't
            // compete with .draggable for the same press the way a bare
            // .onTapGesture would. The row's own simultaneousGesture
            // already calls onSelect() for a tap anywhere in the row,
            // including here, so this only needs to handle promoting an
            // already-selected row into rename mode.
            text
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if isSelected {
                            isEditingTitle = true
                        }
                    }
                )
        }
    }

    // MARK: - Static metadata (unselected)

    private var staticMetadataRow: some View {
        HStack(spacing: 6) {
            if let projectName {
                Label(projectName, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !tagNames.isEmpty {
                Label(tagNames.joined(separator: ", "), systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2), in: .capsule)
            }
            if let dueDate = task.dueDate {
                DateChip(text: dueDate.formatted(.dateTime.month(.abbreviated).day()),
                         systemImage: "calendar", tint: dueDateTint(dueDate))
            }
            if let deferDate = task.deferDate {
                DateChip(text: deferDate.formatted(.dateTime.month(.abbreviated).day()),
                         systemImage: "clock", tint: .secondary)
            }
        }
    }

    // MARK: - Interactive metadata (selected)

    private var interactiveMetadataRow: some View {
        HStack(spacing: 6) {
            if showsProjectPicker {
                projectPickerChip
            }
            tagChips
            dueDateChip
        }
        .padding(.top, 2)
    }

    /// Two separate tap targets, matching OmniFocus: the icon/name itself
    /// enters inline text-edit mode (type a name to create a new project
    /// and assign it right there), while the chevron opens a menu to pick
    /// from existing projects instead — see commitProjectField.
    private var projectPickerChip: some View {
        let current = allProjects.first { $0.id == task.projectID }
        return HStack(spacing: 3) {
            if isEditingProject {
                Image(systemName: "folder.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                EditableNameText(
                    name: $projectFieldDraft,
                    font: .caption,
                    isSelected: true,
                    placeholder: "Project",
                    onCommit: commitProjectField
                )
                .frame(width: 60)
            } else {
                Button {
                    projectFieldDraft = ""
                    isEditingProject = true
                } label: {
                    Label(current?.name ?? "Project", systemImage: current == nil ? "folder.badge.plus" : "folder")
                        .font(.caption)
                        .foregroundStyle(selectedMetadataLabelColor)
                }
                .buttonStyle(.plain)
            }

            Menu {
                Button("Inbox") {
                    task.projectID = nil
                    task.updatedAt = Date()
                }
                Divider()
                ForEach(allProjects) { project in
                    Button {
                        if task.projectID == nil { onWillLeaveInbox?() }
                        task.projectID = project.id
                        task.updatedAt = Date()
                    } label: {
                        if project.id == task.projectID {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(selectedMetadataLabelColor)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            // Menu's own borderless-button label rendering renders its
            // icon in the accent/white control color, ignoring the
            // Image's own .foregroundStyle above — .tint here is the
            // lever that actually recolors it.
            .tint(selectedMetadataLabelColor)
            .fixedSize()
        }
    }

    /// Finds an existing project matching the typed name (case-insensitive)
    /// rather than always creating a duplicate, and only creates a new one
    /// when nothing matches — the "or create a new Project right then" half
    /// of projectPickerChip's two-tap-targets behavior.
    private func commitProjectField() {
        isEditingProject = false
        let trimmed = projectFieldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let matchedProject = allProjects.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        let project = matchedProject ?? {
            let newProject = Project(name: trimmed)
            modelContext.insert(newProject)
            return newProject
        }()
        if task.projectID == nil { onWillLeaveInbox?() }
        task.projectID = project.id
        task.updatedAt = Date()
    }

    @ViewBuilder
    private var tagChips: some View {
        let assignedIDs = Set(allTaskTags.filter { $0.taskID == task.id }.map(\.tagID))
        let assigned = allTags.filter { assignedIDs.contains($0.id) }
        let unassigned = allTags.filter { !assignedIDs.contains($0.id) }

        ForEach(assigned) { tag in
            Button {
                Mutations.removeTag(tag, from: task, in: modelContext)
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

        addTagChip(hasAssignedTags: !assigned.isEmpty, unassigned: unassigned)
    }

    /// Two separate tap targets, matching projectPickerChip/OmniFocus: the
    /// icon/label itself enters inline text-edit mode (type a name to
    /// find-or-create a tag and add it right there), while the chevron
    /// (shown only when there's at least one unassigned tag to offer)
    /// opens a menu to pick an existing one instead — see commitTagField.
    private func addTagChip(hasAssignedTags: Bool, unassigned: [Tag]) -> some View {
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
                    // Explicit icon + Text (not Label(_:systemImage:)) so
                    // the icon can't get dropped by Label's own space-
                    // constrained icon-vs-text layout choices inside this
                    // narrow a frame.
                    HStack(spacing: 3) {
                        Image(systemName: hasAssignedTags ? "plus" : "tag")
                        if !hasAssignedTags {
                            Text("Tag")
                        }
                    }
                    .font(.caption)
                    // A lone "+" (there's already at least one tag pill
                    // to its left) reads as its own small chip, matching
                    // lightGray.png; the plain "Tag" placeholder instead
                    // matches Project's boxless label.
                    .foregroundStyle(hasAssignedTags ? selectedChipTextColor : selectedMetadataLabelColor)
                    .padding(.horizontal, hasAssignedTags ? 6 : 0)
                    .padding(.vertical, hasAssignedTags ? 2 : 0)
                    .background(hasAssignedTags ? selectedChipBackground : Color.clear, in: .capsule)
                }
                .buttonStyle(.plain)
                .frame(width: hasAssignedTags ? nil : 40)
            }

            if !unassigned.isEmpty {
                Menu {
                    ForEach(unassigned) { tag in
                        Button(tag.name) {
                            Mutations.addTag(tag, to: task, in: modelContext)
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

    /// Finds an existing tag matching the typed name (case-insensitive)
    /// rather than always creating a duplicate, and only creates a new one
    /// when nothing matches — mirrors commitProjectField, except this adds
    /// to the task's tag set instead of replacing a single value.
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
        Mutations.addTag(tag, to: task, in: modelContext)
    }

    @ViewBuilder
    private var dueDateChip: some View {
        Group {
            if let due = task.dueDate {
                HStack(spacing: 3) {
                    Button {
                        showingDueDatePicker = true
                    } label: {
                        Label(due.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(dueDateTint(due, dimColor: selectedMetadataLabelColor))
                    }
                    .buttonStyle(.plain)
                    Button {
                        task.dueDate = nil
                        task.updatedAt = Date()
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
                        .font(.caption)
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
                    get: { task.dueDate ?? Date() },
                    set: { task.dueDate = $0; task.updatedAt = Date() }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            if task.dueDate != nil {
                Button("Clear") {
                    task.dueDate = nil
                    task.updatedAt = Date()
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

    // MARK: - Helpers

    private var titleBinding: Binding<String> {
        Binding(
            get: { task.title },
            set: { task.title = $0; task.updatedAt = Date() }
        )
    }

    private var checkboxTint: Color {
        if task.completed { return .secondary }
        return isOverdue ? .red : .secondary
    }

    /// Matches OmniFocus's proximity-based due-date coloring: overdue is
    /// red, due today/tomorrow is orange, anything further out is neutral.
    private func dueDateTint(_ dueDate: Date, dimColor: Color = .secondary) -> Color {
        guard !task.completed else { return dimColor }
        let calendar = Calendar.current
        if dueDate < Date() { return .red }
        if let tomorrowEnd = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: Date())),
           dueDate < tomorrowEnd {
            return .orange
        }
        return dimColor
    }
}

/// A small rounded pill for a date label, matching OmniFocus's colored
/// due/defer chips rather than plain inline text.
private struct DateChip: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: .capsule)
    }
}
