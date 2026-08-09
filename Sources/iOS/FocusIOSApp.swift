import SwiftUI
import SwiftData

@main
struct FocusIOSApp: App {
    @State private var authStore = AuthSessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authStore)
        }
        .modelContainer(for: [Tag.self, Folder.self, Project.self, TaskItem.self, TaskTag.self, ProjectTag.self, ProjectShare.self])
    }
}
