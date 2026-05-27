import AuthenticationServices
import ClerkKit
import SwiftUI

struct SignInView: View {
    @State private var email = ""
    @State private var code = ""
    @State private var pendingSignIn: SignIn?
    @State private var status: String?
    @State private var inProgress = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Palkie Talkie").font(.largeTitle.bold())
            Text("Voice fluency. Real personalities. No drills.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Button {
                    Task { await signInWithApple() }
                } label: {
                    Label("Continue with Apple", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(inProgress)

                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    Label("Continue with Google", systemImage: "g.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(inProgress)

                Divider().padding(.vertical, 8)

                if pendingSignIn == nil {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Send email code") {
                        Task { await sendEmailCode() }
                    }
                    .disabled(email.isEmpty || inProgress)
                } else {
                    TextField("Verification code", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                    Button("Verify") {
                        Task { await verifyEmailCode() }
                    }
                    .disabled(code.isEmpty || inProgress)
                }
            }
            .padding()

            if let status {
                Text(status).foregroundStyle(.secondary).font(.footnote)
            }
        }
        .padding()
    }

    private func signInWithGoogle() async {
        inProgress = true
        defer { inProgress = false }
        do {
            _ = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
        } catch {
            status = "Google sign-in failed: \(error.localizedDescription)"
        }
    }

    private func signInWithApple() async {
        inProgress = true
        defer { inProgress = false }
        do {
            _ = try await Clerk.shared.auth.signInWithApple()
        } catch {
            status = "Apple sign-in failed: \(error.localizedDescription)"
        }
    }

    private func sendEmailCode() async {
        inProgress = true
        defer { inProgress = false }
        do {
            pendingSignIn = try await Clerk.shared.auth.signInWithEmailCode(emailAddress: email)
            status = "Code sent. Check your email."
        } catch {
            status = "Couldn't send code: \(error.localizedDescription)"
        }
    }

    private func verifyEmailCode() async {
        inProgress = true
        defer { inProgress = false }
        guard let signIn = pendingSignIn else { return }
        do {
            _ = try await signIn.verifyCode(code)
            pendingSignIn = nil
            code = ""
        } catch {
            status = "Verification failed: \(error.localizedDescription)"
        }
    }
}
