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

    /// Wipes every synced model locally and resets both cursors to
    /// `.distantPast`, so the next sign-in does a full fresh pull instead of
    /// resuming from wherever this device's cursors happened to be — signing
    /// out only ends the Supabase session (see AuthSessionStore.signOut),
    /// it was never responsible for local data hygiene, so callers that want
    /// a clean slate (e.g. a "Log Out" action, as opposed to switching
    /// accounts on the same signed-in-forever laptop) need to call this
    /// explicitly first. Without it, signing back in (even as a different
    /// user) just resumes the previous session's stale local store and
    /// stale cursors, so any divergence from Supabase silently persists
    /// instead of being resolved by a fresh pull.
    static func resetLocalData(context: ModelContext) {
        try? context.delete(model: TaskTag.self)
        try? context.delete(model: ProjectTag.self)
        try? context.delete(model: ProjectShare.self)
        try? context.delete(model: TaskItem.self)
        try? context.delete(model: Project.self)
        try? context.delete(model: Tag.self)
        try? context.delete(model: Folder.self)
        try? context.save()
        SyncCursor.lastPulledAt = .distantPast
        SyncCursor.lastPushedAt = .distantPast
    }

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
        print("[SYNC] pushing everything with updatedAt > \(since) (raw: \(since.timeIntervalSinceReferenceDate))")
        // Soft-deletes any TaskTag/ProjectTag whose referenced tag/task/
        // project no longer exists locally, for local data hygiene (a task
        // showing a "tag" that doesn't actually exist anywhere is a real
        // bug, not just a sync annoyance) — but this alone does NOT stop
        // pushDirty below from re-attempting them this same cycle (it
        // just bumped their updatedAt, making the dirty predicate MORE
        // likely to match), so the orphanedJoinIDs exclusion passed into
        // pushDirty is what actually prevents the repeat failure. See
        // isOrphaned's own doc comment for why soft-deleting alone can't
        // be the whole fix.
        let orphaned = cleanOrphanedJoins(context: context)

        // Which tags/projects/tasks must be force-included in this cycle's
        // push even though they aren't themselves "dirty" — narrowly
        // scoped to just the parents actually referenced by outgoing
        // project_tags/task_tags rows this cycle. A join row can only push
        // successfully if the parent it references actually exists in
        // Supabase, and our local dirty cursor has no way of knowing
        // whether that parent's *own* past push ever actually succeeded
        // (see cleanOrphanedJoins's doc comment for the exact failure this
        // guards against — a parent that silently never made it up stops
        // looking dirty forever once its updatedAt falls behind the
        // cursor). This used to force-include *every* row in these three
        // tables every cycle regardless of dirtiness, which fixed that
        // problem but created a worse one: PostgREST's upsert has no
        // server-side last-write-wins check, so a device re-pushing its
        // own stale copy of a row on its normal ~25s schedule could
        // silently clobber a fresher edit the other device had just
        // pushed moments earlier (this is what broke project reordering
        // inside a folder — both devices kept re-asserting their own
        // stale sortOrder). Scoping to just the referenced rows keeps the
        // FK guarantee while only re-pushing something outside the normal
        // dirty set when there's an actual join row that needs it this
        // cycle.
        let dirtyProjectTags = ((try? context.fetch(FetchDescriptor<ProjectTag>(
            predicate: #Predicate<ProjectTag> { $0.updatedAt > since }
        ))) ?? []).filter { !orphaned.projectTagIDs.contains($0.id) }
        let dirtyTaskTags = ((try? context.fetch(FetchDescriptor<TaskTag>(
            predicate: #Predicate<TaskTag> { $0.updatedAt > since }
        ))) ?? []).filter { !orphaned.taskTagIDs.contains($0.id) }
        let forceTagIDs = Set(dirtyProjectTags.map(\.tagID) + dirtyTaskTags.map(\.tagID))
        let forceProjectIDs = Set(dirtyProjectTags.map(\.projectID))
        let forceTaskIDs = Set(dirtyTaskTags.map(\.taskID))

        // Each table pushes independently (its own do/catch) rather than
        // sharing one do-block — a single table throwing used to abort
        // every *later* table in this same cycle too (PostgREST rejecting
        // "tags", say, meant "projects"/"tasks"/"task_tags" never even got
        // attempted), which silently blocked unrelated edits from ever
        // reaching Supabase. The push cursor only advances if every table
        // succeeded, so a real failure still causes a full retry next
        // cycle — this only removes the *cascading* block between tables.
        var failures: [String] = []

        func attempt(_ label: String, _ operation: () async throws -> Void) async {
            do {
                try await operation()
            } catch {
                failures.append("\(label): \(error.localizedDescription)")
            }
        }

        await attempt("folders") {
            try await pushDirty(
                table: "folders", context: context,
                predicate: #Predicate<Folder> { $0.updatedAt > since }
            ) { FolderDTO($0) }
        }
        await attempt("tags") {
            try await pushDirty(
                table: "tags", context: context,
                predicate: #Predicate<Tag> { $0.updatedAt > since || forceTagIDs.contains($0.id) }
            ) { TagDTO($0) }
        }
        await attempt("projects") {
            try await pushDirty(
                table: "projects", context: context,
                predicate: #Predicate<Project> { $0.updatedAt > since || forceProjectIDs.contains($0.id) }
            ) { ProjectDTO($0) }
        }
        // Placed right after "projects" (not grouped with the other join
        // tables below) so a project created and shared in the same local
        // session has already reached Supabase by the time its share row
        // is attempted — project_shares' only FK parent is projects, and
        // it's pushed synchronously earlier in this same cycle, so unlike
        // project_tags/task_tags this doesn't need the forceProjectIDs-style
        // re-push guard.
        await attempt("project_shares") {
            try await pushDirty(
                table: "project_shares", context: context,
                predicate: #Predicate<ProjectShare> { $0.updatedAt > since }
            ) { ProjectShareDTO($0) }
        }
        await attempt("project_tags") {
            try await pushDirty(
                table: "project_tags", context: context,
                predicate: #Predicate<ProjectTag> { $0.updatedAt > since },
                excluding: { orphaned.projectTagIDs.contains($0.id) }
            ) { ProjectTagDTO($0) }
        }
        await attempt("tasks") {
            try await pushDirty(
                table: "tasks", context: context,
                predicate: #Predicate<TaskItem> { $0.updatedAt > since || forceTaskIDs.contains($0.id) }
            ) { TaskDTO($0) }
        }
        await attempt("task_tags") {
            try await pushDirty(
                table: "task_tags", context: context,
                predicate: #Predicate<TaskTag> { $0.updatedAt > since },
                excluding: { orphaned.taskTagIDs.contains($0.id) }
            ) { TaskTagDTO($0) }
        }

        // cleanOrphanedJoins above soft-deletes tombstoned rows in place —
        // persist those regardless of whether any table's push succeeded.
        try? context.save()

        if failures.isEmpty {
            SyncCursor.lastPushedAt = cutoff
            lastError = nil
        } else {
            lastError = "Push failed: \(failures.joined(separator: "; "))"
        }
    }

    /// A TaskTag/ProjectTag referencing a tag (or task/project) that no
    /// longer exists anywhere locally can never be pushed successfully —
    /// Postgres's foreign key constraint rejects the row regardless of our
    /// own deletedAt flag, since the DB has no concept of our app-level
    /// soft-delete (a *soft-deleted* join still carries the same broken
    /// reference). PostgREST also upserts a whole batch atomically, so
    /// this one bad row blocked every *other* dirty task_tags/project_tags
    /// row in the same batch too. Returns the offending ids so pushAll can
    /// exclude them from this same cycle's push (soft-deleting them here
    /// bumps their own updatedAt, which otherwise would make pushDirty's
    /// own `updatedAt > since` predicate pick them right back up).
    private static func cleanOrphanedJoins(context: ModelContext) -> (taskTagIDs: Set<UUID>, projectTagIDs: Set<UUID>) {
        let now = Date()
        guard let allTags = try? context.fetch(FetchDescriptor<Tag>()) else { return ([], []) }
        let tagIDs = Set(allTags.map(\.id))

        var orphanedTaskTagIDs: Set<UUID> = []
        if let taskTags = try? context.fetch(FetchDescriptor<TaskTag>(predicate: #Predicate { $0.deletedAt == nil })),
           let allTasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            let taskIDs = Set(allTasks.map(\.id))
            for taskTag in taskTags where !tagIDs.contains(taskTag.tagID) || !taskIDs.contains(taskTag.taskID) {
                taskTag.deletedAt = now
                taskTag.updatedAt = now
                orphanedTaskTagIDs.insert(taskTag.id)
            }
        }

        var orphanedProjectTagIDs: Set<UUID> = []
        if let projectTags = try? context.fetch(FetchDescriptor<ProjectTag>(predicate: #Predicate { $0.deletedAt == nil })),
           let allProjects = try? context.fetch(FetchDescriptor<Project>()) {
            let projectIDs = Set(allProjects.map(\.id))
            for projectTag in projectTags where !tagIDs.contains(projectTag.tagID) || !projectIDs.contains(projectTag.projectID) {
                projectTag.deletedAt = now
                projectTag.updatedAt = now
                orphanedProjectTagIDs.insert(projectTag.id)
            }
        }

        return (orphanedTaskTagIDs, orphanedProjectTagIDs)
    }

    private static func pushDirty<Model: PersistentModel, DTO: Encodable>(
        table: String,
        context: ModelContext,
        predicate: Predicate<Model>,
        excluding isExcluded: (Model) -> Bool = { _ in false },
        toDTO: (Model) -> DTO
    ) async throws {
        let rows = try context.fetch(FetchDescriptor<Model>(predicate: predicate))
            .filter { !isExcluded($0) }
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
        print("[SYNC] pulling everything with updated_at >= \(since) (raw: \(since.timeIntervalSinceReferenceDate))")
        var maxSeenUpdatedAt: Date?
        var errors: [String] = []

        do {
            let folders: [FolderDTO] = try await fetchPage(table: "folders", since: since)
            for dto in folders { upsertFolder(dto, context: context) }
            if let m = folders.map(\.updatedAt).max() {
                maxSeenUpdatedAt = max(maxSeenUpdatedAt ?? m, m)
            }
            print("[SYNC] merged folders: \(folders.count)")
        } catch {
            errors.append("folders: \(error.localizedDescription)")
        }

        do {
            let tags: [TagDTO] = try await fetchPage(table: "tags", since: since)
            for dto in tags { upsertTag(dto, context: context) }
            if let m = tags.map(\.updatedAt).max() {
                maxSeenUpdatedAt = max(maxSeenUpdatedAt ?? m, m)
            }
            print("[SYNC] merged tags: \(tags.count)")
        } catch {
            errors.append("tags: \(error.localizedDescription)")
        }

        do {
            let projects: [ProjectDTO] = try await fetchPage(table: "projects", since: since)
            for dto in projects { upsertProject(dto, context: context) }
            if let m = projects.map(\.updatedAt).max() {
                maxSeenUpdatedAt = max(maxSeenUpdatedAt ?? m, m)
            }
            print("[SYNC] merged projects: \(projects.count)")
        } catch {
            errors.append("projects: \(error.localizedDescription)")
        }

        do {
            let projectShares: [ProjectShareDTO] = try await fetchPage(table: "project_shares", since: since)
            for dto in projectShares { upsertProjectShare(dto, context: context) }
            if let m = projectShares.map(\.updatedAt).max() {
                maxSeenUpdatedAt = max(maxSeenUpdatedAt ?? m, m)
            }
            print("[SYNC] merged project_shares: \(projectShares.count)")
        } catch {
            errors.append("project_shares: \(error.localizedDescription)")
        }

        do {
            let projectTags: [ProjectTagDTO] = try await fetchPage(table: "project_tags", since: since)
            for dto in projectTags { upsertProjectTag(dto, context: context) }
            if let m = projectTags.map(\.updatedAt).max() {
                maxSeenUpdatedAt = max(maxSeenUpdatedAt ?? m, m)
            }
            print("[SYNC] merged project_tags: \(projectTags.count)")
        } catch {
            errors.append("project_tags: \(error.localizedDescription)")
        }

        do {
            let tasks: [TaskDTO] = try await fetchPage(table: "tasks", since: since)
            for dto in tasks { upsertTask(dto, context: context) }
            if let m = tasks.map(\.updatedAt).max() {
                maxSeenUpdatedAt = max(maxSeenUpdatedAt ?? m, m)
            }
            print("[SYNC] merged tasks: \(tasks.count)")
        } catch {
            errors.append("tasks: \(error.localizedDescription)")
        }

        do {
            let taskTags: [TaskTagDTO] = try await fetchPage(table: "task_tags", since: since)
            for dto in taskTags { upsertTaskTag(dto, context: context) }
            if let m = taskTags.map(\.updatedAt).max() {
                maxSeenUpdatedAt = max(maxSeenUpdatedAt ?? m, m)
            }
            print("[SYNC] merged task_tags: \(taskTags.count)")
        } catch {
            errors.append("task_tags: \(error.localizedDescription)")
        }

        // upsertFolder/upsertProject/etc. above mutate tracked model
        // instances in place but never persist them — without an explicit
        // save, whether/when those merges actually reach disk (and reach
        // other views' @Query observers) depends entirely on SwiftData's
        // own autosave timing rather than happening deterministically at
        // the end of a sync cycle.
        try? context.save()

        if let maxSeenUpdatedAt {
            // fetchPage now filters with strict `.gt`, not `.gte` — an
            // earlier version used `.gte` plus nudging this cursor a
            // microsecond past the max seen timestamp to keep an
            // already-fetched boundary row from matching again forever.
            // That nudge never actually worked: PostgrestFilterValue's Date
            // encoding (ISO8601DateFormatter with `.withFractionalSeconds`)
            // only keeps 3 fractional digits, so a 1-microsecond nudge was
            // silently rounded away before the request ever went out,
            // leaving the cursor effectively stuck. Plain `.gt` sidesteps
            // the whole problem — no encoding precision to lose.
            SyncCursor.lastPulledAt = maxSeenUpdatedAt
        }

        if errors.isEmpty {
            lastError = nil
        } else {
            let message = errors.joined(separator: " | ")
            lastError = "Pull completed with partial failures: \(message)"
            print("[SYNC] \(lastError ?? "")")
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
                    .gt("updated_at", value: since)
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
    //
    // "Newer" is judged after rounding the local timestamp down to
    // millisecond precision, not by a raw Date comparison: PostgrestFilterValue
    // encodes Date via ISO8601DateFormatter's `.withFractionalSeconds`, which
    // Apple's formatter always truncates to exactly 3 fractional digits —
    // coarser than Swift's native Date, which keeps far more precision. Any
    // dto decoded from a Supabase round trip has already lost everything
    // finer than 1ms, so comparing it against a local Date stamped with
    // full precision can make the *same* edit look "older" once it comes
    // back — up to 1ms of local-only precision doesn't reflect a real
    // difference in when the edits happened, and rejecting on it caused a
    // genuinely newer remote edit to be silently discarded.
    private static func isNewer(_ incoming: Date, thanLocal local: Date) -> Bool {
        let localMillisFloor = (local.timeIntervalSince1970 * 1000).rounded(.down) / 1000
        return incoming.timeIntervalSince1970 > localMillisFloor
    }

    private static func upsertFolder(_ dto: FolderDTO, context: ModelContext) {
        let dtoID = dto.id
        let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == dtoID })
        if let existing = try? context.fetch(descriptor).first {
            guard isNewer(dto.updatedAt, thanLocal: existing.updatedAt) else { return }
            existing.name = dto.name
            existing.sortOrder = dto.sortOrder
            existing.updatedAt = dto.updatedAt
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(Folder(
                id: dto.id, name: dto.name, sortOrder: dto.sortOrder,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            ))
        }
    }

    private static func upsertTag(_ dto: TagDTO, context: ModelContext) {
        let dtoID = dto.id
        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == dtoID })
        if let existing = try? context.fetch(descriptor).first {
            guard isNewer(dto.updatedAt, thanLocal: existing.updatedAt) else { return }
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
            guard isNewer(dto.updatedAt, thanLocal: existing.updatedAt) else {
                print("[SYNC] pull rejected project \(dto.name) (\(dtoID)): incoming updatedAt \(dto.updatedAt) (raw \(dto.updatedAt.timeIntervalSinceReferenceDate)) is not newer than local \(existing.updatedAt) (raw \(existing.updatedAt.timeIntervalSinceReferenceDate)) — local sortOrder \(existing.sortOrder), incoming sortOrder \(dto.sortOrder)")
                return
            }
            print("[SYNC] pull merging project \(dto.name) (\(dtoID)): sortOrder \(existing.sortOrder) -> \(dto.sortOrder)")
            existing.name = dto.name
            existing.notes = dto.notes
            existing.isCompleted = dto.isCompleted
            existing.flagged = dto.flagged
            existing.dueDate = dto.dueDate
            existing.deferDate = dto.deferDate
            existing.folderID = dto.folderID
            existing.sortOrder = dto.sortOrder
            existing.reviewIntervalDays = dto.reviewIntervalDays
            existing.lastReviewedAt = dto.lastReviewedAt
            existing.updatedAt = dto.updatedAt
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(Project(
                id: dto.id, name: dto.name, notes: dto.notes, isCompleted: dto.isCompleted,
                flagged: dto.flagged, dueDate: dto.dueDate, deferDate: dto.deferDate,
                folderID: dto.folderID, sortOrder: dto.sortOrder,
                reviewIntervalDays: dto.reviewIntervalDays, lastReviewedAt: dto.lastReviewedAt,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            ))
        }
    }

    private static func upsertProjectShare(_ dto: ProjectShareDTO, context: ModelContext) {
        let dtoID = dto.id
        let descriptor = FetchDescriptor<ProjectShare>(predicate: #Predicate { $0.id == dtoID })
        if let existing = try? context.fetch(descriptor).first {
            guard isNewer(dto.updatedAt, thanLocal: existing.updatedAt) else { return }
            existing.projectID = dto.projectID
            existing.sharedWithUserID = dto.sharedWithUserID
            existing.sharedWithUsername = dto.sharedWithUsername
            existing.updatedAt = dto.updatedAt
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(ProjectShare(
                id: dto.id, projectID: dto.projectID, sharedWithUserID: dto.sharedWithUserID,
                sharedWithUsername: dto.sharedWithUsername,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            ))
        }
    }

    private static func upsertProjectTag(_ dto: ProjectTagDTO, context: ModelContext) {
        let dtoID = dto.id
        let descriptor = FetchDescriptor<ProjectTag>(predicate: #Predicate { $0.id == dtoID })
        if let existing = try? context.fetch(descriptor).first {
            guard isNewer(dto.updatedAt, thanLocal: existing.updatedAt) else { return }
            existing.projectID = dto.projectID
            existing.tagID = dto.tagID
            existing.updatedAt = dto.updatedAt
            existing.deletedAt = dto.deletedAt
        } else {
            context.insert(ProjectTag(
                id: dto.id, projectID: dto.projectID, tagID: dto.tagID,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            ))
        }
    }

    private static func upsertTask(_ dto: TaskDTO, context: ModelContext) {
        let dtoID = dto.id
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == dtoID })
        if let existing = try? context.fetch(descriptor).first {
            guard isNewer(dto.updatedAt, thanLocal: existing.updatedAt) else { return }
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
            guard isNewer(dto.updatedAt, thanLocal: existing.updatedAt) else { return }
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
