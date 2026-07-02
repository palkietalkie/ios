@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

/// Rendering tests for the standalone Knowledge Graph screen. The body has four mutually exclusive branches (error / loading / empty / populated); each is exercised by injecting a model in that state so a refactor that breaks any branch surfaces here. The model is injectable purely so these states can be rendered without a live backend.
@MainActor
final class KnowledgeGraphViewTests: XCTestCase {
    private func model(
        entities: [KGEntityDTO] = [],
        edges: [KGEdgeDTO] = [],
        error: String? = nil,
        loading: Bool = false,
    ) -> KnowledgeGraphViewModel {
        let vm = KnowledgeGraphViewModel()
        vm.entities = entities
        vm.edges = edges
        vm.error = error
        vm.loading = loading
        return vm
    }

    func testPopulatedBranchRendersNamesGroupsAndRelationships() throws {
        let naoto = KGEntityDTO(id: "e1", type: "person", name: "Naoto", attrs: [:])
        let kawasaki = KGEntityDTO(id: "e2", type: "organization", name: "Kawasaki", attrs: [:])
        let osaka = KGEntityDTO(id: "e3", type: "place", name: "Osaka", attrs: [:])
        let sut = KnowledgeGraphView(model: model(
            entities: [naoto, kawasaki, osaka],
            edges: [KGEdgeDTO(src: "e1", rel: "works_at", dst: "e2")],
        ))
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("Naoto"))
        XCTAssertTrue(texts.contains("Osaka"))
        XCTAssertTrue(texts.contains("People"), "humanizeType pluralizes the section header")
        XCTAssertTrue(texts.contains("Organizations"))
        XCTAssertTrue(texts.contains("works at Kawasaki"), "the edge surfaces as a relationship line")
    }

    /// Unknown entity kinds hit humanizeType/icon's default branches (de-underscore + capitalize, generic icon).
    func testUnknownTypeUsesDefaultHeaderFormatting() throws {
        let sut = KnowledgeGraphView(model: model(
            entities: [KGEntityDTO(id: "x1", type: "life_event", name: "Moved to SF", attrs: [:])],
        ))
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("Life Event"), "default branch de-underscores and capitalizes the raw type")
    }

    func testEmptyBranchShowsContentUnavailable() throws {
        let sut = KnowledgeGraphView(model: model())
        XCTAssertNoThrow(try sut.inspect().find(ViewType.ContentUnavailableView.self))
    }

    func testLoadingBranchShowsSpinner() throws {
        let sut = KnowledgeGraphView(model: model(loading: true))
        XCTAssertNoThrow(try sut.inspect().find(ViewType.ProgressView.self))
    }

    func testErrorBranchShowsMessage() throws {
        let sut = KnowledgeGraphView(model: model(error: "The request timed out."))
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains { $0.contains("The request timed out.") })
    }

    func testRenderedCopyHasNoEmOrEnDash() throws {
        let sut = KnowledgeGraphView(model: model(entities: [KGEntityDTO(
            id: "e1",
            type: "person",
            name: "Naoto",
            attrs: [:],
        )]))
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        for text in texts {
            XCTAssertFalse(text.contains("—"), "em dash leaked into copy: \(text)")
            XCTAssertFalse(text.contains("–"), "en dash leaked into copy: \(text)")
        }
    }
}
