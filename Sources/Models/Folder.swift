import Foundation
import SwiftData

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int = 0
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = Int(Date().timeIntervalSince1970),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
