import Foundation

// Codable wire types mirroring the Postgres tables (see README's schema SQL).
// `owner_id` is deliberately absent: on push it's left to the column default
// (`auth.uid()`) or left untouched on conflict-update; on pull we don't need
// it locally since every local row belongs to the one signed-in user.

struct TagDTO: Codable {
    let id: UUID
    var name: String
    var colorHex: String?
    var parentTagID: UUID?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color_hex"
        case parentTagID = "parent_tag_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ tag: Tag) {
        id = tag.id
        name = tag.name
        colorHex = tag.colorHex
        parentTagID = tag.parentTagID
        sortOrder = tag.sortOrder
        createdAt = tag.createdAt
        updatedAt = tag.updatedAt
        deletedAt = tag.deletedAt
    }

    // Synthesized Encodable would use encodeIfPresent for the Optional
    // fields below, which OMITS the key entirely when nil rather than
    // sending an explicit null — PostgREST's upsert only touches columns
    // actually present in the payload, so clearing colorHex/parentTagID
    // locally would silently never reach the server. Plain encode(_:forKey:)
    // (Optional's own Encodable conformance) sends null instead of omitting.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(parentTagID, forKey: .parentTagID)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

struct FolderDTO: Codable {
    let id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ folder: Folder) {
        id = folder.id
        name = folder.name
        sortOrder = folder.sortOrder
        createdAt = folder.createdAt
        updatedAt = folder.updatedAt
        deletedAt = folder.deletedAt
    }
}

struct ProjectDTO: Codable {
    let id: UUID
    var name: String
    var notes: String
    var isCompleted: Bool
    var flagged: Bool
    var dueDate: Date?
    var deferDate: Date?
    var folderID: UUID?
    var sortOrder: Int
    var reviewIntervalDays: Int?
    var lastReviewedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, notes, flagged
        case isCompleted = "is_completed"
        case dueDate = "due_date"
        case deferDate = "defer_date"
        case folderID = "folder_id"
        case sortOrder = "sort_order"
        case reviewIntervalDays = "review_interval_days"
        case lastReviewedAt = "last_reviewed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ project: Project) {
        id = project.id
        name = project.name
        notes = project.notes
        isCompleted = project.isCompleted
        flagged = project.flagged
        dueDate = project.dueDate
        deferDate = project.deferDate
        folderID = project.folderID
        sortOrder = project.sortOrder
        reviewIntervalDays = project.reviewIntervalDays
        lastReviewedAt = project.lastReviewedAt
        createdAt = project.createdAt
        updatedAt = project.updatedAt
        deletedAt = project.deletedAt
    }

    // See TagDTO's identical override for why: synthesized Encodable would
    // omit dueDate/deferDate/folderID/reviewIntervalDays/lastReviewedAt
    // entirely when nil instead of sending null, so clearing a due date
    // (or moving a project out of a folder, etc.) would silently never
    // reach the server.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(notes, forKey: .notes)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(flagged, forKey: .flagged)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(deferDate, forKey: .deferDate)
        try container.encode(folderID, forKey: .folderID)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(reviewIntervalDays, forKey: .reviewIntervalDays)
        try container.encode(lastReviewedAt, forKey: .lastReviewedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

struct TaskDTO: Codable {
    let id: UUID
    var projectID: UUID?
    var parentTaskID: UUID?
    var title: String
    var notes: String
    var dueDate: Date?
    var deferDate: Date?
    var flagged: Bool
    var completed: Bool
    var completedAt: Date?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, flagged, completed
        case projectID = "project_id"
        case parentTaskID = "parent_task_id"
        case dueDate = "due_date"
        case deferDate = "defer_date"
        case completedAt = "completed_at"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ task: TaskItem) {
        id = task.id
        projectID = task.projectID
        parentTaskID = task.parentTaskID
        title = task.title
        notes = task.notes
        dueDate = task.dueDate
        deferDate = task.deferDate
        flagged = task.flagged
        completed = task.completed
        completedAt = task.completedAt
        sortOrder = task.sortOrder
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        deletedAt = task.deletedAt
    }

    // See TagDTO's identical override for why: synthesized Encodable would
    // omit projectID/parentTaskID/dueDate/deferDate/completedAt entirely
    // when nil instead of sending null, so clearing a due date, moving a
    // task to the inbox, un-completing it, etc. would silently never reach
    // the server.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(parentTaskID, forKey: .parentTaskID)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(deferDate, forKey: .deferDate)
        try container.encode(flagged, forKey: .flagged)
        try container.encode(completed, forKey: .completed)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

struct ProjectTagDTO: Codable {
    let id: UUID
    var projectID: UUID
    var tagID: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case tagID = "tag_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ projectTag: ProjectTag) {
        id = projectTag.id
        projectID = projectTag.projectID
        tagID = projectTag.tagID
        createdAt = projectTag.createdAt
        updatedAt = projectTag.updatedAt
        deletedAt = projectTag.deletedAt
    }
}

struct ProjectShareDTO: Codable {
    let id: UUID
    var projectID: UUID
    var sharedWithUserID: UUID
    var sharedWithUsername: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case sharedWithUserID = "shared_with_user_id"
        case sharedWithUsername = "shared_with_username"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ projectShare: ProjectShare) {
        id = projectShare.id
        projectID = projectShare.projectID
        sharedWithUserID = projectShare.sharedWithUserID
        sharedWithUsername = projectShare.sharedWithUsername
        createdAt = projectShare.createdAt
        updatedAt = projectShare.updatedAt
        deletedAt = projectShare.deletedAt
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
