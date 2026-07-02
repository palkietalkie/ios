@testable import PalkieTalkie
import XCTest

/// Unit tests for KnowledgeGraphViewModel (the KG load + the grouping/relationship logic that drives the redesigned screen).
@MainActor
final class KnowledgeGraphViewModelTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: KnowledgeGraphViewModel.cacheKey)
    }

    override func tearDown() async throws {
        try? await Task.sleep(nanoseconds: 300_000_000)
        UserDefaults.standard.removeObject(forKey: KnowledgeGraphViewModel.cacheKey)
        try await super.tearDown()
    }

    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: StubAuthing())
    }

    func testLoadPopulatesNodesAndEdges() async throws {
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/kg",
            data: BackendAPI.encoder.encode(KGGraphDTO(
                nodes: [KGEntityDTO(id: "e1", type: "person", name: "Naoto", attrs: [:])],
                edges: [KGEdgeDTO(src: "e1", rel: "works_at", dst: "e2")],
            )),
        )
        let vm = KnowledgeGraphViewModel()
        await vm.load(api: makeAPI(transport))
        XCTAssertEqual(vm.entities.count, 1)
        XCTAssertEqual(vm.edges.count, 1)
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.isEmpty)
    }

    /// Regression: getKG() used to be `try?`, so a contract mismatch (backend `{nodes,edges}` vs an iOS bare-array decode) silently swallowed the error and showed every user an empty KG. A decode failure must surface in `error`. The bare `[]` is exactly the pre-fix shape that no longer matches KGGraphDTO.
    func testDecodeFailureSurfacesError() async {
        let transport = FakeTransport()
        transport.enqueue(path: "/kg", data: Data("[]".utf8))
        let vm = KnowledgeGraphViewModel()
        await vm.load(api: makeAPI(transport))
        XCTAssertNotNil(vm.error, "a KG decode failure must surface, not silently show an empty graph")
    }

    func testIsEmptyWithNoNodes() async throws {
        let transport = FakeTransport()
        try transport.enqueue(path: "/kg", data: BackendAPI.encoder.encode(KGGraphDTO(nodes: [], edges: [])))
        let vm = KnowledgeGraphViewModel()
        await vm.load(api: makeAPI(transport))
        XCTAssertTrue(vm.isEmpty)
    }

    func testInitSeedsFromCache() throws {
        try JSONCache.save(
            KGGraphDTO(nodes: [KGEntityDTO(id: "p1", type: "place", name: "Osaka", attrs: [:])], edges: []),
            key: KnowledgeGraphViewModel.cacheKey,
        )
        let vm = KnowledgeGraphViewModel()
        XCTAssertEqual(vm.entities.first?.name, "Osaka")
    }

    func testGroupedByTypeSortsGroupsAndEntities() {
        let vm = KnowledgeGraphViewModel()
        vm.entities = [
            KGEntityDTO(id: "p2", type: "person", name: "Naoto", attrs: [:]),
            KGEntityDTO(id: "pl1", type: "place", name: "Osaka", attrs: [:]),
            KGEntityDTO(id: "p1", type: "person", name: "Ayumi", attrs: [:]),
        ]
        let grouped = vm.groupedByType
        XCTAssertEqual(grouped.map(\.type), ["person", "place"])
        XCTAssertEqual(grouped.first?.entities.map(\.name), ["Ayumi", "Naoto"])
    }

    func testRelationshipsResolveTargetNamesAndDeUnderscore() {
        let vm = KnowledgeGraphViewModel()
        let naoto = KGEntityDTO(id: "e1", type: "person", name: "Naoto", attrs: [:])
        vm.entities = [naoto, KGEntityDTO(id: "e2", type: "organization", name: "Kawasaki", attrs: [:])]
        vm.edges = [KGEdgeDTO(src: "e1", rel: "works_at", dst: "e2")]
        XCTAssertEqual(vm.relationships(for: naoto), ["works at Kawasaki"])
    }

    func testRelationshipsFallBackToTargetIdWhenUnknown() {
        let vm = KnowledgeGraphViewModel()
        let naoto = KGEntityDTO(id: "e1", type: "person", name: "Naoto", attrs: [:])
        vm.entities = [naoto]
        vm.edges = [KGEdgeDTO(src: "e1", rel: "knows", dst: "missing")]
        XCTAssertEqual(vm.relationships(for: naoto), ["knows missing"])
    }

    func testRemoveEntityDropsItAndItsEdges() async {
        let vm = KnowledgeGraphViewModel()
        let naoto = KGEntityDTO(id: "e1", type: "person", name: "Naoto", attrs: [:])
        vm.entities = [naoto, KGEntityDTO(id: "e2", type: "place", name: "Osaka", attrs: [:])]
        vm.edges = [KGEdgeDTO(src: "e1", rel: "lives_in", dst: "e2")]
        await vm.removeEntity(naoto, api: makeAPI(FakeTransport()))
        XCTAssertEqual(vm.entities.map(\.id), ["e2"])
        XCTAssertTrue(vm.edges.isEmpty, "edges touching the removed item must drop too")
        XCTAssertNil(vm.error)
    }

    func testRemoveEntityRestoresGraphOnFailure() async {
        let vm = KnowledgeGraphViewModel()
        let naoto = KGEntityDTO(id: "e1", type: "person", name: "Naoto", attrs: [:])
        vm.entities = [naoto]
        vm.edges = [KGEdgeDTO(src: "e1", rel: "knows", dst: "e2")]
        let transport = FakeTransport()
        transport.responseStatus = 500
        await vm.removeEntity(naoto, api: makeAPI(transport))
        XCTAssertEqual(vm.entities.map(\.id), ["e1"], "a failed delete must restore the item")
        XCTAssertEqual(vm.edges.count, 1)
        XCTAssertNotNil(vm.error)
    }
}
