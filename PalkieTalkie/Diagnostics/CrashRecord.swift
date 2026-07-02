import Foundation

/// One captured crash, written to disk at crash time and reported on the next launch. Codable so it survives the process death that produced it.
struct CrashRecord: Codable, Equatable {
    /// "nsexception" (uncaught Objective-C exception, e.g. the AVFAudio voice-processing assert) or "signal" (a fatal POSIX signal, e.g. a Swift trap surfacing as SIGTRAP / SIGILL or a bad access as SIGSEGV).
    let kind: String
    /// Exception class name, or signal name like "SIGABRT".
    let name: String
    let reason: String
    /// First stack frame in our own binary, the file+line that actually broke. Empty when no app frame is present.
    let topFrame: String
    let stack: [String]
    let build: String
    let crashedAt: Date

    /// Picks the first stack frame from our binary. The raw frames look like `6 PalkieTalkie 0x… RealInputNode.setVoiceProcessingEnabled + 64 (AudioEngineProtocol.swift:99)`; we keep the symbol + source location and drop the address noise so the Slack line is readable.
    static func topAppFrame(from stack: [String], binaryName: String = "PalkieTalkie") -> String {
        guard let frame = stack.first(where: { $0.contains(binaryName) }) else { return "" }
        // Drop the leading index + binary + address columns; keep "symbol + (File.swift:line)".
        if let range = frame.range(of: #"0x[0-9a-fA-F]+\s+"#, options: .regularExpression) {
            return String(frame[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return frame.trimmingCharacters(in: .whitespaces)
    }

    /// Build a record from an uncaught Objective-C exception. Pure (date injected) so it's unit-tested even though the handler that calls it can only fire on a real crash.
    static func fromException(_ exception: NSException, build: String, at crashedAt: Date) -> CrashRecord {
        CrashRecord(
            kind: "nsexception",
            name: exception.name.rawValue,
            reason: exception.reason ?? "",
            topFrame: topAppFrame(from: exception.callStackSymbols),
            stack: exception.callStackSymbols,
            build: build,
            crashedAt: crashedAt,
        )
    }

    /// Build a record from a fatal POSIX signal. Pure (symbols + date injected) so it's unit-tested.
    static func fromSignal(_ signalNumber: Int32, symbols: [String], build: String, at crashedAt: Date) -> CrashRecord {
        CrashRecord(
            kind: "signal",
            name: signalName(signalNumber),
            reason: "fatal signal \(signalNumber)",
            topFrame: topAppFrame(from: symbols),
            stack: symbols,
            build: build,
            crashedAt: crashedAt,
        )
    }

    static func signalName(_ signalNumber: Int32) -> String {
        switch signalNumber {
        case SIGABRT: "SIGABRT"
        case SIGSEGV: "SIGSEGV"
        case SIGBUS: "SIGBUS"
        case SIGILL: "SIGILL"
        case SIGFPE: "SIGFPE"
        case SIGTRAP: "SIGTRAP"
        default: "SIG\(signalNumber)"
        }
    }
}
