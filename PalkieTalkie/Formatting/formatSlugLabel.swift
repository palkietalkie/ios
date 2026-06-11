import Foundation

/// Turn a snake_case slug into a display label: "lower_intermediate" → "Lower intermediate". Shared by the pickers (proficiency, speed, etc.) — generic, so it's a free function, not duplicated inside each view-model.
func formatSlugLabel(_ slug: String) -> String {
    let words = slug.split(separator: "_").map(String.init)
    guard let first = words.first else { return slug }
    let head = first.prefix(1).uppercased() + first.dropFirst().lowercased()
    let tail = words.dropFirst().map { $0.lowercased() }
    return ([head] + tail).joined(separator: " ")
}
