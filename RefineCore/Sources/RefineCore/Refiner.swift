import Foundation

/// The same flow as runWithGuard in Refine.popclipext/refine.js: privacy guard,
/// request, put hidden items back, and one retry on the fallback model.
@MainActor
public final class Refiner {
    public enum Mode: Hashable, Sendable {
        /// A rewrite in one of prompt.js's styles: "me", "polite", "short", "fix" or "spoken".
        case rewrite(style: String)
        /// The 🇮🇩 button: a Bahasa Indonesia translation of any text.
        case translate
    }

    public let js: RefineJS
    private let chatURL: URL

    public init(js: RefineJS) throws {
        self.js = js
        guard let url = URL(string: js.info.apiURL) else {
            throw GroqError(status: nil, message: "Bad API_URL in prompt.js")
        }
        chatURL = url
    }

    /// Returns the rewrite, or nil when there is nothing worth sending.
    public func refine(_ text: String, style: String, hiddenTerms: String, apiKey: String) async throws -> String? {
        try await run(text, mode: .rewrite(style: style), hiddenTerms: hiddenTerms, apiKey: apiKey)
    }

    /// Returns the result (hidden items put back), or nil when there is nothing worth sending.
    public func run(_ text: String, mode: Mode, hiddenTerms: String, apiKey: String) async throws -> String? {
        // Only `masked` leaves the device: links, emails, keys, code, numbers and your
        // hidden terms are placeholders by now.
        let prepared = try js.prepare(text, hiddenTerms: hiddenTerms, notes: mode != .translate)
        guard prepared.refinable else { return nil }

        func attempt(_ model: String) async throws -> String {
            let body: Data
            switch mode {
            case .rewrite(let style): body = try js.requestBody(masked: prepared.masked, style: style, model: model)
            case .translate: body = try js.translateBody(masked: prepared.masked, model: model)
            }
            let reply = try await Groq.chat(url: chatURL, body: body, apiKey: apiKey)
            try Task.checkCancellation()
            return try js.finish(response: reply, itemsJSON: prepared.itemsJSON)
        }

        let primary = js.info.defaultModel
        let fallback = js.info.fallbackModel
        do {
            return try await attempt(primary)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let groq = error as? GroqError, groq.status == 401 { throw error }
            if primary == fallback { throw error }
            // Preview model removed, rate limited (limits are per model), a lost
            // placeholder, or a bad reply: try once more on the production model.
            return try await attempt(fallback)
        }
    }
}
