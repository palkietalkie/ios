import SwiftUI

@MainActor
struct NotificationSettingsView: View {
    @Environment(\.backendAPI) private var api
    @State private var remindersEnabled = false
    @State private var reminderHour = 19
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Daily reminders", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, _ in Task { await save() } }
                if remindersEnabled {
                    Picker("Reminder time", selection: $reminderHour) {
                        ForEach(0 ..< 24, id: \.self) { hour in
                            Text(verbatim: hourLabel(hour)).tag(hour)
                        }
                    }
                    .onChange(of: reminderHour) { _, _ in Task { await save() } }
                }
            } footer: {
                Text("A gentle nudge if you haven't talked today.")
            }
        }
        .navigationTitle("Notifications")
        .task { await load() }
        .alert("Couldn't save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    /// Localized clock label for an hour-of-day (e.g. "7:00 PM"). A pure value, so verbatim, not a catalog string.
    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func load() async {
        do {
            let prefs = try await api.getNotificationPrefs()
            remindersEnabled = prefs.remindersEnabled
            reminderHour = prefs.reminderHourLocal
            loaded = true
        } catch let err {
            error = err.localizedDescription
        }
    }

    private func save() async {
        guard loaded, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await api.setNotificationPrefs(
                NotificationPrefsUpdate(
                    remindersEnabled: remindersEnabled, reminderHourLocal: reminderHour,
                ),
            )
        } catch let err {
            error = err.localizedDescription
        }
    }
}
