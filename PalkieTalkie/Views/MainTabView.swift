import SwiftUI

@MainActor
struct MainTabView: View {
    /// Selected tab. Bound so child views (e.g. TalkAboutTodayView) can request a switch on user action. Persisted to UserDefaults under "main_tab_selection" so a relaunch returns you to wherever you were instead of always Talk.
    @AppStorage("main_tab_selection") private var selectedTab: AppTab = .talk
    @Environment(SessionController.self) private var session
    /// The tab the user was on before they last entered Talk. When the model hangs up by voice, we return here instead of leaving them on the idle mic. Defaults to Topics for a cold open straight into Talk.
    @State private var tabBeforeTalk: AppTab = .today

    enum AppTab: String, Hashable { case talk, today, stats, persona, more }

    var body: some View {
        // Order puts Talk in the center (the primary action), flanked by Topics + Persona on the left and Stats + More on the right.
        TabView(selection: $selectedTab) {
            TalkAboutTodayView(onTopicSelected: { selectedTab = .talk })
                .tag(AppTab.today)
                .tabItem { Label("Topics", systemImage: "lightbulb") }
            NavigationStack { PersonaPickerView() }
                .tag(AppTab.persona)
                .tabItem { Label("Persona", systemImage: "person.crop.circle") }
            ConversationView()
                .tag(AppTab.talk)
                .tabItem { Label("Talk", systemImage: "mic.fill") }
            StatsView()
                .tag(AppTab.stats)
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            MorePanelView()
                .tag(AppTab.more)
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .talk, oldValue != .talk { tabBeforeTalk = oldValue }
        }
        .onChange(of: session.endRequestedByTool) { _, ended in
            guard ended else { return }
            session.endRequestedByTool = false
            // Leaving Talk makes ConversationView disappear, which ends the session.
            selectedTab = tabBeforeTalk
        }
    }
}
