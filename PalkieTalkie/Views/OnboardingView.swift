import SwiftUI

/// First-launch flow that captures `nativeLanguages`, `targetLanguage`, and `targetAccents` before letting the user into the main app. Presented as a step-by-step wizard — one decision per screen, animated — rather than a single Form: the form read as data entry, the wizard reads as a guided setup and lets each step explain *why* it's asked. Other profile fields keep server defaults and are editable later in Profile.
@MainActor
struct OnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.backendAPI) private var api
    @Environment(\.authing) private var auth
    @Environment(\.onboardingAnnouncer) private var onboardingAnnouncer
    // Display language is a local UI setting (not a profile field); the step writes here and the root app reads it via `.environment(\.locale, …)`.
    @AppStorage("AppLocale") private var appLocale: String = ""
    @State private var model: OnboardingViewModel
    /// Slack thread for this user's onboarding; the first reported step opens it, the rest thread under it.
    @State private var onboardingThreadTs: String?

    init(onContinue: @escaping () -> Void, model: OnboardingViewModel = OnboardingViewModel()) {
        self.onContinue = onContinue
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // contentShape on the filled frame so the entire area between top bar and footer is swipeable, even when the step's content is short.
                .contentShape(Rectangle())
                .simultaneousGesture(stepSwipe)
            footer
        }
        .background(Color(.systemBackground))
        .task {
            guard !model.didInitialLoad else { return }
            model.didInitialLoad = true
            await model.load(api: api, auth: auth)
            // onChange doesn't fire for the initial step, so report the first view here.
            await recordStep(model.step, phase: "viewed")
        }
        .onChange(of: model.step) { _, new in
            Task { await recordStep(new, phase: "viewed") }
        }
        .overlay { if model.loading { ProgressView() } }
        .interactiveDismissDisabled()
    }

    // MARK: - Top bar: back chevron + progress

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            .opacity(model.step == .intro ? 0 : 1)
            .disabled(model.step == .intro)

            HStack(spacing: 6) {
                ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= model.step.rawValue ? Color.accentColor : Color(.systemGray4))
                        .frame(height: 4)
                        .animation(.easeInOut, value: model.step)
                }
            }
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Animated step content

    private var stepBody: some View {
        currentStep
            .id(model.step)
            .transition(.asymmetric(
                insertion: .move(edge: model.advancing ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: model.advancing ? .leading : .trailing).combined(with: .opacity),
            ))
    }

    /// Swipe to move between steps (left = next, right = back), mirroring the footer button + back chevron. Applied in `body` to the FULL-height filled area, not here on currentStep — a short step like "You're all set" sizes to its content, so attaching the gesture to currentStep left most of the screen non-swipeable. simultaneousGesture so a step's vertical ChoiceList still scrolls; we only act on a predominantly-horizontal drag, and left-swipe respects stepValid like the Continue button.
    private var stepSwipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height),
                  abs(value.translation.width) > 60
            else { return }
            if value.translation.width < 0 {
                if model.stepValid { advance() }
            } else {
                goBack()
            }
        }
    }

    @ViewBuilder private var currentStep: some View {
        switch model.step {
        case .intro:
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to").font(.largeTitle.bold())
                Text(verbatim: "Palkie Talkie").font(.largeTitle.bold()).foregroundStyle(.tint)
                Text(
                    "It's a voice app for getting fluent by actually talking. Your tutor is a real character who speaks naturally, remembers you, and keeps the conversation going, no lessons, no scripts.",
                )
                .font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Talk out loud anytime, your walk, your commute, your kitchen.", systemImage: "figure.walk")
                    Label("Pick a tutor with real personality, or make your own.", systemImage: "person.wave.2.fill")
                    Label("It remembers your life and picks up where you left off.", systemImage: "brain.head.profile")
                }
                .font(.callout)
                .padding(.top, 4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 16)
        case .displayLanguage:
            StepScaffold(
                title: "Choose your app language",
                why: "The language Palkie Talkie's screens appear in.",
            ) {
                ChoiceList(
                    options: supportedAppLocales.map(\.code),
                    isSelected: { appLocale == $0 },
                    display: { code in supportedAppLocales.first { $0.code == code }?.label ?? code },
                ) {
                    appLocale = $0
                }
            }
        case .name:
            StepScaffold(
                title: "What should your tutor call you?",
                why: "Your tutor uses your name in conversation, the way a friend would.",
            ) {
                // Styled to match a ChoiceList box (same vertical padding, corner radius, fill) so the field's height lines up with the option boxes on the other steps instead of being a thin .roundedBorder strip.
                TextField("Your name", text: $model.preferredName)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground)),
                    )
            }
        case .native:
            StepScaffold(
                title: "What's your native language?",
                why: "So your tutor can switch to it when you get stuck, and say your name right.",
            ) {
                ChoiceList(
                    options: model.languages.map(\.name),
                    isSelected: { model.nativeLanguages.contains($0) },
                    display: localizedLanguageName,
                ) {
                    model.toggleNative($0)
                }
            }
        case .target:
            StepScaffold(
                title: "What do you want to learn?",
                why: "The language you'll practice speaking.",
            ) {
                ChoiceList(
                    options: model.languages.map(\.name),
                    isSelected: { model.targetLanguage == $0 },
                    display: localizedLanguageName,
                ) {
                    model.pickTarget($0)
                }
            }
        case .accents:
            StepScaffold(
                title: "Which accents?",
                why: "Your tutor mixes these in so you hear natural variety. Pick one or more.",
            ) {
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Button(model.allAccentsSelected ? "Clear all" : "Select all") {
                            model.toggleAllAccents()
                        }
                        .font(.subheadline)
                    }
                    ChoiceList(
                        options: model.accentsForTargetLanguage,
                        isSelected: { model.targetAccents.contains($0) },
                        display: localizedAccentName,
                    ) {
                        model.toggleAccent($0)
                    }
                }
            }
        case .proficiency:
            StepScaffold(
                title: "What's your level?",
                why: "So your tutor pitches the conversation to the right level.",
            ) {
                ChoiceList(
                    options: model.practiceOptions?.proficiency ?? [],
                    isSelected: { model.proficiency == $0 },
                    display: formatSlugLabel,
                ) {
                    model.pickProficiency($0)
                }
            }
        case .speed:
            StepScaffold(
                title: "How fast should your tutor speak?",
                why: "Slower is easier to follow; faster pushes you.",
            ) {
                ChoiceList(
                    options: model.practiceOptions?.tutorSpeakingSpeed ?? [],
                    isSelected: { model.tutorSpeakingSpeed == $0 },
                    // Append the backend-sourced rate ("Slow · 0.85×") so the concrete number disambiguates slow vs very slow.
                    display: { slug in
                        guard let rate = model.practiceOptions?.tutorSpeakingSpeedRates[slug] else {
                            return formatSlugLabel(slug)
                        }
                        return "\(formatSlugLabel(slug)) · \(formatSpeedRate(rate))"
                    },
                ) {
                    model.pickSpeed($0)
                }
            }
        case .goals:
            StepScaffold(
                title: "What are you practicing for?",
                why: "Pick any that fit, or add your own. Your tutor steers toward what matters to you.",
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ChoiceList(
                        options: model.goalPresets,
                        isSelected: { model.selectedGoals.contains($0) },
                        display: localizedGoalLabel,
                    ) {
                        model.toggleGoal($0)
                    }
                    TextField("Something else?", text: $model.otherGoal, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
            }
        case .getStarted:
            StepScaffold(
                title: "You're all set",
                why: "Here's how your first conversation works.",
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    Label(
                        "Your tutor speaks first, you don't need to say anything to begin.",
                        systemImage: "speaker.wave.2.fill",
                    )
                    Label("Listen, then reply out loud whenever you're ready.", systemImage: "mic.fill")
                    Label(
                        "No buttons to press, just talk, like a real conversation.",
                        systemImage: "bubble.left.and.bubble.right.fill",
                    )
                }
                .font(.body)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Footer: error + primary button

    private var footer: some View {
        VStack(spacing: 8) {
            if let err = model.loadError ?? model.saveError {
                Text(err).font(.footnote).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            // Reassure on every setup step so a quick pick doesn't feel permanent; the intro and primer aren't settings, so they're exempt.
            if model.step != .intro, model.step != .getStarted {
                Text("You can change this anytime later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            Button {
                advance()
            } label: {
                Text(model.step == .getStarted ? "Start talking" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.stepValid || model.saving)
        }
        .padding()
    }

    // MARK: - Navigation (animation only; the logic lives in the model)

    /// Report a step view/completion to the drop-off feed. Best-effort; the first reported step opens the thread and we keep that ts for the rest.
    private func recordStep(_ step: OnboardingViewModel.Step, phase: String) async {
        let ts = await onboardingAnnouncer.announce(step: step.slug, phase: phase, threadTs: onboardingThreadTs)
        if onboardingThreadTs == nil { onboardingThreadTs = ts }
    }

    private func advance() {
        // Fire-and-forget: the step the user is leaving is now completed. Must not block the transition.
        Task { await recordStep(model.step, phase: "completed") }
        if model.step == .getStarted {
            onContinue()
        } else if model.isLastInputStep {
            // Last data step: persist the profile, then slide into the primer only if the save took.
            Task {
                await model.save(api: api)
                if model.didSaveSuccessfully {
                    withAnimation(.easeInOut(duration: 0.3)) { _ = model.advanceStep() }
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { _ = model.advanceStep() }
        }
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.3)) { model.goBack() }
    }
}
