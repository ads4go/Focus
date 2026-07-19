import Foundation

enum Perspective: Hashable {
    case inbox
    case flagged
    case projects
    case project(UUID)
    case tag(UUID)
}

/// A task paired with its subtasks, for feeding SwiftUI's `List(_:children:)` —
/// that API gives disclosure triangles and indentation for free once data is
/// shaped as a tree, so this is the only tree-building this feature needs.
struct TaskNode: Identifiable {
    let task: TaskItem
    let children: [TaskNode]?
    var id: UUID { task.id }
}

/// A tag paired with its child tags, for the same `List(_:children:)` tree
/// display — mirrors TaskNode's shape for nested tag folders (e.g. "Errands"
/// containing "Supermarket", "Hardware Store").
struct TagNode: Identifiable {
    let tag: Tag
    let children: [TagNode]?
    var id: UUID { tag.id }
}

enum Perspectives {
    /// Root tasks matching `perspective`, each with its full subtask tree
    /// attached regardless of whether the subtasks themselves match the
    /// perspective's own criteria — e.g. all of a flagged task's subtasks
    /// show nested under it in the Flagged perspective, not just the ones
    /// that are individually flagged. A subtask nested under a task that
    /// doesn't itself match the perspective won't appear at all; that's an
    /// accepted gap rather than something worth a flattening/promotion pass.
    static func taskTree(for perspective: Perspective, allTasks: [TaskItem], allTaskTags: [TaskTag]) -> [TaskNode] {
        let roots = tasks(for: perspective, allTasks: allTasks, allTaskTags: allTaskTags)
            .filter { $0.parentTaskID == nil }
        return roots.map { node(for: $0, allTasks: allTasks) }
    }

    private static func node(for task: TaskItem, allTasks: [TaskItem]) -> TaskNode {
        let children = allTasks
            .filter { $0.parentTaskID == task.id }
            .sorted(by: taskSortOrder)
            .map { node(for: $0, allTasks: allTasks) }
        return TaskNode(task: task, children: children.isEmpty ? nil : children)
    }

    static func tasks(for perspective: Perspective, allTasks: [TaskItem], allTaskTags: [TaskTag]) -> [TaskItem] {
        let filtered: [TaskItem]
        switch perspective {
        case .inbox:
            filtered = allTasks.filter { $0.projectID == nil && !$0.completed }
        case .flagged:
            filtered = allTasks.filter { $0.flagged && !$0.completed }
        case .projects:
            filtered = []
        case .project(let projectID):
            filtered = allTasks.filter { $0.projectID == projectID }
        case .tag(let tagID):
            let taskIDs = Set(allTaskTags.filter { $0.tagID == tagID }.map(\.taskID))
            filtered = allTasks.filter { taskIDs.contains($0.id) }
        }
        return filtered.sorted(by: taskSortOrder)
    }

    static func tags(for task: TaskItem, allTags: [Tag], allTaskTags: [TaskTag]) -> [Tag] {
        let tagIDs = Set(allTaskTags.filter { $0.taskID == task.id }.map(\.tagID))
        return allTags.filter { tagIDs.contains($0.id) }
    }

    /// Root tags (no parent) with their full child-tag subtree attached.
    static func tagTree(allTags: [Tag]) -> [TagNode] {
        let roots = allTags
            .filter { $0.parentTagID == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        return roots.map { tagNode(for: $0, allTags: allTags) }
    }

    private static func tagNode(for tag: Tag, allTags: [Tag]) -> TagNode {
        let children = allTags
            .filter { $0.parentTagID == tag.id }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { tagNode(for: $0, allTags: allTags) }
        return TagNode(tag: tag, children: children.isEmpty ? nil : children)
    }

    /// Completed tasks sort after incomplete ones; within each group, manual
    /// drag-to-reorder position (`sortOrder`) decides the order.
    private static func taskSortOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.completed != rhs.completed {
            return !lhs.completed && rhs.completed
        }
        return lhs.sortOrder < rhs.sortOrder
    }
}
