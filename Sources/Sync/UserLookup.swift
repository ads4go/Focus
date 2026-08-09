import Foundation
import PostgREST

/// One-off username -> Supabase auth user id lookup, used only by the
/// "Share Project" action — deliberately not part of the periodic
/// SyncEngine push/pull loop. Goes through the lookup_user_id_by_username
/// Postgres function rather than reading the profiles table directly,
/// since that table's own RLS only lets a user read their own row (see
/// README's shared-projects migration for why).
enum UserLookup {
    private struct Params: Encodable {
        let lookup_username: String
    }

    static func userID(forUsername username: String) async throws -> UUID? {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let id: UUID? = try await SupabaseServices.postgrest
            .rpc("lookup_user_id_by_username", params: Params(lookup_username: normalized))
            .execute()
            .value
        return id
    }
}
