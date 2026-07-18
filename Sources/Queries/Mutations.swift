import Foundation
import SwiftData

/// Every mutation to a synced model funnels through here so `updatedAt` is
/// always stamped and deletes are always soft (see Sources/Sync/SyncEngine.swift
/// for why: a hard local delete would erase a row before it's ever pushed as
/// a tombstone, so the other device would never learn it was deleted).
enum Mutations {
    static func toggleCompleted(_ task: TaskItem) {
        setCompleted(task, !task.completed)
    }

    static func setCompleted(_ task: TaskItem, _ completed: Bool) {
        task.completed = completed
        task.completedAt = completed ? Date() : nil
        task.updatedAt = Date()
    }

    static func deleteTask(_ task: TaskItem, in context: ModelContext) {
        let now = Date()
        task.deletedAt = now
        task.updatedAt = now

        let taskID = task.id
        let descriptor = FetchDescriptor<TaskTag>(
            predicate: #Predicate { $0.taskID == taskID && $0.deletedAt == nil }
        )
        if let joins = try? context.fetch(descriptor) {
            for join in joins {
                join.deletedAt = now
                join.updatedAt = now
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
        let descriptor = FetchDescriptor<TaskTag>(
            predicate: #Predicate { $0.tagID == tagID && $0.deletedAt == nil }
        )
        if let joins = try? context.fetch(descriptor) {
            for join in joins {
                join.deletedAt = now
                join.updatedAt = now
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
