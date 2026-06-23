import Foundation

/// Compose a default preferred name from Clerk's first/last name only. Returns "" when both are empty, the email is deliberately NOT a fallback: signing in with Apple often shares no name, and using the email local-part silently persisted garbage like "hnishio0105" as the user's name. Empty means "ask the user", which is correct.
func composePreferredName(firstName: String?, lastName: String?) -> String {
    [firstName, lastName]
        .compactMap(\.self)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}
