import SwiftUI

struct SignInView: View {
    let authStore: AuthSessionStore

    @State private var email = ""
    @State private var password = ""
    @State private var isSigningUp = false
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Focus")
                .font(.largeTitle.bold())
            Text("Sign in with the same account on every Mac you want this to sync to.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
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
            .disabled(isSubmitting || email.isEmpty || password.isEmpty)

            Button(isSigningUp ? "Already have an account? Sign In" : "New here? Create an Account") {
                isSigningUp.toggle()
                authStore.errorMessage = nil
                authStore.statusMessage = nil
            }
            .buttonStyle(.link)
        }
        .padding(32)
        .frame(width: 360)
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            if isSigningUp {
                await authStore.signUp(email: email, password: password)
            } else {
                await authStore.signIn(email: email, password: password)
            }
            isSubmitting = false
        }
    }
}
