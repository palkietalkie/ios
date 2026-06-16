import EventKit
import SwiftUI

struct IntegrationsView: View {
    @Environment(\.backendAPI) private var api
    @State private var model: IntegrationsViewModel

    init(oauth: (any OAuthStarting)? = nil) {
        if let oauth {
            _model = State(initialValue: IntegrationsViewModel(oauth: oauth))
        } else {
            _model = State(initialValue: IntegrationsViewModel())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Calendar") {
                    Toggle(isOn: $model.appleCalendarGranted) {
                        Label("Apple Calendar", systemImage: "calendar")
                    }
                    .onChange(of: model.appleCalendarGranted) { _, newValue in
                        if newValue { Task { await model.requestCalendar() } }
                    }
                    Toggle(isOn: $model.googleConnected) {
                        Label("Google Calendar", systemImage: "g.circle.fill")
                    }
                    .onChange(of: model.googleConnected) { _, newValue in
                        if newValue { Task { await model.connectGoogle(api: api) } }
                    }
                    Toggle(isOn: $model.outlookConnected) {
                        Label("Outlook", systemImage: "envelope.circle.fill")
                    }
                    .onChange(of: model.outlookConnected) { _, newValue in
                        if newValue { Task { await model.connectOutlook(api: api) } }
                    }
                }
                if let statusMessage = model.statusMessage {
                    Section { Text(statusMessage).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Reminders") {
                    NavigationLink {
                        Text("Schedule recurring practice sessions, coming soon")
                    } label: {
                        Label("Practice schedule", systemImage: "alarm")
                    }
                }
            }
            .navigationTitle("Integrations")
            .task { await model.refreshIntegrations(api: api) }
            .overlay {
                if model.isLoading { ProgressView().padding().background(.regularMaterial).cornerRadius(8) }
            }
        }
    }
}
