import Foundation
import SwiftData

/// Explicit join row for the task<->tag many-to-many relationship.
/// Kept as its own syncable row (rather than an array field on TaskItem) so a
/// tag add on one device and a tag removal on another don't clobber each
/// other under row-level last-write-wins sync — see Sources/Sync/SyncEngine.swift.
@Model
final class TaskTag {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var tagID: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        tagID: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.tagID = tagID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
