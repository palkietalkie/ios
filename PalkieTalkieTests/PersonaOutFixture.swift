@testable import PalkieTalkie

/// Test-fixture initializer for the generated PersonaOut. The many view/logic tests that build a persona don't care about `sort_weight` (a server-side picker-ordering hint), so this keeps their fixtures terse: it mirrors the pre-sortWeight field list and forwards sortWeight: nil. It deliberately does NOT default fields the tests assert on — a backend RENAME of any of these breaks this forwarder and surfaces the drift, while a purely additive field (like sortWeight was) stays defaulted here instead of churning every call site.
extension PersonaOut {
    init(
        id: String,
        name: String,
        description: String,
        voiceId: String,
        role: String?,
        age: String?,
        background: String?,
        vocabularyRegister: String?,
        conversationalStyle: String?,
        topicalPreferences: String?,
        isPreset: Bool,
        isPublic: Bool,
        isOwner: Bool,
        likeCount: Int,
        likedByMe: Bool,
    ) {
        self.init(
            id: id,
            name: name,
            description: description,
            voiceId: voiceId,
            role: role,
            age: age,
            background: background,
            vocabularyRegister: vocabularyRegister,
            conversationalStyle: conversationalStyle,
            topicalPreferences: topicalPreferences,
            isPreset: isPreset,
            isPublic: isPublic,
            isOwner: isOwner,
            likeCount: likeCount,
            likedByMe: likedByMe,
            sortWeight: nil,
        )
    }
}
