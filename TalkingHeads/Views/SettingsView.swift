import SwiftUI

// TERMINOLOGY:
// - `Picker` = dropdown/select component (like <select> in HTML).
// - `Section` = groups form items with a header (like a fieldset in HTML).
// - `Form` = a scrollable settings-style list (like iOS Settings app).
// - `.tag()` = associates a value with a Picker option (like <option value="">).

/// Persona and scenario selection screen.
struct SettingsView: View {
    @EnvironmentObject var orchestrator: VoiceOrchestrator

    // `@State` = local component state (like useState in React)
    @State private var personas = PromptBuilder.loadPersonas()
    @State private var scenarios = PromptBuilder.loadScenarios()

    var body: some View {
        Form {
            Section("Character") {
                // Picker bound to orchestrator.selectedPersona
                // `$orchestrator.selectedPersona` = two-way binding (like v-model in Vue)
                Picker("Persona", selection: $orchestrator.selectedPersona) {
                    Text("Default Tutor").tag(nil as Persona?)
                    ForEach(personas) { persona in
                        VStack(alignment: .leading) {
                            Text(persona.name)
                            Text(persona.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(persona as Persona?)
                    }
                }
                // `.pickerStyle(.inline)` = show all options inline instead of a dropdown
                .pickerStyle(.inline)
            }

            Section("Scenario") {
                Picker("Scenario", selection: $orchestrator.selectedScenario) {
                    Text("No specific scenario").tag(nil as Scenario?)
                    ForEach(scenarios) { scenario in
                        VStack(alignment: .leading) {
                            Text(scenario.name)
                            Text(scenario.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(scenario as Scenario?)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Settings")
    }
}
