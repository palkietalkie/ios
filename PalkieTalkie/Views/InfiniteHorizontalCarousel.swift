import SwiftUI

/// Horizontal scroller that feels infinite in both directions. Renders `items × copies` virtual entries
/// (100 copies; lazy, so memory stays bounded to what's on screen) and starts the scroll position at the
/// middle copy. The user can swipe ~5,000 cards left or right before hitting an edge — well past any
/// realistic use. We avoid the silent-jump-on-edge trick because it flickers on iOS 26's
/// snap-target scrolling; the deep buffer is the simpler robust answer.
///
/// All cards share a fixed height. Content is already capped by lineLimit, so a fixed bound makes
/// every card visually identical without paying for a measurement pass.
struct InfiniteHorizontalCarousel<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let cardHeight: CGFloat
    @ViewBuilder var content: (Item) -> Content

    @State private var scrollPosition: Int?

    private static var copies: Int {
        100
    }

    init(
        items: [Item],
        spacing: CGFloat = 12,
        cardHeight: CGFloat = 150,
        @ViewBuilder content: @escaping (Item) -> Content,
    ) {
        self.items = items
        self.spacing = spacing
        self.cardHeight = cardHeight
        self.content = content
    }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(0 ..< items.count * Self.copies, id: \.self) { idx in
                        content(items[idx % items.count])
                            .frame(height: cardHeight, alignment: .topLeading)
                            .id(idx)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition(id: $scrollPosition)
            .onAppear {
                if scrollPosition == nil {
                    scrollPosition = items.count * (Self.copies / 2)
                }
            }
        }
    }
}
