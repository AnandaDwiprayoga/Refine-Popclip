import Foundation

public struct GroqError: LocalizedError {
    public let status: Int?
    public let message: String
    public var errorDescription: String? { message }

    public init(status: Int?, message: String) {
        self.status = status
        self.message = message
    }
}

/// Groq's OpenAI-compatible API: Whisper transcription and chat completions.
public enum Groq {
    public static let transcriptionURL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    public static let whisperModel = "whisper-large-v3-turbo"

    /// Whisper uses the prompt as "what came before", so a code-switched sample
    /// nudges it to keep English words in English and Bahasa words in Bahasa.
    public static let whisperHint =
        "Oke, jadi aku mau tanya soal API yang di staging, udah di-deploy belum ya? The BE team said the PR is merged, tapi masih error 500."

    /// Sends an in-memory WAV and returns the transcript. Nothing is written to disk.
    public static func transcribe(wav: Data, apiKey: String) async throws -> String {
        let boundary = "RefineBar-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("model", whisperModel)
        field("response_format", "json")
        field("temperature", "0")
        field("prompt", whisperHint)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: transcriptionURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let data = try await send(request, body: body, what: "Transcription")
        struct Reply: Decodable { let text: String }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw GroqError(status: nil, message: "Unexpected transcription reply")
        }
        return reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Posts a chat completions body built by prompt.js and returns the raw JSON reply.
    public static func chat(url: URL, body: Data, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request, body: body, what: "Rewrite")
    }

    private static func send(_ request: URLRequest, body: Data, what: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 {
                throw GroqError(status: 401, message: "Groq rejected the API key. Check it in settings.")
            }
            if status == 429 {
                throw GroqError(status: 429, message: "Groq rate limit reached. Try again in a moment.")
            }
            var detail = ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                detail = ": \(message)"
            }
            throw GroqError(status: status, message: "\(what) failed (HTTP \(status))\(detail)")
        }
        return data
    }
}

private extension Data {
    mutating func append(_ string: String) { append(Data(string.utf8)) }
}
