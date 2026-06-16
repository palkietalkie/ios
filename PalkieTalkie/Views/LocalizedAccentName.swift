import Foundation

/// Resolves a backend accent name (the English wire value, owned by `backend/app/profile/languages.py`) to its localized display via the string catalog. Unlike language names, accents are regional proper nouns with no iOS table, so the translations live in `Localizable.xcstrings` keyed by the English name. The raw name stays the selection value; only the label is localized. A name with no catalog entry falls back to itself.
func localizedAccentName(_ name: String) -> String {
    NSLocalizedString(name, comment: "Accent display name; key is the backend English name")
}
