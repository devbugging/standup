import Foundation

enum TranscriptionError: LocalizedError {
    case noAPIKey
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "OpenAI API key not configured. Open Settings to add it."
        case .requestFailed(let msg): return "Transcription failed: \(msg)"
        case .invalidResponse: return "Invalid response from OpenAI Whisper"
        }
    }
}

class WhisperService {

    func transcribe(fileURL: URL, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriptionError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        var body = Data()

        // model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.requestFailed("HTTP \(httpResponse.statusCode): \(errorMsg)")
        }

        struct WhisperResponse: Decodable {
            let text: String
        }

        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return decoded.text
    }
}
