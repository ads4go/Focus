import SwiftUI
import SwiftData
import AppKit

struct TagListView: View {
    /// Called with the full selection set on every change, including back
    /// down to empty — the caller treats an empty set as "no filter, show
    /// everything" rather than "nothing to show" (see Perspective.tags).
    let onSelectionChange: (Set<UUID>) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.sortOrder)
    private var tags: [Tag]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

    @State private var isAddingTag = false
    @State private var newTagName = ""
    @State private var parentForNewTag: Tag?
    @State private var editingTagID: UUID? = nil
    /// Driven entirely by hand now (see toggleSelection) rather than List's
    /// own `selection:` binding — matches ProjectListView's own switch (see
    /// its identical doc comment): native selection tint can't be
    /// recolored *or* reshaped into a pill, so this pane draws its own.
    @State private var selection: Set<UUID> = []

    private var nodes: [TagNode] {
        Perspectives.tagTree(allTags: tags)
    }

    /// Finder-style: a plain tap replaces the selection with just this row;
    /// ⌘-click toggles this row in/out of the existing selection instead —
    /// see ProjectListView's identical helper. Shift-range-select isn't
    /// replicated.
    private func toggleSelection(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } else {
            selection = [id]
        }
    }

    // `List(data, children:)` — the tree convenience initializer — doesn't
    // support `.onMove`, and `.dropDestination` inside a List doesn't fire on
    // macOS, so nested drag-to-reorder needs manual ForEach+DisclosureGroup
    // recursion (via TagRow, a real recursive View type — a function can't
    // return `some View` and call itself). Reordering is drag-and-drop
    // (.draggable/.dropDestination in TagRow's own label) rather than
    // List's native move handles — this list no longer has a `selection:`
    // binding at all (its rows draw their own pill selection instead of
    // List's native tint — see `selection`'s own doc comment above), and
    // native reorder ties into that same selection plumbing to initiate
    // reliably.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(nodes) { node in
                    TagRow(
                        node: node,
                        siblings: nodes.map(\.tag),
                        allTags: tags,
                        taskCount: taskCount,
                        selection: $selection,
                        editingTagID: $editingTagID,
                        onSelect: toggleSelection
                    ) { tag in
                        parentForNewTag = tag
                        isAddingTag = true
                    } onDelete: { tag in
                        Mutations.deleteTag(tag, in: modelContext)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .padding(.top, 12)
            .padding(.leading, -11)
            .padding(.trailing, -15)
            .overlay {
                if tags.isEmpty && !isAddingTag {
                    ContentUnavailableView("No Tags", systemImage: "tag")
                }
            }

            // Bottom-left "+" (no header row above the list anymore) —
            // matches ProjectListView's own placement for adding a new tag.
            HStack {
                Button {
                    let tag = Tag(name: "")
                    modelContext.insert(tag)
                    editingTagID = tag.id
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .frame(width: 28)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        // See ProjectListView's identical modifier for why this is here —
        // without it, this VStack only reports its own content-hugging
        // height, leaving any blank margin below a short list genuinely
        // outside this view's own bounds (and unreachable by any gesture
        // attached in here).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A real AppKit click-catcher instead of a plain SwiftUI
        // Color+onTapGesture — see ProjectListView's identical background
        // (and its EmptyAreaClickCatcher's own doc comment) for why.
        .background {
            EmptyAreaClickCatcher { selection = [] }
        }
        .onChange(of: selection) { _, newValue in
            onSelectionChange(newValue)
        }
        .alert(
            parentForNewTag == nil ? "New Tag" : "New Subtag of \(parentForNewTag?.name ?? "")",
            isPresented: $isAddingTag
        ) {
            TextField("Tag name", text: $newTagName)
            Button("Cancel", role: .cancel) { newTagName = "" }
            Button("Add", action: commitNewTag)
        }
    }

    private func taskCount(_ tag: Tag) -> Int {
        Set(allTaskTags.filter { $0.tagID == tag.id }.map(\.taskID)).count
    }

    private func commitNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Tag(name: trimmed, parentTagID: parentForNewTag?.id))
        parentForNewTag = nil
    }
}

/// A tag row that recursively renders its own children — a real `View`
/// struct rather than a function, since a function returning `some View`
/// can't call itself (the opaque type would reference itself).
private struct TagRow: View {
    let node: TagNode
    /// This row's own siblings (same parentTagID) — used both to find
    /// where a drag-and-drop reorder lands (see Mutations.moveOrderable)
    /// and, if a dropped tag's parentTagID differs, to reparent it into
    /// this group first, matching ProjectListView's own reorder-drop.
    let siblings: [Tag]
    /// Every tag in the app, not just this row's own siblings — a dragged
    /// tag from a different parent group needs a global lookup by id.
    let allTags: [Tag]
    let taskCount: (Tag) -> Int
    @Binding var selection: Set<UUID>
    @Binding var editingTagID: UUID?
    let onSelect: (UUID) -> Void
    let onAddSubtag: (Tag) -> Void
    let onDelete: (Tag) -> Void

    private var nameBinding: Binding<String> {
        Binding(
            get: { node.tag.name },
            set: { node.tag.name = $0; node.tag.updatedAt = Date() }
        )
    }

    var body: some View {
        if let children = node.children {
            DisclosureGroup {
                ForEach(children) { child in
                    TagRow(
                        node: child,
                        siblings: children.map(\.tag),
                        allTags: allTags,
                        taskCount: taskCount,
                        selection: $selection,
                        editingTagID: $editingTagID,
                        onSelect: onSelect,
                        onAddSubtag: onAddSubtag,
                        onDelete: onDelete
                    )
                    .listRowSeparator(.hidden)
                }
            } label: {
                label
            }
        } else {
            label
        }
    }

    private var label: some View {
        let isSelected = selection.contains(node.tag.id)
        return HStack {
            // Matches ProjectListView's root-level project indent, so a
            // tag's icon+text starts at the same horizontal position a
            // project's does in the Projects left pane.
            Spacer().frame(width: 18)
            Image(systemName: "tag")
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.pink))
            if node.tag.id == editingTagID {
                AutoSelectTextField(text: nameBinding, onCommit: { editingTagID = nil })
            } else {
                EditableNameText(name: nameBinding, isSelected: isSelected)
            }
            Spacer()
            if node.tag.id != editingTagID {
                Text("\(taskCount(node.tag))")
                    .font(.caption)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.secondary))
            }
        }
        // See ProjectListView's identical padding for why this is here —
        // gives the capsule below real pill proportions instead of just
        // hugging the text tightly.
        .padding(.vertical, 3)
        // Hand-drawn pill (Capsule) instead of List's native selection tint
        // — see ProjectListView's identical background for why.
        .background {
            Capsule().fill(isSelected ? editingRowBorderColor : Color.clear)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onSelect(node.tag.id) })
        .draggable(node.tag.id.uuidString)
        // This pane's own replacement for List's native onMove — see
        // Mutations.moveOrderable's doc comment.
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let draggedID = UUID(uuidString: uuidString),
                  let dragged = allTags.first(where: { $0.id == draggedID }),
                  dragged.id != node.tag.id
            else { return false }
            if dragged.parentTagID != node.tag.parentTagID {
                dragged.parentTagID = node.tag.parentTagID
                dragged.updatedAt = Date()
            }
            Mutations.moveOrderable(dragged, beforeTarget: node.tag, in: siblings)
            return true
        }
        .contextMenu {
            Button("Add Subtag") { onAddSubtag(node.tag) }
            Button("Delete Tag", role: .destructive) { onDelete(node.tag) }
        }
    }
}

/// An NSTextField wrapper that immediately focuses and selects all text
/// when it appears — bypassing SwiftUI focus timing entirely.
private struct AutoSelectTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "Untitled Tag"
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoSelectTextField
        init(_ parent: AutoSelectTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ obj: Notification) {
            (obj.object as? NSTextField)?.currentEditor()?.selectAll(nil)
        }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }
        func controlTextDidEndEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                parent.text = trimmed.isEmpty ? "Untitled Tag" : trimmed
            }
            parent.onCommit()
        }
    }
}

/// Reaches into the List's own backing NSTableView — see ProjectListView's
/// identical type (this pane's own copy, since that one's private to its
/// file) for the full explanation of why a plain SwiftUI background can't
/// do this job.
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
            let point = recognizer.location(in: tableView)
            if tableView.row(at: point) == -1 {
                onClick()
            }
        }
    }
}
