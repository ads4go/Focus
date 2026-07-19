import Foundation
import SwiftData
import PostgREST

/// Polling-based, last-write-wins sync against Supabase Postgres. No Realtime:
/// the failure mode that matters (a laptop closed for days) has no websocket
/// to miss events on regardless, so "pull everything since the last cursor"
/// already does 100% of the correctness work — see the plan doc for the full
/// rationale. Known limitation: this is row-granularity LWW, so a genuinely
/// concurrent edit to two different fields on the same row during an offline
/// window resolves to whichever device pushes second, whole row. Acceptable
/// for a single-user, two-device personal tool.
@MainActor
enum SyncEngine {
    private static func logSyncResult<T>(
        _ label: String,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        do {
            let result = try await operation()
            print("[SYNC] \(label) succeeded")
            return result
        } catch {
            print("[SYNC] \(label) failed: \(error)")
            throw error
        }
    }

    static private(set) var isSyncing = false
    static private(set) var lastError: String?

    static func syncNow(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await pushAll(context: context)
        await pullAll(context: context)
    }

    // MARK: - Push

    static func pushAll(context: ModelContext) async {
        let cutoff = Date()
        let since = SyncCursor.lastPushedAt
        do {
            try await pushDirty(
                table: "tags", context: context,
                predicate: #Predicate<Tag> { $0.updatedAt > since }
            ) { TagDTO($0) }
            try await pushDirty(
                table: "projects", context: context,
                predicate: #Predicate<Project> { $0.updatedAt > since }
            ) { ProjectDTO($0) }
            try await pushDirty(
                table: "tasks", context: context,
                predicate: #Predicate<TaskItem> { $0.updatedAt > since }
            ) { TaskDTO($0) }
            try await pushDirty(
                table: "task_tags", context: context,
                predicate: #Predicate<TaskTag> { $0.updatedAt > since }
            ) { TaskTagDTO($0) }
            SyncCursor.lastPushedAt = cutoff
            lastError = nil
        } catch {
            lastError = "Push failed: \(error.localizedDescription)"
        }
    }

    private static func pushDirty<Model: PersistentModel, DTO: Encodable>(
        table: String,
        context: ModelContext,
        predicate: Predicate<Model>,
        toDTO: (Model) -> DTO
    ) async throws {
        let rows = try context.fetch(FetchDescriptor<Model>(predicate: predicate))
        guard !rows.isEmpty else { return }
        let dtos = rows.map(toDTO)
        let _ = try await logSyncResult("upsert \(table)") {
            try await SupabaseServices.postgrest
                .from(table)
                .upsert(dtos, onConflict: "id")
                .execute()
        }
    }

    // MARK: - Pull

    static func pullAll(context: ModelContext) async {
        let since = SyncCursor.lastPulledAt
        do {
            let tags: [TagDTO] = try await fetchPage(table: "tags", since: since)
            let projects: [ProjectDTO] = try await fetchPage(table: "projects", since: since)
            let tasks: [TaskDTO] = try await fetchPage(table: "tasks", since: since)
            let taskTags: [TaskTagDTO] = try await fetchPage(table: "task_tags", since: since)

            for dto in tags { upsertTag(dto, context: context) }
            for dto in projects { upsertProject(dto, context: context) }
            for dto in tasks { upsertTask(dto, context: context) }
            for dto in taskTags { upsertTaskTag(dto, context: context) }

            let maxUpdatedAt = (tags.map(\.updatedAt) + projects.map(\.updatedAt)
                + tasks.map(\.updatedAt) + taskTags.map(\.updatedAt)).max()
            if let maxUpdatedAt {
                SyncCursor.lastPulledAt = maxUpdatedAt
            }
            lastError = nil
        } catch {
            lastError = "Pull failed: \(error.localizedDescription)"
        }
    }

    private static func fetchPage<DTO: Decodable>(table: String, since: Date) async throws -> [DTO] {
        var results: [DTO] = []
        var offset = 0
        let pageSize = 1000
        while true {
            let page: [DTO] = try await logSyncResult("fetch \(table) page offset=\(offset)") {
                try await SupabaseServices.postgrest
                    .from(table)
                    .select()
                    .gte("updated_at", value: since)
                    .order("updated_at", ascending: true)
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value
            }
            results.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }
        return results
    }

    // Remote wins only if strictly newer than the local row — otherwise the
    // local copy is either already pushed or about to be, so leave it alone.

    private static func upsertTag(_ dto: TagDTO, context: ModelContext) {
        let dtoID = dto.id
        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == dtoID })
        if let existing = try? context.fetch(descriptor).first {
            guard dto.updatedAt > existing.updatedAt else { return }
            existing.name = dto.name
            existing.colorHex = dto.colorHex
            existing.parentTagID = dto.parentTagID
            existing.sortOrder = dto.sortOrder
            existing.updatedAt = dto.updatedAt
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(Tag(
                id: dto.id, name: dto.name, colorHex: dto.colorHex, parentTagID: dto.parentTagID,
                sortOrder: dto.sortOrder,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            ))
        }
    }

    private static func upsertProject(_ dto: ProjectDTO, context: ModelContext) {
        let dtoID = dto.id
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == dtoID })
        if let existing = try? context.fetch(descriptor).first {
            guard dto.updatedAt > existing.updatedAt else { return }
            existing.name = dto.name
            existing.notes = dto.notes
            existing.isCompleted = dto.isCompleted
            existing.sortOrder = dto.sortOrder
            existing.reviewIntervalDays = dto.reviewIntervalDays
            existing.lastReviewedAt = dto.lastReviewedAt
            existing.updatedAt = dto.updatedAt
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(Project(
                id: dto.id, name: dto.name, notes: dto.notes, isCompleted: dto.isCompleted,
                sortOrder: dto.sortOrder,
                reviewIntervalDays: dto.reviewIntervalDays, lastReviewedAt: dto.lastReviewedAt,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            ))
        }
    }

    private static func upsertTask(_ dto: TaskDTO, context: ModelContext) {
        let dtoID = dto.id
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == dtoID })
        if let existing = try? context.fetch(descriptor).first {
            guard dto.updatedAt > existing.updatedAt else { return }
            existing.title = dto.title
            existing.notes = dto.notes
            existing.projectID = dto.projectID
            existing.parentTaskID = dto.parentTaskID
            existing.dueDate = dto.dueDate
            existing.deferDate = dto.deferDate
            existing.flagged = dto.flagged
            existing.completed = dto.completed
            existing.completedAt = dto.completedAt
            existing.sortOrder = dto.sortOrder
            existing.updatedAt = dto.updatedAt
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(TaskItem(
                id: dto.id, title: dto.title, notes: dto.notes, projectID: dto.projectID,
                parentTaskID: dto.parentTaskID,
                dueDate: dto.dueDate, deferDate: dto.deferDate, flagged: dto.flagged,
                completed: dto.completed, completedAt: dto.completedAt, sortOrder: dto.sortOrder,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            ))
        }
    }

    private static func upsertTaskTag(_ dto: TaskTagDTO, context: ModelContext) {
        let dtoID = dto.id
        let descriptor = FetchDescriptor<TaskTag>(predicate: #Predicate { $0.id == dtoID })
        if let existing = try? context.fetch(descriptor).first {
            guard dto.updatedAt > existing.updatedAt else { return }
            existing.taskID = dto.taskID
            existing.tagID = dto.tagID
            existing.updatedAt = dto.updatedAt
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(TaskTag(
                id: dto.id, taskID: dto.taskID, tagID: dto.tagID,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            ))
        }
    }
}
