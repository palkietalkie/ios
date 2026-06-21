import SwiftUI

/// One wizard step: large title, a one-line reason it's asked, then the selectable content. The reason turns "fill this field" into "here's why" — onboarding research shows users abandon fields whose purpose is opaque.
@MainActor
struct StepScaffold<Content: View>: View {
    let title: LocalizedStringKey
    let why: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold())
            Text(why).font(.callout).foregroundStyle(.secondary)
            content.padding(.top, 8)
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
}
