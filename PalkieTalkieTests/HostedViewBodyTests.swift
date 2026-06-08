@testable import PalkieTalkie
import SwiftUI
import UIKit
import XCTest

/// Mounts every parameterless tab/leaf view inside a UIHostingController so SwiftUI actually evaluates each body. The inspect-based tests pin the contract; these drive the render pipeline to push view-body coverage past what inspection alone reaches.
@MainActor
final class HostedViewBodyTests: XCTestCase {
    private func host(_ view: some View, settleMs: UInt64 = 600) async {
        await TestHosting.host(view, settleMs: settleMs)
    }

    func testProfileViewBody() async {
        UserDefaults.standard.removeObject(forKey: "cache.profile")
        await host(NavigationStack { ProfileView() })
    }

    func testPracticeViewBody() async {
        UserDefaults.standard.removeObject(forKey: "cache.profile")
        await host(NavigationStack { PracticeView() })
    }

    func testPersonaCustomizeViewBody() async {
        await host(NavigationStack { PersonaCustomizeView(persona: nil) })
    }

    func testPersonaCustomizeViewEditModeBody() async {
        let existing = PersonaDTO(
            id: UUID().uuidString,
            name: "MyCoach",
            description: "",
            voiceId: "alloy",
            role: nil,
            age: nil,
            background: nil,
            vocabularyRegister: nil,
            conversationalStyle: nil,
            topicalPreferences: nil,
            isPreset: false,
            isPublic: false,
            isOwner: true,
            likeCount: 0,
            likedByMe: false,
        )
        await host(NavigationStack { PersonaCustomizeView(persona: existing) })
    }

    func testOnboardingViewBody() async {
        await host(NavigationStack { OnboardingView(onContinue: {}) })
    }

    func testSignInViewBody() async {
        await host(SignInView())
    }

    func testPrivacyDataViewBody() async {
        await host(NavigationStack { PrivacyDataView() })
    }

    func testConsentViewBody() async {
        await host(ConsentView(onContinue: {}))
    }

    func testHistoryViewBody() async {
        UserDefaults.standard.removeObject(forKey: "cache.sessions")
        await host(HistoryView())
    }

    func testMistakesViewBody() async {
        UserDefaults.standard.removeObject(forKey: "cache.mistakes")
        await host(NavigationStack { MistakesView() })
    }

    func testPhrasesViewBody() async {
        UserDefaults.standard.removeObject(forKey: "cache.phrases")
        await host(NavigationStack { PhrasesView() })
    }

    func testCEFRDetailViewBody() async {
        await host(NavigationStack { CEFRDetailView() })
    }

    func testLanguagePickerViewBody() async {
        await host(NavigationStack { LanguagePickerView() })
    }

    func testMorePanelViewBody() async {
        await host(MorePanelView())
    }

    func testStatsViewBody() async {
        UserDefaults.standard.removeObject(forKey: "cache.stats")
        await host(NavigationStack { StatsView() })
    }

    func testIntegrationsViewBody() async {
        await host(NavigationStack { IntegrationsView() })
    }
}
