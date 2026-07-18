import Foundation

// Codable wire types mirroring the Postgres tables (see README's schema SQL).
// `owner_id` is deliberately absent: on push it's left to the column default
// (`auth.uid()`) or left untouched on conflict-update; on pull we don't need
// it locally since every local row belongs to the one signed-in user.

struct TagDTO: Codable {
    let id: UUID
    var name: String
    var colorHex: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color_hex"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ tag: Tag) {
        id = tag.id
        name = tag.name
        colorHex = tag.colorHex
        createdAt = tag.createdAt
        updatedAt = tag.updatedAt
        deletedAt = tag.deletedAt
    }
}

struct ProjectDTO: Codable {
    let id: UUID
    var name: String
    var notes: String
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case isCompleted = "is_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ project: Project) {
        id = project.id
        name = project.name
        notes = project.notes
        isCompleted = project.isCompleted
        createdAt = project.createdAt
        updatedAt = project.updatedAt
        deletedAt = project.deletedAt
    }
}

struct TaskDTO: Codable {
    let id: UUID
    var projectID: UUID?
    var title: String
    var notes: String
    var dueDate: Date?
    var deferDate: Date?
    var flagged: Bool
    var completed: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, flagged, completed
        case projectID = "project_id"
        case dueDate = "due_date"
        case deferDate = "defer_date"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ task: TaskItem) {
        id = task.id
        projectID = task.projectID
        title = task.title
        notes = task.notes
        dueDate = task.dueDate
        deferDate = task.deferDate
        flagged = task.flagged
        completed = task.completed
        completedAt = task.completedAt
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        deletedAt = task.deletedAt
    }
}

struct TaskTagDTO: Codable {
    let id: UUID
    var taskID: UUID
    var tagID: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case tagID = "tag_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ taskTag: TaskTag) {
        id = taskTag.id
        taskID = taskTag.taskID
        tagID = taskTag.tagID
        createdAt = taskTag.createdAt
        updatedAt = taskTag.updatedAt
        deletedAt = taskTag.deletedAt
    }
}
