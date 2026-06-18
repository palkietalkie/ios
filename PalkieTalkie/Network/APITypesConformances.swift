import Foundation

// iOS domain names for the generated wire types. The generated struct (Generated/APITypes.swift) is the single source of truth for FIELDS and types; these aliases only give the app's call sites their established domain names so the backend's serialization-suffixed names (…Out / …Response) don't spread through the UI. One mapping point, and regenerated field changes flow through automatically.
typealias PersonaDTO = PersonaOut
typealias PersonaCreatePayload = PersonaCreate
typealias PersonaUpdatePayload = PersonaUpdate
typealias VoiceDTO = VoiceOut
typealias LanguageDTO = LanguageOut
typealias PracticeOptionsDTO = PracticeOptionsOut
typealias ConsentDTO = ConsentOut
typealias ConsentUpdatePayload = ConsentUpdate
typealias Stats = StatsOverview
typealias Mistake = MistakeOut
typealias PhraseUsage = PhraseOut
typealias CEFRWord = CefrWordOut
typealias CEFRCoverage = CefrCoverage
typealias Entitlement = EntitlementResponse
typealias ProfileDTO = ProfileOut
typealias IntegrationStatus = ProviderStatus
typealias OAuthConnectURL = ConnectURL

// SwiftUI list / picker ergonomics the generator can't emit (it produces pure Codable structs). Declaring them in an extension keeps the generated file regenerable without losing these conformances. Types that already carry an `id` field get Identifiable for free; the rest map it to their natural key.
extension MistakeOut: Identifiable {}
extension PhraseOut: Identifiable {}
extension CefrWordOut: Identifiable {}
extension VoiceOut: Identifiable {}
extension SessionSummary: Identifiable { var id: String {
    sessionId
} }
extension CefrCoverage: Identifiable { var id: String {
    level
} }
extension ProviderStatus: Identifiable { var id: String {
    provider
} }
extension LanguageOut: Identifiable, Hashable {
    var id: String {
        name
    }

    static func == (lhs: LanguageOut, rhs: LanguageOut) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
