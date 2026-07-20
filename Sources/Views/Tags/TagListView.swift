import SwiftUI
import SwiftData

struct TagListView: View {
    let onSelectTag: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.sortOrder)
    private var tags: [Tag]
    @Query(filter: #Predicate<TaskTag> { $0.deletedAt == nil })
    private var allTaskTags: [TaskTag]

    @State private var isAddingTag = false
    @State private var newTagName = ""
    @State private var parentForNewTag: Tag?
    @State private var selection: UUID?

    private var nodes: [TagNode] {
        Perspectives.tagTree(allTags: tags)
    }

    private var itemCountLabel: String {
        "\(tags.count) tag\(tags.count == 1 ? "" : "s")"
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
            Text("TEMP MARKER: TAG LIST VIEW")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.pink, in: Capsule())
                .padding(.horizontal)
                .padding(.top, 8)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tags")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.pink)
                    Text(itemCountLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    parentForNewTag = nil
                    isAddingTag = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Tag")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)

            List(selection: $selection) {
                ForEach(nodes) { node in
                    TagRow(node: node, taskCount: taskCount) { tag in
                        parentForNewTag = tag
                        isAddingTag = true
                    } onDelete: { tag in
                        Mutations.deleteTag(tag, in: modelContext)
                    }
                }
                .onMove { offsets, destination in
                    Mutations.reorder(nodes.map(\.tag), fromOffsets: offsets, toOffset: destination)
                }
            }
            .listStyle(.inset)
            .overlay {
                if tags.isEmpty && !isAddingTag {
                    ContentUnavailableView("No Tags", systemImage: "tag")
                }
            }
        }
        .navigationTitle("Tags")
        .onChange(of: selection) { _, newValue in
            if let newValue {
                onSelectTag(newValue)
            }
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
                .foregroundStyle(.secondary)
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
