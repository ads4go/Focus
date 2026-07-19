import Foundation
import SwiftData

/// A model with a manually draggable position. `sortOrder` uses fractional
/// indexing (see `Mutations.reorder`) so a drag only touches the moved row —
/// nothing else in the list needs renumbering.
protocol Orderable: AnyObject {
    var sortOrder: Int { get set }
    var updatedAt: Date { get set }
}
extension TaskItem: Orderable {}
extension Project: Orderable {}
extension Tag: Orderable {}

/// Every mutation to a synced model funnels through here so `updatedAt` is
/// always stamped and deletes are always soft (see Sources/Sync/SyncEngine.swift
/// for why: a hard local delete would erase a row before it's ever pushed as
/// a tombstone, so the other device would never learn it was deleted).
enum Mutations {
    /// Repositions the item(s) at `offsets` to `destination` within
    /// `siblings` (which must be pre-sorted by `sortOrder` and share the same
    /// grouping, e.g. the same parentTaskID/parentTagID) — the `Array.move`
    /// semantics `List.onMove` hands back. Only the moved row's `sortOrder`
    /// changes (fractional indexing), never its neighbors'.
    static func reorder<T: Orderable>(_ siblings: [T], fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard let sourceIndex = offsets.first else { return }
        let dragged = siblings[sourceIndex]
        var reordered = siblings
        reordered.move(fromOffsets: offsets, toOffset: destination)
        guard let newIndex = reordered.firstIndex(where: { $0 === dragged }) else { return }
        let before = newIndex > 0 ? reordered[newIndex - 1].sortOrder : nil
        let after = newIndex < reordered.count - 1 ? reordered[newIndex + 1].sortOrder : nil
        switch (before, after) {
        case let (b?, a?):
            // Keep strict ordering when neighbors are adjacent.
            let midpoint = b + (a - b) / 2
            dragged.sortOrder = midpoint == b ? b + 1 : midpoint
        case let (b?, nil): dragged.sortOrder = b + 1
        case let (nil, a?): dragged.sortOrder = a - 1
        default: break
        }
        dragged.updatedAt = Date()
    }


    static func toggleCompleted(_ task: TaskItem, in context: ModelContext) {
        setCompleted(task, !task.completed, in: context)
    }

    /// Cascades to every subtask so completing (or reopening) a parent always
    /// checks/strikes through its whole subtask tree, not just the one row.
    static func setCompleted(_ task: TaskItem, _ completed: Bool, in context: ModelContext) {
        task.completed = completed
        task.completedAt = completed ? Date() : nil
        task.updatedAt = Date()

        let taskID = task.id
        let childDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.parentTaskID == taskID && $0.deletedAt == nil }
        )
        if let children = try? context.fetch(childDescriptor) {
            for child in children where child.completed != completed {
                setCompleted(child, completed, in: context)
            }
        }
    }

    static func deleteTask(_ task: TaskItem, in context: ModelContext) {
        let now = Date()
        task.deletedAt = now
        task.updatedAt = now

        let taskID = task.id
        let tagDescriptor = FetchDescriptor<TaskTag>(
            predicate: #Predicate { $0.taskID == taskID && $0.deletedAt == nil }
        )
        if let joins = try? context.fetch(tagDescriptor) {
            for join in joins {
                join.deletedAt = now
                join.updatedAt = now
            }
        }

        let childDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.parentTaskID == taskID && $0.deletedAt == nil }
        )
        if let children = try? context.fetch(childDescriptor) {
            for child in children {
                deleteTask(child, in: context)
            }
        }
    }

    static func deleteProject(_ project: Project, in context: ModelContext) {
        let now = Date()
        project.deletedAt = now
        project.updatedAt = now

        let projectID = project.id
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.projectID == projectID && $0.deletedAt == nil }
        )
        if let tasks = try? context.fetch(descriptor) {
            for task in tasks {
                deleteTask(task, in: context)
            }
        }
    }

    static func deleteTag(_ tag: Tag, in context: ModelContext) {
        let now = Date()
        tag.deletedAt = now
        tag.updatedAt = now

        let tagID = tag.id
        let joinDescriptor = FetchDescriptor<TaskTag>(
            predicate: #Predicate { $0.tagID == tagID && $0.deletedAt == nil }
        )
        if let joins = try? context.fetch(joinDescriptor) {
            for join in joins {
                join.deletedAt = now
                join.updatedAt = now
            }
        }

        let childDescriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.parentTagID == tagID && $0.deletedAt == nil }
        )
        if let children = try? context.fetch(childDescriptor) {
            for child in children {
                deleteTag(child, in: context)
            }
        }
    }

    static func duplicateTask(_ task: TaskItem, in context: ModelContext) {
        let copy = TaskItem(
            title: task.title,
            notes: task.notes,
            projectID: task.projectID,
            parentTaskID: task.parentTaskID,
            dueDate: task.dueDate,
            deferDate: task.deferDate,
            flagged: task.flagged
        )
        context.insert(copy)

        let taskID = task.id
        let descriptor = FetchDescriptor<TaskTag>(
            predicate: #Predicate { $0.taskID == taskID && $0.deletedAt == nil }
        )
        if let joins = try? context.fetch(descriptor) {
            for join in joins {
                context.insert(TaskTag(taskID: copy.id, tagID: join.tagID))
            }
        }
    }

    static func addTag(_ tag: Tag, to task: TaskItem, in context: ModelContext) {
        let taskID = task.id
        let tagID = tag.id
        let descriptor = FetchDescriptor<TaskTag>(
            predicate: #Predicate { $0.taskID == taskID && $0.tagID == tagID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if existing.deletedAt != nil {
                existing.deletedAt = nil
                existing.updatedAt = Date()
            }
            return
        }
        context.insert(TaskTag(taskID: taskID, tagID: tagID))
    }

    static func removeTag(_ tag: Tag, from task: TaskItem, in context: ModelContext) {
        let taskID = task.id
        let tagID = tag.id
        let descriptor = FetchDescriptor<TaskTag>(
            predicate: #Predicate { $0.taskID == taskID && $0.tagID == tagID && $0.deletedAt == nil }
        )
        if let existing = try? context.fetch(descriptor).first {
            let now = Date()
            existing.deletedAt = now
            existing.updatedAt = now
        }
    }
}
