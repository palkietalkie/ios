import Charts
import SwiftUI

struct StatsView: View {
    private static let cacheKey = "cache.stats"

    @Environment(\.backendAPI) private var api
    @State private var stats: Stats? = JSONCache.load(Stats.self, key: StatsView.cacheKey)
    @State private var loadError: String?
    @State private var explainerMetric: MetricInfo?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Render the full layout immediately. When `stats` is nil (first visit, no cache yet, or refresh in progress), each panel falls back to placeholders (em-dash / zero) so the user sees structure, not a spinner. Real numbers replace placeholders as soon as the network returns.
                    buildHero(stats)
                    metricGrid(stats)
                    buildCefrCard(stats?.cefrCoverage ?? [])
                    detailLinks
                    if let loadError {
                        Text(loadError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .padding(16)
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

    private func buildHero(_ stats: Stats?) -> some View {
        let streak = stats?.dayStreak
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: streak.map(String.init) ?? "-")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Image(systemName: "flame.fill").foregroundStyle(.orange).font(.title)
            }
            Text((streak ?? 0) == 1 ? "day in a row" : "days in a row")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))
    }

    // MARK: - Metric cards (2-column grid)

    private func metricGrid(_ stats: Stats?) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard(.minutes, value: stats.map { "\($0.sessionTotalSeconds / 60)" } ?? "-", unit: "minutes")
            metricCard(
                .sessions,
                value: stats.map { "\($0.sessionsCount)" } ?? "-",
                unit: (stats?.sessionsCount ?? 0) == 1 ? "session" : "sessions",
            )
            metricCard(.uniqueWords, value: stats.map { "\($0.uniqueWords)" } ?? "-", unit: "words")
            metricCard(.uniquePhrases, value: stats.map { "\($0.uniquePhrases)" } ?? "-", unit: "phrases")
            metricCard(.talkShare, value: formatPct(stats?.userTalkPct), unit: "vs AI")
            metricCard(.speakingRate, value: formatWpm(stats?.speakingRateWpm), unit: "wpm")
            metricCard(.pitchRange, value: formatPitchRange(stats?.pitchMinHz, stats?.pitchMaxHz), unit: "Hz")
            metricCard(.affinity, value: stats.map { "\($0.affinity ?? 0)" } ?? "-", unit: "moments")
            Color.clear.frame(height: 0)
        }
    }

    private func metricCard(_ metric: MetricInfo, value: String, unit: String) -> some View {
        Button { explainerMetric = metric } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(metric.title)).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "info.circle").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(LocalizedStringKey(unit)).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
        }
        .buttonStyle(.plain)
    }

    // MARK: - CEFR chart card

    private func buildCefrCard(_ data: [CEFRCoverage]) -> some View {
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
                        if let v = value.as(Int.self) { Text(verbatim: "\(v)%") }
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
                buildDetailLinkRow("Frequent mistakes", systemImage: "exclamationmark.bubble")
            }
            NavigationLink(destination: PhrasesView()) {
                buildDetailLinkRow("Frequent phrases", systemImage: "quote.bubble")
            }
            NavigationLink(destination: CEFRDetailView()) {
                buildDetailLinkRow("CEFR detail", systemImage: "list.bullet.rectangle")
            }
        }
    }

    private func buildDetailLinkRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 24)
            Text(LocalizedStringKey(title))
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
        .foregroundStyle(.primary)
    }

    // MARK: - Formatting

    private func formatPct(_ v: Double?) -> String {
        v.map { String(format: "%.0f%%", $0 * 100) } ?? "-"
    }

    private func formatWpm(_ v: Double?) -> String {
        v.map { String(format: "%.0f", $0) } ?? "-"
    }

    private func formatPitchRange(_ lo: Double?, _ hi: Double?) -> String {
        guard let lo, let hi else { return "-" }
        return "\(Int(lo.rounded()))-\(Int(hi.rounded()))"
    }

    // MARK: - Load

    private func load() async {
        do {
            let fresh = try await api.getStats()
            stats = fresh
            JSONCache.save(fresh, key: Self.cacheKey)
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

    static let minutes = MetricInfo(
        id: "minutes",
        title: "Total time",
        explanation: "Total time you've spent in conversation across all sessions.",
        computation: "We add up the length of every conversation you finished.",
    )
    static let sessions = MetricInfo(
        id: "sessions",
        title: "Conversations",
        explanation: "How many separate conversations you've had.",
        computation: "Counted from every conversation saved to your account.",
    )
    static let uniqueWords = MetricInfo(
        id: "uniqueWords",
        title: "Vocabulary",
        explanation: "How many different words you've actually said. Repeating \"hello\" 50 times still counts as 1.",
        computation: "Counted from what you've said. Different forms of the same word (\"running\", \"run\") count once.",
    )
    static let uniquePhrases = MetricInfo(
        id: "uniquePhrases",
        title: "Expressions",
        explanation: "Multi-word native expressions you've used (e.g., \"give it a shot\", \"figure out\").",
        computation: "We pick these out from your conversations after each one ends.",
    )
    static let talkShare = MetricInfo(
        id: "talkShare",
        title: "Talk share",
        explanation: "Of the words said in your conversations, how many were yours vs the AI's. ~50% means a balanced two-way conversation; under 30% means you're letting the AI dominate.",
        computation: "Based on how much you said compared with the AI.",
    )
    static let speakingRate = MetricInfo(
        id: "speakingRate",
        title: "Speaking rate",
        explanation: "Words per minute when you're talking. Native English averages 120-150 wpm; comfortable conversational fluency is 100+. Below ~70 wpm typically means hesitation.",
        computation: "Your total words divided by the time you spent speaking.",
    )
    static let pitchRange = MetricInfo(
        id: "pitchRange",
        title: "Pitch range",
        explanation: "How much your voice goes up and down. Wider range = more expressive, animated speech. Flat pitch is a hallmark of robotic / hesitant speech.",
        computation: "Measured from your voice on your device. We track your lowest and highest pitch in each conversation.",
    )
    static let affinity = MetricInfo(
        id: "affinity",
        title: "Affinity",
        explanation: "How much you win your tutor over: the laughs and warmth you pull out of them. It rises when YOU make the conversation come alive. Charming a native speaker into a lively exchange is real skill.",
        computation: "We listen for the real reactions in your tutor's voice as you talk, the genuine laughs and warmth, and turn them into this score. The more you pull out, the higher it climbs.",
    )
    static let cefr = MetricInfo(
        id: "cefr",
        title: "CEFR vocab coverage",
        explanation: "What percent of the standard CEFR vocabulary (A1 → C2) you've actually used in conversation. A1 = absolute beginner, C2 = native-level mastery. Aim to push each level past 80%.",
        computation: "We match the words you've spoken against a standard vocabulary list for each level.",
    )
}

struct MetricExplainerSheet: View {
    let info: MetricInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(info.title)).font(.title2.bold())
            Text(LocalizedStringKey(info.explanation)).font(.body)
            if let computation = info.computation {
                Divider()
                Text("How it's measured").font(.subheadline).foregroundStyle(.secondary)
                Text(LocalizedStringKey(computation)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
    }
}
