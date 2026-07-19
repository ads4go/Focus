import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var projectID: UUID?
    var parentTaskID: UUID?
    var dueDate: Date?
    var deferDate: Date?
    var flagged: Bool
    var completed: Bool
    var completedAt: Date?
    var sortOrder: Double = 0
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        projectID: UUID? = nil,
        parentTaskID: UUID? = nil,
        dueDate: Date? = nil,
        deferDate: Date? = nil,
        flagged: Bool = false,
        completed: Bool = false,
        completedAt: Date? = nil,
        sortOrder: Double = Date().timeIntervalSince1970,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.projectID = projectID
        self.parentTaskID = parentTaskID
        self.dueDate = dueDate
        self.deferDate = deferDate
        self.flagged = flagged
        self.completed = completed
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
