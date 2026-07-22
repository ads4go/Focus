import Foundation
import SwiftData

/// Explicit join row for the project<->tag many-to-many relationship,
/// mirroring TaskTag so projects can carry tags with the same soft-delete
/// sync semantics.
@Model
final class ProjectTag {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var tagID: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        tagID: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.tagID = tagID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
