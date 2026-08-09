import SwiftUI

struct SignInView: View {
    let authStore: AuthSessionStore

    @State private var username = ""
    @State private var password = ""
    @State private var isSigningUp = false
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Focus")
                .font(.largeTitle.bold())

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(isSigningUp ? .newPassword : .password)
                .onSubmit(submit)

            if let errorMessage = authStore.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if let statusMessage = authStore.statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(isSigningUp ? "Create Account" : "Sign In") {
                submit()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSubmitting || username.isEmpty || password.isEmpty)

            // Accounts are created by hand via the Supabase Admin dashboard
            // (see README), not self-serve — this toggle only makes sense
            // on macOS, which is otherwise identical behavior. Leaving
            // isSigningUp permanently false on iOS collapses every other
            // ternary below to plain sign-in with no further changes.
            #if os(macOS)
            Button(isSigningUp ? "Already have an account? Sign In" : "New here? Create an Account") {
                isSigningUp.toggle()
                authStore.errorMessage = nil
                authStore.statusMessage = nil
            }
            .buttonStyle(.link)
            #endif
        }
        .padding(32)
        .frame(maxWidth: 360)
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            if isSigningUp {
                await authStore.signUp(username: username, password: password)
            } else {
                await authStore.signIn(username: username, password: password)
            }
            isSubmitting = false
        }
    }
}
