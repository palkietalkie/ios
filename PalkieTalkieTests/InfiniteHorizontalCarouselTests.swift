@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class InfiniteHorizontalCarouselTests: XCTestCase {
    struct CarouselItem: Identifiable, Equatable {
        let id: Int
    }

    /// Empty `items` collapses to `EmptyView()` rather than rendering an empty ScrollView. The "no content yet" branch is critical: if the caller has zero items and the view renders a scroll container anyway, there's a thin invisible focus target the user can hit. Lock the branch.
    func testEmptyItemsRendersEmptyView() {
        let view = InfiniteHorizontalCarousel(items: [] as [CarouselItem], cardHeight: 100) { _ in
            Text("never used")
        }
        // ScrollView's presence would indicate the body did not collapse to EmptyView.
        XCTAssertNil(try? view.inspect().scrollView())
    }

    /// Non-empty `items` wraps content in a ScrollView with a LazyHStack inside. This is the "infinite" engine — a refactor that downgrades to a regular HStack would defeat the lazy memory bound the comment promises (only what's on screen).
    func testNonEmptyItemsRendersScrollViewWithLazyHStack() throws {
        let items = (0 ..< 3).map { CarouselItem(id: $0) }
        let view = InfiniteHorizontalCarousel(items: items, cardHeight: 100) { item in
            Text("\(item.id)")
        }
        XCTAssertNoThrow(try view.inspect().scrollView().lazyHStack())
    }

    /// The buffer renders `items.count × 100` virtual entries — that's the "feels infinite" depth (~5,000 cards each way) the doc comment promises. Counting the ForEach children here locks the copies multiplier: if a refactor drops it to a single copy, the swipe runway collapses and this fails.
    func testRendersHundredCopiesOfEachItem() throws {
        let items = (0 ..< 3).map { CarouselItem(id: $0) }
        let view = InfiniteHorizontalCarousel(items: items, cardHeight: 100) { item in
            Text("\(item.id)")
        }
        let forEach = try view.inspect().scrollView().lazyHStack().forEach(0)
        XCTAssertEqual(forEach.count, items.count * 100)
    }
}
