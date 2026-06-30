import SwiftUI

/// Standalone Knowledge Graph screen. The old version was a cramped inline Profile section: a flat list that dumped raw attribute key/values and showed no relationships at all. This follows the established mobile pattern (grouped entities + a "related" line per item, like Contacts grouped sections or a knowledge-panel, not a force-directed node graph): entities are sectioned by kind with an icon, and under each one the edges, the actual connections, finally surface. Read-only: the post-session pipeline builds it.
@MainActor
struct KnowledgeGraphView: View {
    @Environment(\.backendAPI) private var api
    @State private var model = KnowledgeGraphViewModel()

    var body: some View {
        List {
            if let error = model.error {
                Text("Couldn't load your knowledge graph: \(error)")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if model.isEmpty, model.error == nil {
                if model.loading {
                    // AuraDB scales to zero and can take a beat to wake; show a spinner during the first load so the screen doesn't flash the empty state (or, on a slow wake, a timeout) before data arrives.
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView(
                        "Knowledge Graph",
                        systemImage: "brain",
                        description: Text(
                            "No entities yet. As you talk, the AI starts recognizing the people, places, and projects.",
                        ),
                    )
                }
            } else {
                ForEach(model.groupedByType, id: \.type) { group in
                    Section {
                        ForEach(group.entities, id: \.id) { entity in
                            entityRow(entity)
                        }
                    } header: {
                        Label(Self.humanizeType(group.type), systemImage: Self.icon(for: group.type))
                    }
                }
            }
        }
        .navigationTitle("Knowledge Graph")
        .task {
            guard !model.didInitialLoad else { return }
            model.didInitialLoad = true
            await model.load(api: api)
        }
        .refreshable { await model.load(api: api) }
    }

    private func entityRow(_ entity: KGEntityDTO) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: entity.name).font(.headline)
            // Relationships are the point of a graph — surface them under each entity. Verbatim: names + relation verbs are the user's own data, not UI copy.
            ForEach(model.relationships(for: entity), id: \.self) { relationship in
                Label {
                    Text(verbatim: relationship)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Section-header label from the backend-defined entity type. Data-derived, pluralized for the common kinds.
    private static func humanizeType(_ type: String) -> String {
        switch type.lowercased() {
        case "person": "People"
        case "place": "Places"
        case "project": "Projects"
        case "interest": "Interests"
        case "event": "Events"
        case "organization", "company", "org": "Organizations"
        default: type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func icon(for type: String) -> String {
        switch type.lowercased() {
        case "person": "person.2.fill"
        case "place": "mappin.and.ellipse"
        case "project": "folder.fill"
        case "interest": "heart.fill"
        case "event": "calendar"
        case "organization", "company", "org": "building.2.fill"
        default: "circle.grid.2x2.fill"
        }
    }
}
