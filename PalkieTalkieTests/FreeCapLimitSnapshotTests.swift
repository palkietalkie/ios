@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Renders FreeCapLimitView to PNGs (daily + weekly wording) so the screen can be eyeballed without hitting a real cap in the app. Writes to ios/snapshots/ (tracked), derived from #filePath so the destination is deterministic regardless of where the test runs. Not an assertion test, a visual aid.
@MainActor
final class FreeCapLimitSnapshotTests: XCTestCase {
    func testRenderDailyAndWeekly() throws {
        // .../ios/PalkieTalkieTests/FreeCapLimitSnapshotTests.swift → .../ios/snapshots
        let snapshotsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("snapshots")
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        for kind in ["daily", "weekly"] {
            // ImageRenderer renders detached from the app bundle, so the global AccentColor asset isn't resolved and Color.accentColor would fall back to SwiftUI's default blue. Inject the brand tint explicitly so the PNG shows the coral the running app actually paints.
            let view = FreeCapLimitView(limitKind: kind, onUpgrade: {}, onDismiss: {})
                .tint(Color.brandCoral)
                .frame(width: 393, height: 852)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage, "ImageRenderer produced no image")
            let png = try XCTUnwrap(image.pngData())
            let url = snapshotsDir.appendingPathComponent("freecap-\(kind).png")
            try png.write(to: url)
            print("WROTE \(url.path)")
        }
    }
}
