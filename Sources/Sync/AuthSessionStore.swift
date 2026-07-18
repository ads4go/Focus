import Foundation
import Auth
import Observation

/// Tracks the signed-in Supabase user and keeps the shared Postgrest client's
/// bearer token in sync with the current session (including after auto-refresh),
/// so RLS policies scoped to `auth.uid()` see the right caller on every request.
@Observable
@MainActor
final class AuthSessionStore {
    private(set) var session: Session?
    private(set) var isRestoringSession = true
    var errorMessage: String?

    private let auth = SupabaseServices.auth

    var isSignedIn: Bool { session != nil }
    var currentUserID: UUID? { session?.user.id }

    init() {
        Task { await observeAuthChanges() }
    }

    private func observeAuthChanges() async {
        for await (_, session) in auth.authStateChanges {
            self.session = session
            _ = SupabaseServices.postgrest.setAuth(session?.accessToken)
            isRestoringSession = false
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await auth.signUp(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        try? await auth.signOut()
    }
}
