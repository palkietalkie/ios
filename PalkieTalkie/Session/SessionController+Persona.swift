import Foundation

/// Persona resolution: pin `selectedPersonaId` to a real server persona before a session starts, and recover when the cached id has gone stale. Split out of SessionController so the core file stays the phase machine + lifecycle.
@MainActor
extension SessionController {
    func resolvePersonaIdIfNeeded() async throws -> Bool {
        if UUID(uuidString: selectedPersonaId) != nil { return true }
        return try await pickFirstPersonaFromServer()
    }

    /// Pulls /personas and pins selectedPersonaId to the first preset. Called when nothing is cached, and when /start
    /// 404s on the cached UUID (user-created persona deleted, dev DB reset, preset list rotated → UUID5 changed).
    func pickFirstPersonaFromServer() async throws -> Bool {
        let personas = try await backend.getPersonas(search: nil, sort: "recommended")
        let resolved =
            personas.first(where: { $0.isPreset })
                ?? personas.first
        guard let resolved else { return false }
        selectedPersonaId = resolved.id
        return true
    }
}
