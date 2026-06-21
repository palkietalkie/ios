import Foundation

/// Resolves a backend goal slug (the wire value, owned by `backend/app/profile/goal.py`) to its localized chip label via the string catalog. The slug never shows to the user; the English label is the catalog key, so other locales (e.g. ja 駐在 / 留学) translate it without mixing scripts into one string. An unknown slug falls back to itself.
func localizedGoalLabel(_ slug: String) -> String {
    let key: String
    switch slug {
    case "everyday_conversation": key = "Everyday conversation"
    case "making_friends": key = "Making friends"
    case "dating_relationships": key = "Dating & relationships"
    case "family": key = "Family & in-laws"
    case "work_meetings": key = "Work & meetings"
    case "job_interview": key = "Job interviews"
    case "public_speaking": key = "Public speaking"
    case "living_abroad": key = "Living abroad"
    case "studying_abroad": key = "Studying abroad"
    case "travel": key = "Travel"
    default: return slug
    }
    return NSLocalizedString(key, comment: "Goal chip label; key is the English label, slug owned by backend goal.py")
}
