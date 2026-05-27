@testable import PalkieTalkie
import XCTest

/// In-memory transport for asserting on the request the BackendAPI builds and for feeding canned responses back without
/// touching the network.
final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    var lastRequest: URLRequest?
    var responseData: Data = .init()
    var responseStatus: Int = 200
    var error: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error { throw error }
        let url = request.url ?? URL(string: "https://example.test")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: responseStatus,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (responseData, response)
    }
}

struct StubAuth: AuthTokenProviding {
    let token: String?
    func sessionToken() async throws -> String {
        guard let token else { throw AuthTokenError(reason: "stub: no token") }
        return token
    }
}

final class BackendAPITests: XCTestCase {
    func makeAPI(
        transport: FakeHTTPTransport,
        token: String? = "test-jwt"
    ) -> BackendAPI {
        BackendAPI(
            baseURL: URL(string: "https://api.test")!,
            transport: transport,
            auth: StubAuth(token: token)
        )
    }

    // MARK: - Snake-case encoding

    func testStartConversationEncodesSnakeCase() async throws {
        let transport = FakeHTTPTransport()
        // Canned response so the call resolves.
        let resp = StartResponse(
            sessionId: "s1",
            textPrompt: "hi",
            voiceId: "v",
            wsUrl: "wss://x",
            provider: "personaplex",
            ephemeralToken: nil
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
            calendarEvents: []
        )

        _ = try await api.startConversation(
            personaId: "p1",
            context: context,
            topicOverride: "weather"
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
        let transport = FakeHTTPTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport, token: "abc123")

        _ = try await api.getPersonas()

        let header = transport.lastRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(header, "Bearer abc123")
    }

    func testMissingTokenThrowsNotAuthenticated() async {
        let transport = FakeHTTPTransport()
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
        let transport = FakeHTTPTransport()
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
        let transport = FakeHTTPTransport()
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
        let transport = FakeHTTPTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport)
        _ = try await api.getCEFRWords(level: "B1")
        let url = transport.lastRequest?.url
        XCTAssertEqual(url?.path, "/stats/cefr")
        XCTAssertEqual(url?.query, "level=B1")
    }
}
