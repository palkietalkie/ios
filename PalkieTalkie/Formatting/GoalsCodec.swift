import Foundation

/// The multi-select goals fold into the single `users.goals` TEXT: selected preset slugs (in backend order) + a free-text "Other", comma-joined. Shared by onboarding and Practice so the two never drift. Backend `format_goals_for_prompt` humanizes the slugs and passes the Other text through.
func joinGoals(presets: [String], selected: Set<String>, other: String) -> String {
    var parts = presets.filter { selected.contains($0) }
    let trimmed = other.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { parts.append(trimmed) }
    return parts.joined(separator: ", ")
}

/// Inverse of `joinGoals`: split a stored goals string back into selected preset slugs (those matching the known presets) and the leftover free-text "Other" (rejoined, so a comma inside the Other text survives a round-trip).
func splitGoals(_ raw: String, presets: [String]) -> (selected: Set<String>, other: String) {
    let known = Set(presets)
    let parts = raw.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    let selected = Set(parts.filter { known.contains($0) })
    let other = parts.filter { !known.contains($0) }.joined(separator: ", ")
    return (selected, other)
}
