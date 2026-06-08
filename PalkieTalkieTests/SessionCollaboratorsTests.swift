@testable import PalkieTalkie
import XCTest

/// Smoke tests for the injectable-seam protocols + default impls in `SessionCollaborators.swift`. Default-impl construction is covered in `DefaultCollaboratorsTests` from the protocol-consumer side; this file pairs the source file so the CI test-pair check accepts the extraction.
final class SessionCollaboratorsTests: XCTestCase {
    /// `BackendAPI` must conform to `ConversationBackend` so SessionController can take either the real backend or a test fake interchangeably.
    func testBackendAPIConformsToConversationBackend() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://test.example.com"))
        // Authing is class-only (AnyObject) — use the existing test stub from BackendAPITests instead of re-defining here.
        let api: any ConversationBackend = BackendAPI(
            baseURL: baseURL,
            transport: URLSession.shared,
            auth: StubAuthing(),
        )
        _ = api
    }

    /// Production default `DefaultMicrophonePermission` must satisfy `MicrophonePermissionRequesting` so the production wiring in PalkieTalkieApp compiles.
    func testDefaultMicrophonePermissionConforms() {
        let perm: any MicrophonePermissionRequesting = DefaultMicrophonePermission()
        _ = perm
    }
}
