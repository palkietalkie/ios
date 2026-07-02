import ClerkKit
import SwiftUI

@MainActor
struct ProfileView: View {
    @Environment(\.backendAPI) private var api
    @State private var model = ProfileViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    LabeledContent("Email") {
                        Text(model.email.isEmpty
                            ? (Clerk.shared.user?.primaryEmailAddress?.emailAddress ?? "—")
                            : model.email)
                    }
                    LabeledContent("Preferred name") {
                        TextField("e.g. Wes", text: $model.preferredName)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Pronunciation") {
                        TextField("e.g. WESS", text: $model.namePronunciation)
                            .multilineTextAlignment(.trailing)
                    }
                    // Distinct sub-row so the user can clearly tell this is a SUGGESTION (not the stored value) and tap to accept. Ghost-text placeholder reads identically to a real value to most users.
                    if model.namePronunciation.isEmpty, !model.pronunciationSuggestion.isEmpty {
                        Button {
                            model.namePronunciation = model.pronunciationSuggestion
                        } label: {
                            HStack {
                                Text("Suggested:").foregroundStyle(.secondary)
                                Text(model.pronunciationSuggestion).bold()
                                Spacer()
                                Text("Tap to use").font(.caption).foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink {
                        MultiLanguagePicker(
                            languages: model.languages,
                            selection: $model.nativeLanguages,
                            title: "Native languages",
                        )
                    } label: {
                        LabeledContent("Native languages") {
                            Text(model.nativeLanguages.isEmpty
                                ? String(localized: "Choose…")
                                : model.nativeLanguages.sorted().map(localizedLanguageName).joined(separator: ", "))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                guard !model.didInitialLoad else { return }
                model.didInitialLoad = true
                await model.load(api: api)
            }
            .refreshable { await model.load(api: api) }
            // Auto-save: any edit to an editable field changes the snapshot; the model debounces + guards so only real edits persist.
            .onChange(of: model.formSnapshot) { _, _ in
                model.scheduleAutoSave(api: api)
            }
        }
    }
}
