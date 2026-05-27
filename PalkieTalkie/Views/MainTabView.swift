import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ConversationView()
                .tabItem { Label("Talk", systemImage: "mic.fill") }
            TalkAboutTodayView()
                .tabItem { Label("Today", systemImage: "newspaper") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            PersonaPickerView()
                .tabItem { Label("Persona", systemImage: "person.crop.circle") }
            MorePanelView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
    }
}
