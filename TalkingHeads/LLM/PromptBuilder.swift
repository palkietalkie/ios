import Foundation

struct Persona: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let systemPrompt: String
    let voiceStyle: String?
}

struct Scenario: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let systemPromptAddition: String
}

struct PromptBuilder {
    static let defaultSystemPrompt = """
        You are an English conversation tutor. Your student is a Japanese English learner \
        at an intermediate-to-advanced level.

        Rules:
        - Speak naturally, like a real person — not a textbook
        - Keep responses concise (1-3 sentences) for natural conversation flow
        - Introduce interesting vocabulary, idioms, and expressions the student may not know
        - If the student makes a grammar or pronunciation error, gently correct it inline
        - Suggest interesting topics if the conversation stalls
        - Never say "let me know when you're ready" or ask verification questions
        - Start speaking immediately when it's your turn
        """

    static func buildSystemPrompt(persona: Persona?, scenario: Scenario?) -> String {
        var prompt = defaultSystemPrompt

        if let persona {
            prompt += "\n\n" + persona.systemPrompt
        }

        if let scenario {
            prompt += "\n\n" + scenario.systemPromptAddition
        }

        return prompt
    }

    static func buildHistory(from messages: [Message]) -> [(role: String, content: String)] {
        messages.compactMap { message in
            switch message.role {
            case .user:
                return (role: "user", content: message.content)
            case .assistant:
                return (role: "assistant", content: message.content)
            case .system:
                return nil
            }
        }
    }

    // MARK: - Loading from bundled JSON

    static func loadPersonas() -> [Persona] {
        guard let url = Bundle.main.url(forResource: "personas", withExtension: "json", subdirectory: "Personas"),
              let data = try? Data(contentsOf: url),
              let personas = try? JSONDecoder().decode([Persona].self, from: data) else {
            return defaultPersonas
        }
        return personas
    }

    static func loadScenarios() -> [Scenario] {
        guard let url = Bundle.main.url(forResource: "scenarios", withExtension: "json", subdirectory: "Personas"),
              let data = try? Data(contentsOf: url),
              let scenarios = try? JSONDecoder().decode([Scenario].self, from: data) else {
            return defaultScenarios
        }
        return scenarios
    }

    // MARK: - Defaults

    static let defaultPersonas: [Persona] = [
        Persona(
            id: "default",
            name: "Alex",
            description: "A friendly, encouraging English tutor",
            systemPrompt: "Your name is Alex. You are warm, patient, and encouraging. You love helping people improve their English through natural conversation.",
            voiceStyle: nil
        ),
        Persona(
            id: "jimmy-carr",
            name: "Jimmy Carr",
            description: "British comedian known for sharp one-liners",
            systemPrompt: "You are Jimmy Carr, the British comedian. Stay in character — use dry wit, sharp one-liners, and your trademark deadpan delivery. Still help with English, but make it entertaining. Use British English expressions and slang.",
            voiceStyle: "british-male"
        ),
        Persona(
            id: "jimmy-o-yang",
            name: "Jimmy O. Yang",
            description: "Actor and comedian from Silicon Valley",
            systemPrompt: "You are Jimmy O. Yang, the actor and comedian known for Silicon Valley. Be funny and relatable. Share stories and cultural observations. Use casual American English with occasional pop culture references.",
            voiceStyle: "american-male"
        ),
    ]

    static let defaultScenarios: [Scenario] = [
        Scenario(
            id: "casual",
            name: "Casual Chat",
            description: "Just a normal conversation",
            systemPromptAddition: "This is a casual conversation. Talk about whatever comes up naturally — hobbies, weekend plans, food, travel, funny stories."
        ),
        Scenario(
            id: "job-interview",
            name: "Job Interview",
            description: "Practice answering interview questions",
            systemPromptAddition: "You are conducting a job interview. Ask common interview questions, give feedback on the student's answers, and teach professional vocabulary and phrases used in interviews."
        ),
        Scenario(
            id: "debate",
            name: "Friendly Debate",
            description: "Practice arguing a position",
            systemPromptAddition: "Engage in a friendly debate. Pick a mildly controversial topic and take the opposite side of whatever the student says. Teach persuasive language, transition phrases, and how to structure arguments in English."
        ),
        Scenario(
            id: "news-discussion",
            name: "News Discussion",
            description: "Discuss current events",
            systemPromptAddition: "Discuss current events and news. Bring up interesting topics, explain complex vocabulary related to politics, economics, and world events. Help the student express opinions about news in English."
        ),
    ]
}
