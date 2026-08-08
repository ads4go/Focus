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
    var statusMessage: String?

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

    func signIn(username: String, password: String) async {
        errorMessage = nil
        statusMessage = nil
        do {
            _ = try await auth.signIn(email: syntheticEmail(for: username), password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(username: String, password: String) async {
        errorMessage = nil
        statusMessage = nil
        do {
            let response = try await auth.signUp(email: syntheticEmail(for: username), password: password)
            switch response {
            case .session:
                break // authStateChanges picks this up and flips the UI over to the app.
            case .user:
                // Supabase's "Confirm email" setting is on, so no session comes
                // back yet — without this, sign-up looks like it silently did
                // nothing. Usernames aren't real addresses, so there's no
                // confirmation link to receive; the fix is disabling the
                // setting, not checking an inbox.
                statusMessage = "Account created, but this Supabase project requires email confirmation. Since Focus signs in with a username rather than a real address, turn off \"Confirm email\" under Authentication settings in the Supabase dashboard, then sign in."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Supabase Auth only speaks email/password — usernames are a synthetic
    /// email under a fixed domain, invisible to the user. Same trick works
    /// for both sign-in and sign-up since it's a pure function of the
    /// username.
    private func syntheticEmail(for username: String) -> String {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalized)@gmail.com"
    }

    func signOut() async {
        try? await auth.signOut()
    }
}
