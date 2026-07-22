import SwiftUI
import SwiftData

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
                    TagRow(node: node, taskCount: taskCount) { tag in
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
                    parentForNewTag = nil
                    isAddingTag = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Tag")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
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
    let onAddSubtag: (Tag) -> Void
    let onDelete: (Tag) -> Void

    var body: some View {
        if let children = node.children {
            DisclosureGroup {
                ForEach(children) { child in
                    TagRow(node: child, taskCount: taskCount, onAddSubtag: onAddSubtag, onDelete: onDelete)
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
            Text(node.tag.name)
            Spacer()
            Text("\(taskCount(node.tag))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(node.tag.id)
        .contextMenu {
            Button("Add Subtag") { onAddSubtag(node.tag) }
            Button("Delete Tag", role: .destructive) { onDelete(node.tag) }
        }
    }
}
