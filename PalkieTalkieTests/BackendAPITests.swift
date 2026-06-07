@testable import PalkieTalkie
import XCTest

/// In-memory transport for asserting on the request the BackendAPI builds and for feeding canned responses back without
/// touching the network. Holds a stack of canned `(Data, URLResponse)` keyed by URL path for tests that drive multiple
/// endpoints in one flow (e.g. View tests that load profile + languages + practice-options in one task).
final class FakeTransport: Transport, @unchecked Sendable {
    struct CannedResponse {
        let data: Data
        let status: Int
        init(data: Data, status: Int = 200) {
            self.data = data
            self.status = status
        }
    }

    /// Path-pattern (substring match) → response. First matching pattern wins; "" matches anything (default fallback).
    var responses: [(pattern: String, response: CannedResponse)] = []
    /// Single fallback when no pattern matches and no `responses` are registered. Backwards-compatible with the
    /// previous single-response shape.
    var responseData: Data = .init()
    var responseStatus: Int = 200
    var error: Error?

    var lastRequest: URLRequest?
    var requests: [URLRequest] = []

    func enqueue(path pattern: String, data: Data, status: Int = 200) {
        responses.append((pattern, CannedResponse(data: data, status: status)))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        requests.append(request)
        if let error { throw error }
        let url = request.url ?? URL(string: "https://example.test")!
        let path = url.path
        let match = responses.first(where: { entry in
            entry.pattern.isEmpty || path.contains(entry.pattern)
        })
        let data = match?.response.data ?? responseData
        let status = match?.response.status ?? responseStatus
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"],
        )!
        return (data, response)
    }
}

/// Test conformer for `Authing`. Returns a fixed token + user id; signOut records the call so View tests can assert
/// the destructive Sign out button was tapped.
final class StubAuthing: Authing, @unchecked Sendable {
    let token: String?
    let _userId: String?
    let _email: String?
    var signOutCount = 0

    init(token: String? = "test-jwt", userId: String? = "u_test", email: String? = "test@example.com") {
        self.token = token
        _userId = userId
        _email = email
    }

    var userId: String? {
        get async { _userId }
    }

    var email: String? {
        get async { _email }
    }

    func sessionToken() async throws -> String {
        guard let token else { throw AuthTokenError(reason: "stub: no token") }
        return token
    }

    func signOut() async {
        signOutCount += 1
    }
}

final class BackendAPITests: XCTestCase {
    func makeAPI(
        transport: FakeTransport,
        token: String? = "test-jwt",
    ) -> BackendAPI {
        BackendAPI(
            baseURL: URL(string: "https://api.test")!,
            transport: transport,
            auth: StubAuthing(token: token),
        )
    }

    // MARK: - Snake-case encoding

    func testStartConversationEncodesSnakeCase() async throws {
        let transport = FakeTransport()
        // Canned response so the call resolves.
        let resp = StartResponse(
            sessionId: "s1",
            textPrompt: "hi",
            voiceId: "v",
            wsUrl: "wss://x",
            provider: "personaplex",
            ephemeralToken: nil,
        )
        transport.responseData = try BackendAPI.encoder.encode(resp)
        let api = makeAPI(transport: transport)
        let context = ConversationContext(
            localISOTime: "2025-01-01T00:00:00Z",
            timezone: "UTC",
            lat: 37.7,
            lon: -122.4,
            city: nil,
            weatherDescription: nil,
            temperatureC: nil,
            calendarEvents: [],
        )

        _ = try await api.startConversation(
            personaId: "p1",
            context: context,
            topicOverride: "weather",
        )

        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        // Camel→snake conversion is the load-bearing invariant for backend compatibility.
        XCTAssertEqual(json["persona_id"] as? String, "p1")
        XCTAssertEqual(json["topic_override"] as? String, "weather")
        XCTAssertEqual(json["lat"] as? Double, 37.7)
        XCTAssertEqual(json["lon"] as? Double, -122.4)
        XCTAssertNil(json["personaId"])
    }

    // MARK: - Auth header

    func testAuthHeaderAttached() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport, token: "abc123")

        _ = try await api.getPersonas()

        let header = transport.lastRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(header, "Bearer abc123")
    }

    func testMissingTokenThrowsNotAuthenticated() async {
        let transport = FakeTransport()
        let api = makeAPI(transport: transport, token: nil)
        do {
            _ = try await api.getPersonas()
            XCTFail("expected throw")
        } catch let BackendError.notAuthenticated(reason) {
            XCTAssertEqual(reason, "stub: no token")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Error decoding

    func testHTTPErrorDecoded() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = makeAPI(transport: transport)
        do {
            _ = try await api.getPersonas()
            XCTFail("expected throw")
        } catch let BackendError.http(code, body) {
            XCTAssertEqual(code, 500)
            XCTAssertEqual(body, "boom")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testDecodingErrorWrapped() async {
        let transport = FakeTransport()
        transport.responseData = Data("not json".utf8)
        let api = makeAPI(transport: transport)
        do {
            _ = try await api.getPersonas()
            XCTFail("expected throw")
        } catch let BackendError.decoding(message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Path / query handling

    func testGetCEFRWordsKeepsQueryString() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport)
        _ = try await api.getCEFRWords(level: "B1")
        let url = transport.lastRequest?.url
        XCTAssertEqual(url?.path, "/stats/cefr")
        XCTAssertEqual(url?.query, "level=B1")
    }
}
