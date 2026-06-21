import Foundation

/// Persona library: list (preset + community + own), create/edit/delete own, like/unlike/report.
extension BackendAPI {
    func getPersonas(search: String? = nil, sort: String = "recommended") async throws -> [PersonaDTO] {
        // Preset name/description are localized server-side (backend owns that content), so tell the backend which UI language we're rendering in.
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        var query = "sort=\(sort)&lang=\(lang)"
        if let search, !search.isEmpty {
            let encoded = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search
            query += "&q=\(encoded)"
        }
        return try await get("/personas?\(query)")
    }

    func createPersona(_ payload: PersonaCreatePayload) async throws -> PersonaDTO {
        try await post("/personas", body: payload)
    }

    func updatePersona(id: String, _ payload: PersonaUpdatePayload) async throws -> PersonaDTO {
        try await patch("/personas/\(id)", body: payload)
    }

    func deletePersona(id: String) async throws {
        let _: EmptyResponse = try await delete("/personas/\(id)")
    }

    func likePersona(id: String) async throws {
        struct Empty: Codable {}
        let _: EmptyResponse = try await post("/personas/\(id)/like", body: Empty())
    }

    func unlikePersona(id: String) async throws {
        let _: EmptyResponse = try await delete("/personas/\(id)/like")
    }

    func reportPersona(id: String) async throws {
        struct Empty: Codable {}
        let _: EmptyResponse = try await post("/personas/\(id)/report", body: Empty())
    }
}
