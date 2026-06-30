import Foundation

/// Backing model for the standalone Knowledge Graph screen. The post-session pipeline builds the graph; the user can't edit it beyond soft-deleting a wrong item (swipe-to-remove).
///
/// Holds the full `{nodes, edges}` graph. The old inline Profile list dropped the edges, so relationships, the whole point of a graph, never surfaced. `groupedByType` and `relationships(for:)` are pure (no I/O) so the screen's structure is unit-tested.
@MainActor
@Observable
final class KnowledgeGraphViewModel {
    static let cacheKey = "cache.knowledge_graph"

    var entities: [KGEntityDTO] = []
    var edges: [KGEdgeDTO] = []
    var error: String?
    var loading = false
    var didInitialLoad = false

    init() {
        if let cached = JSONCache.load(KGGraphDTO.self, key: Self.cacheKey) {
            entities = cached.nodes
            edges = cached.edges
        }
    }

    var isEmpty: Bool {
        entities.isEmpty
    }

    func load(api: BackendAPI) async {
        loading = true
        error = nil
        defer { loading = false }
        // Surface load/decode failures instead of swallowing — a silently-failed decode (the nodes/edges contract drift) is exactly how a populated KG showed up empty for real users.
        do {
            let fresh = try await api.getKG()
            entities = fresh.nodes
            edges = fresh.edges
            JSONCache.save(fresh, key: Self.cacheKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Entities grouped by kind (person/place/project/…), each group's entities sorted by name, groups in a stable kind order. Drives the sectioned layout.
    var groupedByType: [(type: String, entities: [KGEntityDTO])] {
        Dictionary(grouping: entities, by: { $0.type })
            .map { (type: $0.key, entities: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.type < $1.type }
    }

    /// Outgoing relationships for an entity as `verb target` lines, resolving edge target ids back to entity names and de-underscoring the relation (e.g. `works_at` → `works at Kawasaki`). The relationships the old flat list never showed.
    func relationships(for entity: KGEntityDTO) -> [String] {
        let nameById = Dictionary(entities.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return edges
            .filter { $0.src == entity.id }
            .map { "\($0.rel.replacingOccurrences(of: "_", with: " ")) \(nameById[$0.dst] ?? $0.dst)" }
            .sorted()
    }

    /// Soft-delete a wrong item. Optimistic: drop it AND every edge touching it immediately so the swipe feels instant (mirrors the server, which hides edges to a removed node); on failure, restore the previous graph and surface the error.
    func removeEntity(_ entity: KGEntityDTO, api: BackendAPI) async {
        let previousEntities = entities
        let previousEdges = edges
        entities.removeAll { $0.id == entity.id }
        edges.removeAll { $0.src == entity.id || $0.dst == entity.id }
        do {
            try await api.removeKGEntity(id: entity.id)
            JSONCache.save(KGGraphDTO(nodes: entities, edges: edges), key: Self.cacheKey)
        } catch {
            entities = previousEntities
            edges = previousEdges
            self.error = error.localizedDescription
        }
    }
}
