import SwiftUI
import SwiftData

/// Sheet opened by RootTabView's hamburger tab — a manual sync trigger and
/// account switching (sign out), the iPhone equivalent of ContentView's
/// "Sync Now"/"Sign Out" toolbar buttons on macOS.
struct MenuSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var isSyncing = false
    @State private var isLoggingOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isSyncing = true
                        Task {
                            await SyncEngine.syncNow(context: modelContext)
                            isSyncing = false
                        }
                    } label: {
                        Label(isSyncing ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isSyncing)
                }

                Section {
                    Button(role: .destructive, action: logOut) {
                        Label(isLoggingOut ? "Logging Out…" : "Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(isLoggingOut)
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Pushes any pending local edits, THEN clears all local data and
    /// resets both sync cursors before signing out. The push has to come
    /// first: without it, an edit made moments ago — still inside the ~2s
    /// debounce in RootTabView.schedulePush, or simply mid-flight on the
    /// network — gets wiped by resetLocalData before it ever reaches
    /// Supabase, silently discarding it for good (this is exactly how a
    /// just-created ProjectShare row went missing in testing). Resetting
    /// local data at all is still necessary on its own — otherwise a
    /// different account signing in next would see this account's rows
    /// still sitting in local storage, mixed in with whatever it pulls,
    /// and would inherit a sync cursor pointed at this account's
    /// last-synced position (the "old data missing" cursor bug this app
    /// hit once already, see ProjectsScreen history).
    private func logOut() {
        isLoggingOut = true
        Task {
            await SyncEngine.pushAll(context: modelContext)
            SyncEngine.resetLocalData(context: modelContext)
            await authStore.signOut()
            isLoggingOut = false
        }
    }
}
