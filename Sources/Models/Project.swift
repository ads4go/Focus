import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
