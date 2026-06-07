import SwiftUI

@MainActor
struct MainTabView: View {
    /// Selected tab. Bound so child views (e.g. TalkAboutTodayView) can request a switch on user action. Persisted to UserDefaults under "main_tab_selection" so a relaunch returns you to wherever you were instead of always Talk.
    @AppStorage("main_tab_selection") private var selectedTab: AppTab = .talk

    enum AppTab: String, Hashable { case talk, today, stats, persona, more }

    var body: some View {
        TabView(selection: $selectedTab) {
            ConversationView()
                .tag(AppTab.talk)
                .tabItem { Label("Talk", systemImage: "mic.fill") }
            TalkAboutTodayView(onTopicSelected: { selectedTab = .talk })
                .tag(AppTab.today)
                .tabItem { Label("Today", systemImage: "newspaper") }
            StatsView()
                .tag(AppTab.stats)
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            NavigationStack { PersonaPickerView() }
                .tag(AppTab.persona)
                .tabItem { Label("Persona", systemImage: "person.crop.circle") }
            MorePanelView()
                .tag(AppTab.more)
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
    }
}
