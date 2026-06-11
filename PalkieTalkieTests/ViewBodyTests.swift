@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Exercise the `body` of every SwiftUI view in the app so the closure-literals inside ViewBuilder bodies get attributed to coverage. We don't render or assert on the rendered output — the goal is just to walk the view tree once so the expressions inside are reached.
///
/// Views that read from the network on `.task` will hit a real backend during evaluation, but because we never await the .task closure (just construct the body), the network call never fires. Same for `.onAppear` / `.refreshable`.
///
/// Views that need an `Environment` value (e.g. `SessionController`) are instantiated through `UIHostingController(rootView: view.environment(controller))` so the environment is in place before body is read.
@MainActor
final class ViewBodyTests: XCTestCase {
    private func host(_ view: some View) {
        let controller = UIHostingController(rootView: view)
        // Force the SwiftUI view tree to be built and laid out. `loadViewIfNeeded` triggers makeUIView / body evaluation for the entire hierarchy without needing a window.
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        _ = controller.view.intrinsicContentSize
    }

    /// Long-press variant: render the view into a real window so `.task` blocks run, then wait for them to settle before tearing down. Lets us reach the "loaded data" branches whose evaluation depends on the `.task` populating @State. The backend call itself fails fast in the test bundle (no network / no Clerk token) so each `.task` resolves into the error / empty-state branch — which is exactly the branch we want exercised.
    private func hostAndPump(_ view: some View) async {
        await TestHosting.host(view, settleMs: 400)
    }

    private func makeSessionController() -> SessionController {
        SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2026-01-01T00:00:00Z",
                timezone: "UTC", lat: nil, lon: nil,
                city: nil, weatherDescription: nil, temperatureC: nil,
                calendarEvents: [],
            )),
            backend: FakeConversationBackend(
                startResponse: StartResponse(
                    sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "",
                    provider: "personaplex", ephemeralToken: nil,
                ),
                endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
            ),
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
    }

    // MARK: - Tab roots + screen views

    func testRootViewBody() {
        host(RootView())
    }

    func testMainTabViewBody() {
        host(MainTabView().environment(makeSessionController()))
    }

    func testConversationViewBody() {
        host(ConversationView().environment(makeSessionController()))
    }

    func testTalkAboutTodayViewBody() {
        host(TalkAboutTodayView().environment(makeSessionController()))
    }

    func testStatsViewBody() {
        host(StatsView())
    }

    func testPersonaPickerViewBody() {
        host(NavigationStack { PersonaPickerView() }.environment(makeSessionController()))
    }

    func testMorePanelViewBody() {
        host(MorePanelView())
    }

    func testProfileViewBody() {
        host(ProfileView())
    }

    func testIntegrationsViewBody() {
        host(IntegrationsView())
    }

    func testPrivacyDataViewBody() {
        host(NavigationStack { PrivacyDataView() })
    }

    func testLanguagePickerViewBody() {
        host(NavigationStack { LanguagePickerView() })
    }

    func testHistoryViewBody() {
        host(HistoryView())
    }

    func testCEFRDetailViewBody() {
        host(NavigationStack { CEFRDetailView() })
    }

    func testMistakesViewBody() {
        host(NavigationStack { MistakesView() })
    }

    func testPhrasesViewBody() {
        host(NavigationStack { PhrasesView() })
    }

    func testSignInViewBody() {
        host(SignInView())
    }

    // MARK: - Modal screens / customization

    func testConsentViewBody() {
        host(ConsentView(onContinue: {}))
    }

    func testOnboardingViewBody() {
        host(OnboardingView(onContinue: {}))
    }

    func testPersonaCustomizeViewCreateBody() {
        // persona == nil means "creating a new one", which exercises the alternate branch in prefill.
        host(NavigationStack { PersonaCustomizeView(persona: nil) })
    }

    func testPersonaCustomizeViewEditBody() {
        let persona = PersonaDTO(
            id: "p1", name: "Bee", description: "A friendly bee",
            voiceId: "NATM1",
            role: "Curious neighbor", age: "20s", background: "lives in SF",
            vocabularyRegister: "Casual",
            conversationalStyle: "Fast and punchy",
            topicalPreferences: "Tech",
            isPreset: false, isPublic: true, isOwner: true,
            likeCount: 0, likedByMe: false,
        )
        host(NavigationStack { PersonaCustomizeView(persona: persona) })
    }

    func testPersonaCustomizeViewWithCustomVocabBody() {
        // Branch where vocabulary_register is NOT in the preset enum → goes into vocabularyCustom.
        let persona = PersonaDTO(
            id: "p2", name: "Sea", description: "",
            voiceId: "NATM2",
            role: nil, age: nil, background: nil,
            vocabularyRegister: "Surfer slang",
            conversationalStyle: "Drawly and chill",
            topicalPreferences: nil,
            isPreset: false, isPublic: false, isOwner: true,
            likeCount: 5, likedByMe: false,
        )
        host(NavigationStack { PersonaCustomizeView(persona: persona) })
    }

    // MARK: - Multi-language picker

    func testMultiLanguagePickerBody() {
        @State var selection: Set = ["Japanese"]
        let view = MultiLanguagePicker(
            languages: [
                LanguageDTO(name: "English", accents: ["US"]),
                LanguageDTO(name: "Japanese", accents: ["Tokyo"]),
            ],
            selection: $selection,
            title: "Native languages",
        )
        host(NavigationStack { view })
    }

    // MARK: - Carousel + cards

    func testInfiniteHorizontalCarouselWithItems() {
        struct Item: Identifiable { let id: Int; let text: String }
        let items = (0 ..< 3).map { Item(id: $0, text: "card \($0)") }
        host(InfiniteHorizontalCarousel(items: items, cardHeight: 120) { item in
            Text(item.text)
        })
    }

    func testInfiniteHorizontalCarouselEmptyRendersEmptyView() {
        struct Item: Identifiable { let id: Int }
        let items: [Item] = []
        host(InfiniteHorizontalCarousel(items: items) { _ in
            Text("nope")
        })
    }

    // MARK: - LoadingTipsView

    func testLoadingTipsBodyWithInjectedTips() {
        host(LoadingTipsView(tips: ["Try saying 'wanna' for casual speech.", "Pause for breath at commas."]))
    }

    func testLoadingTipsBodyWithDefaultTips() {
        // Falls back to "Loading your tutor…" when Bundle.main lookup fails inside test bundle.
        host(LoadingTipsView())
    }

    // MARK: - Stats metric explainer

    func testMetricExplainerSheetBody() {
        host(MetricExplainerSheet(info: .minutes))
        host(MetricExplainerSheet(info: .uniqueWords))
        host(MetricExplainerSheet(info: .speakingRate))
        host(MetricExplainerSheet(info: .cefr))
    }

    // MARK: - Long-running .task variants for views that depend on backend data

    // These tests host the view in a real window long enough for `.task` modifiers to run their first iteration. The backend call resolves into an error or empty-state inside the test bundle (no network / no Clerk token), which drives the error / empty-state branches of the view tree that the no-pump variants never reach.

    func testStatsViewAfterTaskRunsErrorPath() async {
        await hostAndPump(StatsView())
    }

    func testPersonaPickerViewAfterTaskRunsEmptyPath() async {
        await hostAndPump(NavigationStack { PersonaPickerView() }.environment(makeSessionController()))
    }

    func testTalkAboutTodayViewAfterTaskRunsErrorPath() async {
        await hostAndPump(TalkAboutTodayView().environment(makeSessionController()))
    }

    func testHistoryViewAfterTaskRunsErrorPath() async {
        await hostAndPump(HistoryView())
    }

    func testIntegrationsViewAfterTask() async {
        await hostAndPump(IntegrationsView())
    }

    func testMistakesViewAfterTaskRunsErrorPath() async {
        await hostAndPump(NavigationStack { MistakesView() })
    }

    func testPhrasesViewAfterTask() async {
        await hostAndPump(NavigationStack { PhrasesView() })
    }

    func testCEFRDetailViewAfterTask() async {
        await hostAndPump(NavigationStack { CEFRDetailView() })
    }

    func testProfileViewAfterTask() async {
        await hostAndPump(ProfileView())
    }

    func testPersonaCustomizeViewAfterTask() async {
        await hostAndPump(NavigationStack { PersonaCustomizeView(persona: nil) })
    }

    func testPrivacyDataViewAfterTask() async {
        await hostAndPump(NavigationStack { PrivacyDataView() })
    }

    func testOnboardingViewAfterTask() async {
        await hostAndPump(OnboardingView(onContinue: {}))
    }

    func testRootViewAfterTask() async {
        await hostAndPump(RootView())
    }
}
