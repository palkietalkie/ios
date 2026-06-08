@testable import PalkieTalkie
import XCTest

final class PersonaPlexClientTests: XCTestCase {
    // MARK: - All 7 frame types decode correctly

    func testDecodeHandshake() {
        let data = Data([0x00, 0x01, 0x02])
        guard case let .handshake(version, model) = PersonaPlexClient.decodeFrame(data) else {
            return XCTFail("expected handshake")
        }
        XCTAssertEqual(version, 0x01)
        XCTAssertEqual(model, 0x02)
    }

    func testDecodeAudio() {
        let opus: [UInt8] = [0xAA, 0xBB, 0xCC]
        let data = Data([0x01] + opus)
        guard case let .audio(payload) = PersonaPlexClient.decodeFrame(data) else {
            return XCTFail("expected audio")
        }
        XCTAssertEqual(Array(payload), opus)
    }

    func testDecodeText() {
        let payload = Data("hello".utf8)
        let data = Data([0x02]) + payload
        guard case let .text(text) = PersonaPlexClient.decodeFrame(data) else {
            return XCTFail("expected text")
        }
        XCTAssertEqual(text, "hello")
    }

    func testDecodeControl() {
        let data = Data([0x03, 0x01]) // endTurn
        guard case let .control(action) = PersonaPlexClient.decodeFrame(data) else {
            return XCTFail("expected control")
        }
        XCTAssertEqual(action, .endTurn)
    }

    func testDecodeMetadata() {
        let payload = Data("{\"k\":1}".utf8)
        let data = Data([0x04]) + payload
        guard case let .metadata(bytes) = PersonaPlexClient.decodeFrame(data) else {
            return XCTFail("expected metadata")
        }
        XCTAssertEqual(bytes, payload)
    }

    func testDecodeError() {
        let payload = Data("oops".utf8)
        let data = Data([0x05]) + payload
        guard case let .error(text) = PersonaPlexClient.decodeFrame(data) else {
            return XCTFail("expected error")
        }
        XCTAssertEqual(text, "oops")
    }

    func testDecodePing() {
        let data = Data([0x06])
        guard case .ping = PersonaPlexClient.decodeFrame(data) else {
            return XCTFail("expected ping")
        }
    }

    func testDecodeUnknownFrameReturnsNil() {
        XCTAssertNil(PersonaPlexClient.decodeFrame(Data([0xFF])))
        XCTAssertNil(PersonaPlexClient.decodeFrame(Data()))
    }

    // MARK: - Round-trip

    func testHandshakeEncodeRoundTrip() {
        let encoded = PersonaPlexClient.encodeHandshake(version: 3, model: 7)
        guard case let .handshake(version, model) = PersonaPlexClient.decodeFrame(encoded) else {
            return XCTFail("expected handshake")
        }
        XCTAssertEqual(version, 3)
        XCTAssertEqual(model, 7)
    }

    func testAudioEncodeRoundTrip() {
        let opus = Data([0x10, 0x20, 0x30])
        let encoded = PersonaPlexClient.encodeAudio(opus)
        guard case let .audio(payload) = PersonaPlexClient.decodeFrame(encoded) else {
            return XCTFail("expected audio")
        }
        XCTAssertEqual(payload, opus)
    }

    func testControlEncodeRoundTrip() {
        for action in [
            PersonaPlexClient.ControlAction.start,
            .endTurn,
            .pause,
            .restart,
        ] {
            let encoded = PersonaPlexClient.encodeControl(action)
            guard case let .control(decoded) = PersonaPlexClient.decodeFrame(encoded) else {
                return XCTFail("expected control")
            }
            XCTAssertEqual(decoded, action)
        }
    }

    func testPingEncodeRoundTrip() {
        let encoded = PersonaPlexClient.encodePing()
        XCTAssertEqual(encoded, Data([0x06]))
        guard case .ping = PersonaPlexClient.decodeFrame(encoded) else {
            return XCTFail("expected ping")
        }
    }

    // MARK: - Ping auto-pong

    /// The contract: receiving a `ping` frame causes the client to send the same single-byte frame back. Verified at
    /// the encoder layer — the transport hop is exercised separately in integration.
    func testPingPongFrameIsSingleByte() {
        let pong = PersonaPlexClient.encodePing()
        XCTAssertEqual(pong.count, 1)
        XCTAssertEqual(pong.first, PersonaPlexClient.FrameType.ping.rawValue)
    }
}
