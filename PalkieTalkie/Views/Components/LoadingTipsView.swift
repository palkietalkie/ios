import SwiftUI

/// Flippable English speaking tips displayed while the inference container is cold-starting (gatheringContext /
/// startingSession / connecting phases).
/// Tips rotate every 8 seconds, shuffled per session. The shuffle and timer live in `@State` so they survive parent
/// re-evaluations — otherwise every phase change would reshuffle and restart the timer, making tips flash by in 1-2s
/// instead of 8s.
struct LoadingTipsView: View {
    private static let rotationInterval: TimeInterval = 8

    // @State initialized in init via _shuffledTips = State(initialValue: ...). This is the SwiftUI-supported way to
    // give a State a non-default initial value AND have it survive parent re-evaluations — using a plain `let` would
    // reshuffle every time the parent re-renders this view.
    @State private var shuffledTips: [String]
    @State private var index: Int = 0

    init(tips: [String]? = nil) {
        let source: [String] = if let tips, !tips.isEmpty {
            tips
        } else {
            Self.loadTips()
        }
        _shuffledTips = State(initialValue: source.shuffled())
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Loading your tutor…")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Label("Tip", systemImage: "lightbulb.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)

                if !shuffledTips.isEmpty {
                    Text(shuffledTips[index % shuffledTips.count])
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(index)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity),
                        ))
                }
            }
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
        }
        .task {
            guard !shuffledTips.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.rotationInterval))
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    index = (index + 1) % shuffledTips.count
                }
            }
        }
    }

    private static func loadTips() -> [String] {
        guard
            let url = Bundle.main.url(forResource: "SpeakingTips", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let parsed = try? JSONDecoder().decode([String].self, from: data),
            !parsed.isEmpty
        else {
            return ["Loading your tutor…"]
        }
        return parsed
    }
}

#Preview {
    LoadingTipsView(tips: [
        "Native speakers say 'I gotta go' more than 'I have to leave'.",
        "'Kinda' and 'sorta' are everywhere in casual speech.",
    ])
    .frame(width: 360, height: 400)
}
