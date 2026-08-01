import SwiftUI

struct RootView: View {
    @Environment(AuthSessionStore.self) private var authStore

    var body: some View {
        Group {
            if authStore.isRestoringSession {
                ProgressView()
            } else if authStore.isSignedIn {
                RootTabView()
            } else {
                SignInView(authStore: authStore)
            }
        }
        // Matches the Mac app's dark appearance (white text on black),
        // independent of the device's system appearance setting.
        .preferredColorScheme(.dark)
    }
}
