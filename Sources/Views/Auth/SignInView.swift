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
            Text("Sign in with the same username and password on every Mac you want this to sync to.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

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

            Button(isSigningUp ? "Already have an account? Sign In" : "New here? Create an Account") {
                isSigningUp.toggle()
                authStore.errorMessage = nil
                authStore.statusMessage = nil
            }
            #if os(macOS)
            .buttonStyle(.link)
            #else
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
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
