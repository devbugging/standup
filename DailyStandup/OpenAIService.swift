import Foundation

enum OpenAIError: LocalizedError {
    case noAPIKey
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "OpenAI API key not configured. Open Settings to add it."
        case .requestFailed(let msg): return "OpenAI error: \(msg)"
        case .invalidResponse: return "Could not parse OpenAI response"
        }
    }
}

struct StructuredStandup: Decodable {
    struct Item: Decodable {
        let project: String
        let description: String
    }
    let standup: [Item]
    let todos: [Item]
}

class OpenAIService {

    func structureTranscript(
        rawText: String,
        projects: [String],
        userName: String,
        userRoles: String
    ) async throws -> (standup: String, todos: String) {
        let apiKey = AppState.shared.settings.openAIAPIKey
        guard !apiKey.isEmpty else { throw OpenAIError.noAPIKey }

        let projectList = projects.joined(separator: ", ")

        let systemPrompt = """
        You are a standup note formatter. You receive a raw voice transcript from a daily standup \
        and restructure it into clean, concise bullet points.

        Rules:
        - Match every item to the correct project name from this list: [\(projectList)]. \
          Use EXACT project names from the list. If an item doesn't match any project, use "General".
        - Each standup item describes work DONE (past tense, concise).
        - Each todo item describes work TO BE DONE (concise, actionable).
        - Fix grammar, remove filler words, make each item one clear sentence.
        - If the speaker mentions blockers, include them as standup items prefixed with "Blocker:".
        - The person's name is "\(userName)" and their roles are "\(userRoles)".

        Return ONLY valid JSON matching this schema (no markdown, no code fences):
        {
          "standup": [{"project": "ProjectName", "description": "What was done"}],
          "todos": [{"project": "ProjectName", "description": "What needs to be done"}]
        }

        If there are no todos, return an empty array for todos. Same for standup.
        """

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Here is the raw standup transcript:\n\n\(rawText)"]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.requestFailed("HTTP \(httpResponse.statusCode): \(errorMsg)")
        }

        // Parse OpenAI response
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError.invalidResponse
        }

        // Strip markdown code fences if present
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw OpenAIError.invalidResponse
        }

        let structured = try JSONDecoder().decode(StructuredStandup.self, from: jsonData)

        // Format standup lines
        let standupLines = structured.standup.map { item in
            "- **\(item.project):** \(item.description)"
        }.joined(separator: "\n")

        // Format todo lines
        let todoLines = structured.todos.map { item in
            "\(item.project): \(item.description)"
        }.joined(separator: "\n")

        return (standupLines, todoLines)
    }
}
