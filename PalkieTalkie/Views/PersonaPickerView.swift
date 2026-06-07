import SwiftUI

@MainActor
struct PersonaPickerView: View {
    @Environment(SessionController.self) private var session
    @Environment(\.backendAPI) private var api
    @Environment(\.dismiss) private var dismiss
    private static let cacheKey = "cache.personas"
    @State private var personas: [PersonaDTO] = JSONCache.load([PersonaDTO].self, key: PersonaPickerView.cacheKey) ?? []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var searchText: String = ""
    @State private var sort: SortOption = .recommended
    @State private var showCreate: Bool = false

    enum SortOption: String, CaseIterable, Identifiable {
        case recommended
        case popular
        case recent

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .recommended: "Recommended"
            case .popular: "Most liked"
            case .recent: "Recent"
            }
        }
    }

    var body: some View {
        List {
            ForEach(personas, id: \.id) { persona in
                row(persona)
            }
            if personas.isEmpty, !isLoading {
                ContentUnavailableView("No personas yet", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle("Personas")
        .searchable(text: $searchText, prompt: "Search personas")
        .onChange(of: searchText) { _, _ in Task { await refresh() } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Sort", selection: $sort) {
                    ForEach(SortOption.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .onChange(of: sort) { _, _ in Task { await refresh() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create new persona")
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await refresh() } }) {
            NavigationStack {
                PersonaCustomizeView(persona: nil)
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
        .overlay {
            if isLoading, personas.isEmpty { ProgressView() }
        }
        .alert("Couldn't load personas", isPresented: .constant(loadError != nil)) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    private func row(_ persona: PersonaDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            personaSummary(persona)
            Spacer()
            likeColumn(persona)
        }
        .padding(.vertical, 4)
    }

    private func personaSummary(_ persona: PersonaDTO) -> some View {
        Button {
            session.selectedPersonaId = persona.id
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                personaTitleRow(persona)
                if !persona.description.isEmpty {
                    Text(persona.description).font(.caption).foregroundStyle(.secondary)
                }
                Text("voice: \(persona.voiceId)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func personaTitleRow(_ persona: PersonaDTO) -> some View {
        HStack(spacing: 6) {
            Text(persona.name).font(.headline).foregroundStyle(.primary)
            badge(for: persona)
            if persona.id == session.selectedPersonaId {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func badge(for persona: PersonaDTO) -> some View {
        if persona.isPreset {
            chip(text: "Preset", color: .gray)
        } else if persona.isOwner {
            chip(text: "Mine", color: .blue)
        } else if persona.isPublic {
            chip(text: "Community", color: .purple)
        }
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
    }

    private func likeColumn(_ persona: PersonaDTO) -> some View {
        VStack(spacing: 2) {
            Button {
                Task { await toggleLike(persona) }
            } label: {
                Image(systemName: persona.likedByMe ? "heart.fill" : "heart")
                    .foregroundStyle(persona.likedByMe ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            Text("\(persona.likeCount)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await api.getPersonas(search: searchText, sort: sort.rawValue)
            personas = fresh
            // Only cache the default view (no search / recommended sort) — search results are query-specific and would clobber the general cache on next launch.
            if searchText.isEmpty, sort == .recommended {
                JSONCache.save(fresh, key: Self.cacheKey)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func toggleLike(_ persona: PersonaDTO) async {
        do {
            if persona.likedByMe {
                try await api.unlikePersona(id: persona.id)
            } else {
                try await api.likePersona(id: persona.id)
            }
            await refresh()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
