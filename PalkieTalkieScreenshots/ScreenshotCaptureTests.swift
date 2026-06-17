import XCTest

/// Drives the real app to produce App Store screenshots at the connected simulator's native resolution (run on iPhone 17 Pro Max for Apple's required 6.9" / 1320x2868). Signs in with a Clerk dev test email (`+clerk_test`, fixed code `424242`, no real inbox — same path as `ClerkEmailAuthE2ETests`), walks the one-time consent + onboarding gates, then captures each featured tab as a `.keepAlways` attachment. `scripts/capture-screenshots.sh` extracts the PNGs from the resulting `.xcresult`.
///
/// Must run SIGNED (Clerk needs a keychain) and against the dev backend (Debug config). Microphone/location are pre-granted by the capture script via `simctl privacy`, with an interruption monitor as a fallback.
final class ScreenshotCaptureTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() {
        let app = XCUIApplication()
        // Tip-of-the-hat fallback if a permission dialog still appears despite the pre-grant.
        addUIInterruptionMonitor(withDescription: "system-permission") { alert in
            for label in ["Allow", "Allow While Using App", "OK"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.launch()

        signIn(app)
        passConsentIfPresent(app)
        passOnboardingIfPresent(app)

        // Persona picker — rich (presets always populated), so it's a reliable hero among the three.
        tapTab(app, "Persona")
        capture(app, name: "02-persona")

        tapTab(app, "Stats")
        capture(app, name: "03-stats")

        captureTalkLive(app)
    }

    @MainActor
    private func captureTalkLive(_ app: XCUIApplication) {
        // Talk last: returning to it starts a fresh session (leaving the tab ends the prior one).
        tapTab(app, "Talk")
        // Captions are off by default (voice-first); turn them on so the AI's opening turn is visible text in the shot.
        let cc = app.buttons["CC"]
        if cc.waitForExistence(timeout: 5) { cc.tap() }
        // Wait out cold start: the AI opens the conversation on its own, so once "Loading your tutor..." clears, a transcript follows shortly.
        let loading = app.staticTexts["Loading your tutor..."]
        let deadline = Date().addingTimeInterval(60)
        while loading.exists, Date() < deadline {
            _ = loading.waitForNonExistence(timeout: 5)
        }
        // Give the AI a beat to speak its opening sentence so captions have content. The app runs in its own process, so blocking the test process here doesn't freeze the UI being captured.
        Thread.sleep(forTimeInterval: 7)
        capture(app, name: "01-talk")
    }

    // MARK: - Steps

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        // A persisted Clerk session means the app can launch past sign-in straight to consent/onboarding/main; only drive sign-in when its screen actually shows.
        let email = app.textFields["Email"]
        guard email.waitForExistence(timeout: 20) else { return }
        email.tap()
        // Fixed Clerk dev test email → a STABLE backend user across runs, so its data (mirrored from the founder's dev account) survives the app uninstall the capture script does for a clean local state.
        email.typeText("pt_shots+clerk_test@gitauto.ai")
        app.buttons["Send email code"].tap()

        let code = app.textFields["Verification code"]
        XCTAssertTrue(code.waitForExistence(timeout: 30), "code field never appeared")
        code.tap()
        code.typeText("424242")
        app.buttons["Verify"].tap()
    }

    @MainActor
    private func passConsentIfPresent(_ app: XCUIApplication) {
        // Toggles default ON; just accept. Consent's Continue and onboarding's Continue share a label, so key off the consent-only toggle first.
        let consentToggle = app.switches["Personalize my experience"]
        if consentToggle.waitForExistence(timeout: 20) {
            app.buttons["Continue"].tap()
        }
    }

    @MainActor
    private func passOnboardingIfPresent(_ app: XCUIApplication) {
        // Wizard: native -> target -> accents. Each step needs >=1 selection to enable the primary button.
        guard app.staticTexts["What's your native language?"].waitForExistence(timeout: 20) else { return }
        selectFirstChoice(app)
        app.buttons["Continue"].tap()

        _ = app.staticTexts["What do you want to learn?"].waitForExistence(timeout: 10)
        selectFirstChoice(app)
        app.buttons["Continue"].tap()

        _ = app.staticTexts["Which accents?"].waitForExistence(timeout: 10)
        if app.buttons["Select all"].waitForExistence(timeout: 5) {
            app.buttons["Select all"].tap()
        } else {
            selectFirstChoice(app)
        }
        app.buttons["Get started"].tap()
    }

    // MARK: - Helpers

    @MainActor
    private func selectFirstChoice(_ app: XCUIApplication) {
        // ChoiceList rows are .onTapGesture HStacks (not buttons), so the addressable element is the row's text; the choices live inside the ScrollView while the step title/why sit outside it.
        let firstChoice = app.scrollViews.staticTexts.element(boundBy: 0)
        if firstChoice.waitForExistence(timeout: 8) {
            firstChoice.tap()
        }
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, _ label: String) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "tab \(label) never appeared")
        tab.tap()
        // Let the tab's content settle before the shot.
        _ = app.wait(for: .runningForeground, timeout: 2)
    }

    @MainActor
    private func capture(_: XCUIApplication, name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
