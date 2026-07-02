import Foundation

/// Transliterate non-Latin-script text (Japanese kana + kanji, Chinese hanzi, etc.) to Latin letters for a caption reading aid. On-device, no network: a live caption can't afford a server round-trip per line. Uses CFStringTokenizer's Latin-transcription attribute, which resolves CJK readings via the system's morphological dictionary (so 今日 becomes "kyō", not a per-character guess) and yields pinyin for Chinese. Readings of ambiguous kanji/names are a best guess and occasionally wrong, which is acceptable for a reading aid. Latin-script input (Spanish, French) has nothing to transcribe and passes through unchanged.
func romanize(_ text: String) -> String {
    guard !text.isEmpty else { return text }
    let cf = text as CFString
    let tokenizer = CFStringTokenizerCreate(
        kCFAllocatorDefault,
        cf,
        CFRangeMake(0, CFStringGetLength(cf)),
        kCFStringTokenizerUnitWordBoundary,
        nil,
    )
    var pieces: [String] = []
    while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
        let latin = CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer, kCFStringTokenizerAttributeLatinTranscription,
        )
        if let latin = latin as? String, !latin.isEmpty {
            pieces.append(latin)
        }
    }
    // No tokens carried a transcription (e.g. already-Latin text the tokenizer leaves alone) → keep the original.
    guard !pieces.isEmpty else { return text }
    // Per-token trim + drop-empties collapses the stray runs of whitespace the tokenizer emits around already-Latin words.
    return pieces
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

/// True when the text contains a non-Latin script the romanizer can usefully transliterate (CJK ideographs, kana, hangul, Devanagari, etc.). Drives whether to OFFER romanized captions at all: gating on the actual caption content, not the target-language setting, keeps the feature script-driven rather than hardcoding which languages are non-Latin.
func hasNonLatinScript(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        switch scalar.value {
        case 0x3040 ... 0x30FF, // hiragana + katakana
             0x3400 ... 0x4DBF, // CJK ext A
             0x4E00 ... 0x9FFF, // CJK unified
             0xAC00 ... 0xD7AF, // hangul syllables
             0x0900 ... 0x097F, // devanagari
             0xF900 ... 0xFAFF: // CJK compatibility ideographs
            true
        default:
            false
        }
    }
}
