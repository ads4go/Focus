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
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
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

    /// Clears all local data and resets both sync cursors before signing
    /// out — otherwise a different account signing in next would see this
    /// account's rows still sitting in local storage, mixed in with
    /// whatever it pulls, and would inherit a sync cursor pointed at this
    /// account's last-synced position (exactly the "old data missing"
    /// cursor bug this app hit once already, see ProjectsScreen history).
    private func logOut() {
        try? modelContext.delete(model: TaskTag.self)
        try? modelContext.delete(model: ProjectTag.self)
        try? modelContext.delete(model: TaskItem.self)
        try? modelContext.delete(model: Project.self)
        try? modelContext.delete(model: Tag.self)
        try? modelContext.delete(model: Folder.self)
        SyncCursor.lastPulledAt = .distantPast
        SyncCursor.lastPushedAt = .distantPast
        Task { await authStore.signOut() }
    }
}
