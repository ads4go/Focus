import Foundation

enum Perspective: Hashable {
    case inbox
    /// tagIDs filters which flagged tasks show; empty means no filter (all
    /// flagged tasks) — matches OmniFocus, where its left pane narrows the
    /// middle pane rather than requiring a selection to show anything.
    case flagged(tagIDs: Set<UUID> = [])
    /// projectIDs filters which tasks show; empty means no filter (every
    /// task that has a project, across all of them). A single-element set
    /// is also how Review's one-at-a-time paging is expressed.
    case projects(Set<UUID> = [])
    /// tagIDs filters which tasks show; empty means no filter (every task
    /// that has at least one tag).
    case tags(Set<UUID> = [])
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
    static func taskTree(for perspective: Perspective, allTasks: [TaskItem], allTaskTags: [TaskTag], pinnedIDs: Set<UUID> = []) -> [TaskNode] {
        let roots = tasks(for: perspective, allTasks: allTasks, allTaskTags: allTaskTags, pinnedIDs: pinnedIDs)
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

    static func tasks(for perspective: Perspective, allTasks: [TaskItem], allTaskTags: [TaskTag], pinnedIDs: Set<UUID> = []) -> [TaskItem] {
        let filtered: [TaskItem]
        switch perspective {
        case .inbox:
            filtered = allTasks.filter { ($0.projectID == nil && !$0.completed) || pinnedIDs.contains($0.id) }
        case .flagged(let tagIDs):
            let base = allTasks.filter { ($0.flagged && !$0.completed) || pinnedIDs.contains($0.id) }
            filtered = tagIDs.isEmpty ? base : filterByTags(base, tagIDs: tagIDs, allTaskTags: allTaskTags)
        case .projects(let projectIDs):
            if projectIDs.isEmpty {
                filtered = allTasks.filter { $0.projectID != nil }
            } else {
                filtered = allTasks.filter { $0.projectID.map(projectIDs.contains) ?? false }
            }
        case .tags(let tagIDs):
            if tagIDs.isEmpty {
                let taggedTaskIDs = Set(allTaskTags.map(\.taskID))
                filtered = allTasks.filter { taggedTaskIDs.contains($0.id) }
            } else {
                filtered = filterByTags(allTasks, tagIDs: tagIDs, allTaskTags: allTaskTags)
            }
        }
        return filtered.sorted(by: taskSortOrder)
    }

    static func tags(for task: TaskItem, allTags: [Tag], allTaskTags: [TaskTag]) -> [Tag] {
        let tagIDs = Set(allTaskTags.filter { $0.taskID == task.id }.map(\.tagID))
        return allTags.filter { tagIDs.contains($0.id) }
    }

    /// Tasks carrying at least one of tagIDs — shared by both .flagged and
    /// .tags, whose only difference is what they filter *before* this.
    private static func filterByTags(_ tasks: [TaskItem], tagIDs: Set<UUID>, allTaskTags: [TaskTag]) -> [TaskItem] {
        let matchingTaskIDs = Set(allTaskTags.filter { tagIDs.contains($0.tagID) }.map(\.taskID))
        return tasks.filter { matchingTaskIDs.contains($0.id) }
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

    private static func taskSortOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        return lhs.sortOrder < rhs.sortOrder
    }
}
