import Foundation

/// Captures a crash the moment it happens and reports it on the next launch, because a crash aborts the process, so nothing can be sent live (this is how Crashlytics / Sentry work too: capture now, deliver next launch).
///
/// Two capture paths:
/// - NSSetUncaughtExceptionHandler catches uncaught Objective-C NSExceptions (e.g. the AVFAudio voice-processing assert that crashed the Talk screen). This runs in a near-normal context, so it captures the full name + reason + stack reliably.
/// - POSIX signal handlers catch fatal signals (Swift traps surfacing as SIGTRAP/SIGILL, bad access as SIGSEGV, abort as SIGABRT). Best-effort only: a signal handler is not strictly async-signal-safe, so the Foundation calls here can occasionally fail mid-crash. The NSException path is the reliable one and covers our known crash class; signals are a bonus net.
enum CrashReporter {
    // C function-pointer handlers can't capture context, so the store + build they write live in process-global statics set by install().
    private nonisolated(unsafe) static var store: CrashStore = .default
    private nonisolated(unsafe) static var build = "?"

    private static let fatalSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]

    static func install(build: String, store: CrashStore = .default) {
        self.store = store
        self.build = build

        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.store.save(CrashRecord.fromException(exception, build: CrashReporter.build, at: Date()))
        }

        for fatalSignal in fatalSignals {
            signal(fatalSignal) { signalNumber in
                let record = CrashRecord.fromSignal(
                    signalNumber, symbols: Thread.callStackSymbols, build: CrashReporter.build, at: Date(),
                )
                CrashReporter.store.save(record)
                // Restore the default handler and re-raise so the OS still writes its own crash report (and TestFlight still collects it).
                signal(signalNumber, SIG_DFL)
                raise(signalNumber)
            }
        }
    }

    /// On launch: if a crash was captured before, hand it to `post` (the upload). Clear it only on a successful upload, so a failed send (e.g. not signed in yet) keeps the record to retry next launch. Returns whether one was reported.
    @discardableResult
    static func reportPending(store: CrashStore = .default, post: @Sendable (CrashRecord) async -> Bool) async -> Bool {
        guard let record = store.load() else { return false }
        let delivered = await post(record)
        if delivered { store.clear() }
        return delivered
    }
}
