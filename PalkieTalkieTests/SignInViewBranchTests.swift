@testable import PalkieTalkie
import SwiftUI
import UIKit
import ViewInspector
import XCTest

/// View-level wiring: SignInView's Apple/Google buttons must route to the injected SignInService. Flow logic itself is covered exhaustively in SignInViewModelTests; these pin that the buttons are actually connected.
@MainActor
final class SignInViewBranchTests: XCTestCase {
    func testSignInViewRenders() async {
        await TestHosting.host(SignInView(service: FakeSignInService(), announcer: FakeAuthAnnouncer()))
    }

    func testSignInViewInWindowSurvivesLayout() async {
        await TestHosting.host(SignInView(service: FakeSignInService(), announcer: FakeAuthAnnouncer()), settleMs: 500)
    }

    func testTapAppleButtonReachesService() async throws {
        let svc = FakeSignInService()
        let sut = SignInView(service: svc, announcer: FakeAuthAnnouncer())
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        // Apple is the first button per body source order.
        try buttons[0].tap()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(svc.appleCalls, 1)
    }

    func testTapGoogleButtonReachesService() async throws {
        let svc = FakeSignInService()
        let sut = SignInView(service: svc, announcer: FakeAuthAnnouncer())
        let buttons = try sut.inspect().findAll(ViewType.Button.self)
        try buttons[1].tap()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(svc.googleCalls, 1)
    }
}
