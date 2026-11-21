import RefineCore
import Foundation

/// Self-test commands, run from the terminal without the menu bar UI:
///
///   RefineBar --dry-run "<text>" [--style spoken]   privacy guard + request body, no network
///   RefineBar --refine "<text>" [--style spoken]    full rewrite through Groq
///   RefineBar --transcribe speech.wav [--style s]   Whisper transcript, then the rewrite
///
/// The API key comes from GROQ_API_KEY, else the keychain entry the app saved.
/// --transcribe reads an existing file for testing; the app itself never writes audio.
@MainActor
enum CLI {
    nonisolated static let commands = ["--dry-run", "--refine", "--transcribe"]

    nonisolated static func handles(_ arguments: [String]) -> Bool {
        arguments.contains { commands.contains($0) }
    }

    static func run(_ arguments: [String]) async -> Int32 {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let style = value("--style") ?? "spoken"
        let hiddenTerms = ProcessInfo.processInfo.environment["REFINE_HIDDEN_TERMS"]
            ?? UserDefaults.standard.string(forKey: "hiddenTerms") ?? ""

        do {
            guard let dir = RefineJS.defaultDirectory() else {
                throw GroqError(status: nil, message: "JS files not found. Run the binary inside RefineBar.app or set REFINE_JS_DIR.")
            }
            let js = try RefineJS(directory: dir)
            let refiner = try Refiner(js: js)

            if let text = value("--dry-run") {
                let prepared = try js.prepare(text, hiddenTerms: hiddenTerms)
                print("masked:    \(prepared.masked)")
                print("hidden:    \(prepared.hiddenCount) item(s)")
                print("refinable: \(prepared.refinable)")
                let body = try js.requestBody(masked: prepared.masked, style: style, model: js.info.defaultModel)
                let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let messages = object?["messages"] as? [[String: Any]]
                print("model:     \(object?["model"] ?? "?")  fallback: \(js.info.fallbackModel)")
                print("user msg:  \(messages?.last?["content"] ?? "?")")
                return 0
            }

            guard let apiKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? Keychain.apiKey() else {
                throw GroqError(status: nil, message: "Set GROQ_API_KEY or save a key in the app first.")
            }

            var input = value("--refine")
            if let path = value("--transcribe") {
                let audio = try Data(contentsOf: URL(fileURLWithPath: path))
                let started = Date()
                let transcript = try await Groq.transcribe(wav: audio, apiKey: apiKey)
                print(String(format: "heard   (%.2f s): %@", Date().timeIntervalSince(started), transcript))
                input = transcript
            }
            guard let input else { throw GroqError(status: nil, message: "Nothing to do.") }

            let started = Date()
            let output = try await refiner.refine(input, style: style, hiddenTerms: hiddenTerms, apiKey: apiKey)
            print(String(format: "%@ (%.2f s): %@", style, Date().timeIntervalSince(started), output ?? "(nothing to refine)"))
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
