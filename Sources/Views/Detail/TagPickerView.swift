import SwiftUI
import SwiftData

/// Assigned tags as removable chips in a wrapping row, plus a "+" menu to
/// add more — matches OmniFocus's Tags inspector section rather than a
/// plain on/off toggle list.
struct TagPickerView: View {
    let task: TaskItem
    let allTags: [Tag]
    let allTaskTags: [TaskTag]

    @Environment(\.modelContext) private var modelContext

    private var assignedTagIDs: Set<UUID> {
        Set(allTaskTags.filter { $0.taskID == task.id }.map(\.tagID))
    }

    private var assignedTags: [Tag] {
        allTags.filter { assignedTagIDs.contains($0.id) }
    }

    private var unassignedTags: [Tag] {
        allTags.filter { !assignedTagIDs.contains($0.id) }
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(assignedTags) { tag in
                TagChip(name: tag.name) {
                    Mutations.removeTag(tag, from: task, in: modelContext)
                }
            }
            addButton
        }
        if allTags.isEmpty {
            Text("No tags yet — add one from the sidebar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if !unassignedTags.isEmpty {
            Menu {
                ForEach(unassignedTags) { tag in
                    Button(tag.name) {
                        Mutations.addTag(tag, to: task, in: modelContext)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.secondary.opacity(0.15), in: .circle)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct TagChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption.weight(.medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.pink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.pink.opacity(0.15), in: .capsule)
    }
}

/// Minimal wrapping HStack — SwiftUI has no built-in flow layout, and this
/// view is the only place Focus needs one.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
