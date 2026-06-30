import XCTest

/// Source-scanning guard: every INLINE error message must be `.textSelection(.enabled)` so users can SELECT it and then copy / translate / look it up (not just copy) when an error is in their way. SwiftUI gives no way to assert the modifier at runtime without ViewInspector, so we lint the source instead — this catches the regression "added a new error display, forgot to make it selectable".
///
/// Scope: inline error `Text(...)` (those referencing a `*Error` variable or a "Couldn't …" error string). Alert/confirmationDialog `message:` closures are exempt — `.textSelection` is a no-op in a system alert, so those are skipped via the `message:` lookback.
final class ErrorTextSelectableTests: XCTestCase {
    func testInlineErrorMessagesAreSelectable() throws {
        let viewsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PalkieTalkieTests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("PalkieTalkie/Views")
        let files = try FileManager.default
            .contentsOfDirectory(at: viewsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        var violations: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                guard isErrorText(line) else { continue }
                // Alert message: closures can't select-to-copy; skip them.
                let lookback = lines[max(0, i - 3) ... i].joined(separator: "\n")
                if lookback.contains("message:") { continue }
                // The modifier chain can spill onto the next couple lines.
                let chain = lines[i ... min(lines.count - 1, i + 3)].joined(separator: " ")
                if !chain.contains(".textSelection(.enabled)") {
                    violations.append(
                        "\(file.lastPathComponent):\(i + 1)  \(line.trimmingCharacters(in: .whitespaces))",
                    )
                }
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "Inline error messages must be copyable — add .textSelection(.enabled):\n"
                + violations.joined(separator: "\n"),
        )
    }

    /// An inline error `Text(...)`: references a `*Error` variable (loadError / saveError / kgError) or a "Couldn't …" error string.
    private func isErrorText(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("Text(") else { return false }
        return t.contains("Error") || t.contains("Couldn't")
    }
}
