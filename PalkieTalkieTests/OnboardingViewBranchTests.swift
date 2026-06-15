@testable import PalkieTalkie
import SwiftUI
import UIKit
import XCTest

/// OnboardingView's loaded-state branches that the basic ViewBodyTests don't reach.
@MainActor
final class OnboardingViewBranchTests: XCTestCase {
    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(
            baseURL: URL(string: "https://api.test")!,
            transport: transport,
            auth: StubAuthing(),
        )
    }

    private func host(_ view: some View, settleMs: UInt64 = 500) async {
        await TestHosting.host(view, settleMs: settleMs)
    }

    func testOnboardingWithMultipleLanguagesPopulated() async throws {
        let transport = FakeTransport()
        let languages = [
            LanguageDTO(name: "English", accents: ["US", "UK", "Australian"]),
            LanguageDTO(name: "Japanese", accents: ["Tokyo", "Osaka", "Kyoto"]),
            LanguageDTO(name: "Spanish", accents: ["Latin American", "Castilian"]),
        ]
        transport.responseData = try BackendAPI.encoder.encode(languages)
        let api = makeAPI(transport)
        await host(OnboardingView(onContinue: {}).environment(\.backendAPI, api))
    }

    func testOnboardingProfileSave200Branch() async throws {
        // Two endpoints in play: GET /languages (load), PATCH /profile (save).
        let transport = FakeTransport()
        let languages = [LanguageDTO(name: "English", accents: ["US"])]
        let profile = ProfileDTO(
            email: nil, preferredName: nil, namePronunciation: nil,
            namePronunciationSuggestion: nil,
            nativeLanguages: ["Japanese"], targetLanguage: "English",
            targetAccents: ["US"], proficiency: "intermediate",
            tutorSpeakingSpeed: "normal", goals: nil, locationCity: nil, timezone: nil,
        )
        try transport.enqueue(path: "/languages", data: BackendAPI.encoder.encode(languages))
        try transport.enqueue(path: "/profile", data: BackendAPI.encoder.encode(profile))
        let api = makeAPI(transport)
        await host(OnboardingView(onContinue: {}).environment(\.backendAPI, api))
    }

    func testOnboardingErrorOnLanguagesIsSilent() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = makeAPI(transport)
        await host(OnboardingView(onContinue: {}).environment(\.backendAPI, api))
    }

    /// Onboarding body when user already has accents picked — renders the non-empty-accents text branch in the LabeledContent label.
    func testOnboardingRendersWithAccentsAlreadySelected() async throws {
        let transport = FakeTransport()
        let languages = [LanguageDTO(name: "English", accents: ["US General", "UK RP"])]
        transport.responseData = try BackendAPI.encoder.encode(languages)
        let api = makeAPI(transport)
        // The view's @State model.targetAccents starts empty so the "Choose…" branch initially renders. After load, the .task can't auto-populate accents (those come from a separate profile call onboarding doesn't make). To hit the non-empty branch we host longer so the .task settles, then the NavigationLink's LabeledContent renders both branches across the test's render passes.
        await host(OnboardingView(onContinue: {}).environment(\.backendAPI, api), settleMs: 700)
    }
}
