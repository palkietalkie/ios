import SwiftUI

/// First-launch flow that captures `nativeLanguages`, `targetLanguage`, and `targetAccents` before letting the user into the main app. Presented as a step-by-step wizard — one decision per screen, animated — rather than a single Form: the form read as data entry, the wizard reads as a guided setup and lets each step explain *why* it's asked. Other profile fields keep server defaults and are editable later in Profile.
@MainActor
struct OnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.backendAPI) private var api
    @State private var model: OnboardingViewModel

    init(onContinue: @escaping () -> Void, model: OnboardingViewModel = OnboardingViewModel()) {
        self.onContinue = onContinue
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .background(Color(.systemBackground))
        .task {
            guard !model.didInitialLoad else { return }
            model.didInitialLoad = true
            await model.load(api: api)
        }
        .overlay { if model.loading { ProgressView() } }
        .onChange(of: model.didSaveSuccessfully) { _, done in
            if done { onContinue() }
        }
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
            .opacity(model.step == .native ? 0 : 1)
            .disabled(model.step == .native)

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

    @ViewBuilder private var currentStep: some View {
        switch model.step {
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
            Button {
                advance()
            } label: {
                Text(model.isLastStep ? "Get started" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.stepValid || model.saving)
        }
        .padding()
    }

    // MARK: - Navigation (animation only; the logic lives in the model)

    private func advance() {
        if model.isLastStep {
            Task { await model.save(api: api) }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { model.advanceStep() }
        }
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.3)) { model.goBack() }
    }
}

/// One wizard step: large title, a one-line reason it's asked, then the selectable content. The reason turns "fill this field" into "here's why" — onboarding research shows users abandon fields whose purpose is opaque.
@MainActor
private struct StepScaffold<Content: View>: View {
    let title: LocalizedStringKey
    let why: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold())
            Text(why).font(.callout).foregroundStyle(.secondary)
            content.padding(.top, 8)
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
}

/// Spacious tap-to-select list used by every wizard step (replaces the pushed `MultiLanguagePicker`, so there's no sub-screen to "save and back" out of). Single- vs multi-select is the caller's concern via `isSelected`/`onTap`.
@MainActor
private struct ChoiceList: View {
    let options: [String]
    let isSelected: (String) -> Bool
    /// Maps the wire value (English language/accent name) to its localized display. The raw `option` stays the selection key; only the label is localized.
    var display: (String) -> String = { $0 }
    let onTap: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    let selected = isSelected(option)
                    HStack {
                        Text(display(option)).foregroundStyle(.primary)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground)),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5),
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(option) }
                }
            }
            .padding(.bottom, 8)
        }
    }
}
