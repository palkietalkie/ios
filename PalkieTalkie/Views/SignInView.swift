import SwiftUI

struct SignInView: View {
    /// Shared control height so the email/code fields line up with the .controlSize(.large) sign-in buttons.
    private static let controlHeight: CGFloat = 50

    @State private var model: SignInViewModel

    init(service: (any SignInService)? = nil, announcer: (any AuthAnnouncing)? = nil) {
        _model = State(initialValue: SignInViewModel(
            service: service ?? ClerkSignInService(),
            announcer: announcer ?? AppEnvironment.makeProductionAnnouncer(),
        ))
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 24) {
            Text("Palkie Talkie").font(.largeTitle.bold())
            Text("Voice fluency. Real personalities. No drills.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Button {
                    Task { await model.signInWithApple() }
                } label: {
                    Label("Continue with Apple", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.inProgress)

                Button {
                    Task { await model.signInWithGoogle() }
                } label: {
                    Label("Continue with Google", systemImage: "g.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.inProgress)

                Divider().padding(.vertical, 8)

                if !model.awaitingCode {
                    // Match the .controlSize(.large) buttons: TextField ignores .controlSize, so set the height explicitly.
                    TextField("Email", text: $model.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 12)
                        .frame(height: Self.controlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(.systemGray3), lineWidth: 1),
                        )
                    Button("Send email code") {
                        Task { await model.sendEmailCode() }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.email.isEmpty || model.inProgress)
                } else {
                    TextField("Verification code", text: $model.code)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 12)
                        .frame(height: Self.controlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(.systemGray3), lineWidth: 1),
                        )
                    Button("Verify") {
                        Task { await model.verifyEmailCode() }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.code.isEmpty || model.inProgress)
                }
            }
            .padding()

            if let status = model.status {
                Text(status).foregroundStyle(.secondary).font(.footnote)
            }
        }
        .padding()
    }
}
