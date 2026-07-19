import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    var isCompleted: Bool
    var sortOrder: Int = 0
    /// nil = no review cadence ("Never"). Both are Optional so — unlike
    /// sortOrder — no declaration-level default is needed for existing rows
    /// to migrate cleanly; SwiftData backfills Optionals as nil for free.
    var reviewIntervalDays: Int?
    var lastReviewedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        isCompleted: Bool = false,
        sortOrder: Int = Int(Date().timeIntervalSince1970),
        reviewIntervalDays: Int? = 7,
        lastReviewedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.reviewIntervalDays = reviewIntervalDays
        self.lastReviewedAt = lastReviewedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// nil when there's no cadence set ("Never"). A never-reviewed project
    /// is due immediately once a cadence is set — GTD practice is "review
    /// this soon since you haven't yet," not "wait out a full interval from
    /// creation."
    var nextReviewDate: Date? {
        guard let reviewIntervalDays else { return nil }
        guard let lastReviewedAt else { return .distantPast }
        return Calendar.current.date(byAdding: .day, value: reviewIntervalDays, to: lastReviewedAt)
    }

    var isDueForReview: Bool {
        guard let nextReviewDate else { return false }
        return nextReviewDate <= Date()
    }
}
