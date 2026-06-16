import Foundation

/// Maps the backend's English language name (the wire value, owned by `backend/app/profile/languages.py`) to a localized display name using iOS's own language tables — so the picker reads "日本語" in a Japanese UI without us hand-translating 50 names. The English name still travels on the wire; only the display is localized. Unknown names (constructed languages with no OS entry, or a language the backend adds later) fall back to the English name, so this degrades gracefully rather than showing a code.
func localizedLanguageName(_ englishName: String) -> String {
    guard let code = languageCodeByEnglishName[englishName] else { return englishName }
    let localized = Locale.current.localizedString(forLanguageCode: code)
    if let localized, !localized.isEmpty, localized.caseInsensitiveCompare(code) != .orderedSame {
        return localized
    }
    return englishName
}

/// BCP-47 codes for the backend's `LanguageName` literals. A code mapping, not a second copy of the list: a name the backend adds that isn't here simply falls back to its English display. Constructed languages with no ISO code (High Valyrian, Klingon) are intentionally absent.
private let languageCodeByEnglishName: [String: String] = [
    "English": "en", "Spanish": "es", "Mandarin Chinese": "zh", "Cantonese": "yue",
    "French": "fr", "German": "de", "Japanese": "ja", "Korean": "ko", "Italian": "it",
    "Portuguese": "pt", "Russian": "ru", "Arabic": "ar", "Hindi": "hi", "Bengali": "bn",
    "Vietnamese": "vi", "Thai": "th", "Indonesian": "id", "Turkish": "tr", "Polish": "pl",
    "Dutch": "nl", "Swedish": "sv", "Norwegian": "nb", "Danish": "da", "Finnish": "fi",
    "Greek": "el", "Hebrew": "he", "Hungarian": "hu", "Czech": "cs", "Slovak": "sk",
    "Ukrainian": "uk", "Romanian": "ro", "Persian": "fa", "Tagalog": "tl", "Swahili": "sw",
    "Malay": "ms", "Urdu": "ur", "Latin": "la", "Irish": "ga", "Scottish Gaelic": "gd",
    "Welsh": "cy", "Hawaiian": "haw", "Zulu": "zu", "Haitian Creole": "ht", "Yiddish": "yi",
    "Navajo": "nv", "Esperanto": "eo",
]
