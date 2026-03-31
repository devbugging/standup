import Foundation

class ProjectSetupService {

    /// Generates metadata.json and project.md for a project inside its folder.
    static func generateProjectFiles(
        project: ProjectInfo,
        repoPath: String,
        apiKey: String
    ) async throws {
        let projectDir = "\(repoPath)/projects/\(project.name)"
        let fm = FileManager.default

        // Ensure project directory exists
        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

        // Write metadata.json
        try writeMetadata(project: project, projectDir: projectDir)

        // Generate and write project.md
        try await writeProjectMD(project: project, projectDir: projectDir, apiKey: apiKey)
    }

    // MARK: - metadata.json

    private static func writeMetadata(project: ProjectInfo, projectDir: String) throws {
        var metadata: [String: String] = [:]
        if !project.repoURL.isEmpty {
            metadata["repo"] = project.repoURL
        }
        if !project.websiteURL.isEmpty {
            metadata["website"] = project.websiteURL
        }

        let path = "\(projectDir)/metadata.json"
        let data = try JSONSerialization.data(
            withJSONObject: metadata,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - project.md

    private static func writeProjectMD(
        project: ProjectInfo,
        projectDir: String,
        apiKey: String
    ) async throws {
        let path = "\(projectDir)/project.md"

        var sections: [String] = []
        sections.append("# \(project.name)")
        sections.append("")

        if !project.description.isEmpty {
            sections.append(project.description)
            sections.append("")
        }

        if !project.repoURL.isEmpty {
            sections.append("**Repository:** \(project.repoURL)")
        }
        if !project.websiteURL.isEmpty {
            sections.append("**Website:** \(project.websiteURL)")
        }
        if !project.repoURL.isEmpty || !project.websiteURL.isEmpty {
            sections.append("")
        }

        // Fetch website and generate AI description if website is provided
        if !project.websiteURL.isEmpty, !apiKey.isEmpty {
            if let websiteDescription = try? await fetchAndSummarizeWebsite(
                url: project.websiteURL,
                projectName: project.name,
                apiKey: apiKey
            ) {
                sections.append("## About")
                sections.append("")
                sections.append(websiteDescription)
                sections.append("")
            }
        }

        let content = sections.joined(separator: "\n")
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Website fetch + OpenAI summary

    private static func fetchAndSummarizeWebsite(
        url: String,
        projectName: String,
        apiKey: String
    ) async throws -> String {
        // Fetch website HTML
        guard let requestURL = URL(string: url) else { return "" }
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { return "" }

        // Extract text content from HTML (strip tags, limit size)
        let textContent = extractText(from: html)
        guard !textContent.isEmpty else { return "" }

        // Truncate to ~4000 chars to stay within token limits
        let truncated = String(textContent.prefix(4000))

        // Summarize with OpenAI
        let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
        var apiRequest = URLRequest(url: apiURL)
        apiRequest.httpMethod = "POST"
        apiRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        apiRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You are a technical writer. Given the text content of a project's website, write a concise \
        description of the project (2-4 paragraphs). Focus on: what the project/product does, who \
        it's for, and key features. Write in plain markdown. Do not include headings. \
        The project is called "\(projectName)".
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Website content:\n\n\(truncated)"]
            ]
        ]

        apiRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, _) = try await URLSession.shared.data(for: apiRequest)

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: responseData)
        return chatResponse.choices.first?.message.content ?? ""
    }

    /// Strips HTML tags and extracts visible text content.
    private static func extractText(from html: String) -> String {
        var text = html

        // Remove script and style blocks
        let scriptPattern = "<script[^>]*>[\\s\\S]*?</script>"
        let stylePattern = "<style[^>]*>[\\s\\S]*?</style>"
        if let scriptRegex = try? NSRegularExpression(pattern: scriptPattern, options: .caseInsensitive) {
            text = scriptRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        if let styleRegex = try? NSRegularExpression(pattern: stylePattern, options: .caseInsensitive) {
            text = styleRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // Remove HTML tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = tagRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse whitespace
        if let wsRegex = try? NSRegularExpression(pattern: "\\s+") {
            text = wsRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
