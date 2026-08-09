import Foundation
import SwiftData

/// A grant of read/write access to a project (and its tasks) for another
/// authenticated user, mirroring ProjectTag's join-row shape with the same
/// soft-delete sync semantics. `sharedWithUserID` is the Supabase auth user
/// id being granted access — the owning user is implicit server-side via
/// `owner_id`/RLS, same as every other synced table. `sharedWithUsername`
/// is denormalized at share time (the owner already knows the username
/// they typed) purely so the UI can display "Shared with: X" without a
/// second, reverse id->username lookup — profiles' own RLS only lets a
/// user read their own row, so there's no other cheap way to resolve it.
@Model
final class ProjectShare {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var sharedWithUserID: UUID
    var sharedWithUsername: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        sharedWithUserID: UUID,
        sharedWithUsername: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.sharedWithUserID = sharedWithUserID
        self.sharedWithUsername = sharedWithUsername
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
