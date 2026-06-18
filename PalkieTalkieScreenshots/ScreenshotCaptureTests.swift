import XCTest

/// Drives the real app to produce App Store screenshots at the connected simulator's native resolution (run on iPhone 17 Pro Max for Apple's required 6.9" / 1320x2868). Signs in with a Clerk dev test email (`+clerk_test`, fixed code `424242`, no real inbox, same path as `ClerkEmailAuthE2ETests`), walks the one-time consent + onboarding gates, then tours the tabs plus the Stats and More sub-screens, capturing each as a `.keepAlways` attachment. `scripts/capture-screenshots.sh` extracts the PNGs from the resulting `.xcresult`.
///
/// Must run SIGNED (Clerk needs a keychain) and against the dev backend (Debug config). Microphone/location are pre-granted by the capture script via `simctl privacy`, with an interruption monitor as a fallback. The signed-in account is seeded with real data so Stats/Mistakes/Phrases/CEFR render populated.
final class ScreenshotCaptureTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() {
        let app = XCUIApplication()
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
        // Pin the persona via NSUserDefaults' argument domain (a `-key value` launch arg overrides the persisted key). Talk is the default tab, so the app auto-starts a session on launch using `lastSelectedPersonaId`; without this it picks the first preset ("A man"), which then tops the History list and headlines the Talk-live shot. Pinning the badminton coach makes the auto-started session, the History top row, and the Talk-live capture all show a real persona.
        app.launchArguments += ["-lastSelectedPersonaId", "5d237e71-c5f3-53fb-80f9-e234a819b7d7"]
        app.launch()

        signIn(app)
        passConsentIfPresent(app)
        passOnboardingIfPresent(app)

        // Filename prefix (NN-) is the App Store display order; capture order below is just what's convenient.
        tapTab(app, "Persona")
        capture(app, name: "02-persona")

        tapTab(app, "Topics")
        capture(app, name: "04-topics")

        tapTab(app, "Stats")
        capture(app, name: "03-stats")
        captureSubScreen(app, row: "Frequent mistakes", name: "05-mistakes")
        captureSubScreen(app, row: "Frequent phrases", name: "06-phrases")
        captureSubScreen(app, row: "CEFR detail", name: "07-cefr")

        tapTab(app, "More")
        captureSubScreen(app, row: "Profile", name: "08-profile")
        // Subscription screen deliberately skipped: shows "Upgrades not available yet" until the IAPs clear review.
        captureSubScreen(app, row: "Past conversations", name: "09-history")

        captureTalkLive(app)
    }

    // MARK: - Steps

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let email = app.textFields["Email"]
        guard email.waitForExistence(timeout: 20) else { return }
        email.tap()
        // Fixed Clerk dev test email -> a STABLE backend user across runs, so its seeded data survives the app uninstall the capture script does for a clean local state.
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
        let consentToggle = app.switches["Personalize my experience"]
        if consentToggle.waitForExistence(timeout: 20) {
            app.buttons["Continue"].tap()
        }
    }

    @MainActor
    private func passOnboardingIfPresent(_ app: XCUIApplication) {
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

    @MainActor
    private func captureTalkLive(_ app: XCUIApplication) {
        tapTab(app, "Talk")
        let cc = app.buttons["CC"]
        if cc.waitForExistence(timeout: 5) { cc.tap() }
        let loading = app.staticTexts["Loading your tutor..."]
        let deadline = Date().addingTimeInterval(60)
        while loading.exists, Date() < deadline {
            _ = loading.waitForNonExistence(timeout: 5)
        }
        // Let the AI speak its opening sentence so captions have content. The app runs in its own process, so blocking the test process doesn't freeze the captured UI.
        Thread.sleep(forTimeInterval: 7)
        capture(app, name: "01-talk")
    }

    // MARK: - Helpers

    @MainActor
    private func selectFirstChoice(_ app: XCUIApplication) {
        // ChoiceList rows are .onTapGesture HStacks (not buttons); the addressable element is the row's text inside the ScrollView.
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
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    private func captureSubScreen(_ app: XCUIApplication, row: String, name: String) {
        // Push a NavigationLink row by its label, capture, then pop via the nav bar back button.
        let link = app.buttons[row]
        guard link.waitForExistence(timeout: 10) else { return }
        link.tap()
        // Detail screens fetch over the network; wait long enough that data lands before the shot (1.5s caught the empty state).
        Thread.sleep(forTimeInterval: 4.5)
        capture(app, name: name)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        Thread.sleep(forTimeInterval: 0.8)
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
