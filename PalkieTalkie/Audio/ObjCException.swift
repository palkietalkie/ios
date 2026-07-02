import Foundation

/// Swift-ergonomic front door to the Objective-C `PTRunCatchingNSException` shim. Converts a raised NSException (uncatchable in Swift, otherwise SIGABRT) into a thrown Swift `Error` so normal do/catch handling works.
enum ObjCException {
    static func catching(_ body: @escaping () -> Void) throws {
        var raised: NSError?
        let ok = PTRunCatchingNSException(body, &raised)
        if !ok {
            throw raised ?? NSError(domain: "com.palkietalkie.ObjCException", code: 0)
        }
    }
}
