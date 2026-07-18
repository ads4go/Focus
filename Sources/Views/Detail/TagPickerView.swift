import SwiftUI
import SwiftData

struct TagPickerView: View {
    let task: TaskItem
    let allTags: [Tag]
    let allTaskTags: [TaskTag]

    @Environment(\.modelContext) private var modelContext

    private var assignedTagIDs: Set<UUID> {
        Set(allTaskTags.filter { $0.taskID == task.id }.map(\.tagID))
    }

    var body: some View {
        if allTags.isEmpty {
            Text("No tags yet — add one from the sidebar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(allTags) { tag in
                Toggle(tag.name, isOn: binding(for: tag))
            }
        }
    }

    private func binding(for tag: Tag) -> Binding<Bool> {
        Binding(
            get: { assignedTagIDs.contains(tag.id) },
            set: { isOn in
                if isOn {
                    Mutations.addTag(tag, to: task, in: modelContext)
                } else {
                    Mutations.removeTag(tag, from: task, in: modelContext)
                }
            }
        )
    }
}
