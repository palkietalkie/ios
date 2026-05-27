import Charts
import SwiftUI

struct StatsView: View {
    @State private var stats: Stats?
    @State private var loadError: String?
    @State private var explainerMetric: MetricInfo?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let stats {
                    VStack(spacing: 16) {
                        hero(stats)
                        metricGrid(stats)
                        cefrCard(stats.cefrCoverage)
                        detailLinks
                    }
                    .padding(16)
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red).textSelection(.enabled).padding()
                } else {
                    ProgressView().padding()
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Stats").font(.headline)
                        Text("All time").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $explainerMetric) { info in
                MetricExplainerSheet(info: info)
                    .presentationDetents([.fraction(0.4), .medium])
            }
        }
    }

    // MARK: - Hero (top headline)

    private func hero(_ stats: Stats) -> some View {
        let minutes = stats.sessionTotalSeconds / 60
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(minutes)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                Text("minutes of conversation").foregroundStyle(.secondary)
                Spacer()
                Text("\(stats.sessionsCount) session\(stats.sessionsCount == 1 ? "" : "s")")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))
    }

    // MARK: - Metric cards (2-column grid)

    private func metricGrid(_ stats: Stats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard(.uniqueWords, value: "\(stats.uniqueWords)", unit: "words")
            metricCard(.uniquePhrases, value: "\(stats.uniquePhrases)", unit: "phrases")
            metricCard(.talkShare, value: formatPct(stats.userTalkPct), unit: "your share")
            metricCard(.speakingRate, value: formatWpm(stats.speakingRateWpm), unit: "wpm")
            metricCard(.pitchRange, value: formatHz(stats.pitchRangeHz), unit: "Hz range")
            // Filler card to balance grid when odd metric count — invisible, preserves layout.
            Color.clear.frame(height: 0)
        }
    }

    private func metricCard(_ metric: MetricInfo, value: String, unit: String) -> some View {
        Button { explainerMetric = metric } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(metric.title).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "info.circle").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
        }
        .buttonStyle(.plain)
    }

    // MARK: - CEFR chart card

    private func cefrCard(_ data: [CEFRCoverage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("CEFR vocab coverage").font(.headline)
                Button { explainerMetric = .cefr } label: {
                    Image(systemName: "info.circle").font(.caption).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Chart(data) { item in
                BarMark(x: .value("Level", item.level), y: .value("Coverage %", item.coveragePct))
                    .foregroundStyle(by: .value("Level", item.level))
            }
            .chartLegend(.hidden)
            .chartYScale(domain: 0 ... 100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text("\(v)%") }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
    }

    // MARK: - Detail links

    private var detailLinks: some View {
        VStack(spacing: 8) {
            NavigationLink(destination: MistakesView()) {
                detailLinkRow("Frequent mistakes", systemImage: "exclamationmark.bubble")
            }
            NavigationLink(destination: PhrasesView()) {
                detailLinkRow("Frequent phrases", systemImage: "quote.bubble")
            }
            NavigationLink(destination: CEFRDetailView()) {
                detailLinkRow("CEFR detail", systemImage: "list.bullet.rectangle")
            }
        }
    }

    private func detailLinkRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 24)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
        .foregroundStyle(.primary)
    }

    // MARK: - Formatting

    private func formatPct(_ v: Double?) -> String {
        v.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
    }

    private func formatWpm(_ v: Double?) -> String {
        v.map { String(format: "%.0f", $0) } ?? "—"
    }

    private func formatHz(_ v: Double?) -> String {
        v.map { String(format: "%.0f", $0) } ?? "—"
    }

    // MARK: - Load

    private func load() async {
        do {
            stats = try await BackendAPI.shared.getStats()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Metric metadata

struct MetricInfo: Identifiable {
    let id: String
    let title: String
    let explanation: String
    let computation: String?

    static let uniqueWords = MetricInfo(
        id: "uniqueWords",
        title: "Unique words",
        explanation: "How many different words you've actually said. Repeating \"hello\" 50 times still counts as 1.",
        computation: "Counted from your spoken transcripts, lemmatized (\"running\" and \"run\" collapse to one word)."
    )
    static let uniquePhrases = MetricInfo(
        id: "uniquePhrases",
        title: "Unique phrases",
        explanation: "Multi-word native expressions you've used (e.g., \"give it a shot\", \"figure out\").",
        computation: "Extracted from transcripts after each session by an NLP pipeline."
    )
    static let talkShare = MetricInfo(
        id: "talkShare",
        title: "Your share of talk",
        explanation: "Of the words said in your conversations, how many were yours vs the AI's. ~50% means a balanced two-way conversation; under 30% means you're letting the AI dominate.",
        computation: "Character ratio between your transcripts and the AI's. Real audio-time ratio is coming once on-device speech timing ships."
    )
    static let speakingRate = MetricInfo(
        id: "speakingRate",
        title: "Speaking rate",
        explanation: "Words per minute when you're talking. Native English averages 120-150 wpm; comfortable conversational fluency is 100+. Below ~70 wpm typically means hesitation.",
        computation: "Your word count divided by inferred time you spent speaking (session duration × your talk-share)."
    )
    static let pitchRange = MetricInfo(
        id: "pitchRange",
        title: "Pitch range",
        explanation: "How much your voice goes up and down. Wider range = more expressive, animated speech. Flat pitch is a hallmark of robotic / hesitant speech.",
        computation: "Needs on-device audio analysis (FFT pitch detection). Shipping in the next update."
    )
    static let cefr = MetricInfo(
        id: "cefr",
        title: "CEFR vocab coverage",
        explanation: "What percent of the standard CEFR vocabulary (A1 → C2) you've actually used in conversation. A1 = absolute beginner, C2 = native-level mastery. Aim to push each level past 80%.",
        computation: "Cross-references your spoken words against the CEFR-J Wordlist v1.6 reference."
    )
}

struct MetricExplainerSheet: View {
    let info: MetricInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(info.title).font(.title2.bold())
            Text(info.explanation).font(.body)
            if let computation = info.computation {
                Divider()
                Text("How it's measured").font(.subheadline).foregroundStyle(.secondary)
                Text(computation).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
    }
}
