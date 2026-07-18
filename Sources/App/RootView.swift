import SwiftUI

struct RootView: View {
    @Environment(AuthSessionStore.self) private var authStore

    var body: some View {
        if authStore.isRestoringSession {
            ProgressView()
                .frame(width: 400, height: 300)
        } else if authStore.isSignedIn {
            ContentView()
        } else {
            SignInView(authStore: authStore)
        }
    }
}
