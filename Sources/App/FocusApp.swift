import SwiftUI
import SwiftData

@main
struct FocusApp: App {
    @State private var authStore = AuthSessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authStore)
                .frame(minWidth: 800, minHeight: 500)
        }
        .modelContainer(for: [Tag.self, Project.self, TaskItem.self, TaskTag.self])
    }
}
