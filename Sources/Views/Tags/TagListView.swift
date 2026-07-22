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
    /// A Set binding (not a single UUID?) is what gives List its native
    /// multi-select — Cmd/Shift-click work for free, matching Finder.
    @State private var selection: Set<UUID> = []

    private var nodes: [TagNode] {
        Perspectives.tagTree(allTags: tags)
    }

    // `List(data, children:)` — the tree convenience initializer — doesn't
    // support `.onMove`, and `.dropDestination` inside a List doesn't fire on
    // macOS, so nested drag-to-reorder needs manual ForEach+DisclosureGroup
    // recursion (via TagRow, a real recursive View type — a function can't
    // return `some View` and call itself) with `.onMove` at each level. A
    // selection binding (matching TaskListView, where drag-reorder is
    // confirmed working) is also required — macOS's native list drag-reorder
    // ties into the same row-selection plumbing.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(nodes) { node in
                    TagRow(node: node, taskCount: taskCount, selection: $selection, editingTagID: $editingTagID) { tag in
                        parentForNewTag = tag
                        isAddingTag = true
                    } onDelete: { tag in
                        Mutations.deleteTag(tag, in: modelContext)
                    }
                    .listRowSeparator(.hidden)
                }
                .onMove { offsets, destination in
                    Mutations.reorder(nodes.map(\.tag), fromOffsets: offsets, toOffset: destination)
                }
            }
            .listStyle(.inset)
            .padding(.top, 12)
            .padding(.leading, -6)
            .padding(.trailing, -10)
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
    let taskCount: (Tag) -> Int
    @Binding var selection: Set<UUID>
    @Binding var editingTagID: UUID?
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
                    TagRow(node: child, taskCount: taskCount, selection: $selection, editingTagID: $editingTagID, onAddSubtag: onAddSubtag, onDelete: onDelete)
                        .listRowSeparator(.hidden)
                }
                .onMove { offsets, destination in
                    Mutations.reorder(children.map(\.tag), fromOffsets: offsets, toOffset: destination)
                }
            } label: {
                label
            }
        } else {
            label
        }
    }

    private var label: some View {
        HStack {
            Image(systemName: "tag")
                .foregroundStyle(.pink)
            if node.tag.id == editingTagID {
                AutoSelectTextField(text: nameBinding, onCommit: { editingTagID = nil })
            } else {
                EditableNameText(name: nameBinding, isSelected: selection.contains(node.tag.id))
            }
            Spacer()
            if node.tag.id != editingTagID {
                Text("\(taskCount(node.tag))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(node.tag.id)
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
