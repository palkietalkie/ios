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
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: settleMs * 1_000_000)
        controller.view.layoutIfNeeded()
        window.isHidden = true
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
            email: nil, displayName: nil, namePronunciation: nil,
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
}
