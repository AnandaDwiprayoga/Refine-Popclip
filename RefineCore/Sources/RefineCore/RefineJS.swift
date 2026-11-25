import Foundation
import JavaScriptCore

/// Runs the PopClip extension's own JavaScript (prompt.js, redact.js, config.js and
/// your local.config.js) inside JavaScriptCore, so the prompt, style profile and
/// privacy guard live in one place and behave exactly like the PopClip buttons.
/// Not thread-safe: use it from the main actor only.
@MainActor
public final class RefineJS {
    public struct Prepared {
        public let masked: String
        public let itemsJSON: String
        public let hiddenCount: Int
        public let refinable: Bool
    }

    public struct Info: Decodable {
        public let apiURL: String
        public let defaultModel: String
        public let fallbackModel: String
    }

    public struct JSError: LocalizedError {
        public let message: String
        public let isPlaceholderError: Bool
        public var errorDescription: String? { message }
    }

    private let context: JSContext
    private let bridge: JSValue
    public let info: Info

    /// The files the bridge loads. local.config.js is optional.
    public static let files = ["config.js", "prompt.js", "redact.js", "local.config.js"]

    /// Finds the JS next to the app or extension (Resources/js on macOS, js/ in an
    /// iOS bundle), or in REFINE_JS_DIR.
    public static func defaultDirectory(bundle: Bundle = .main) -> URL? {
        if let dir = ProcessInfo.processInfo.environment["REFINE_JS_DIR"] {
            return URL(fileURLWithPath: dir)
        }
        if let res = bundle.resourceURL?.appendingPathComponent("js"),
           FileManager.default.fileExists(atPath: res.appendingPathComponent("prompt.js").path) {
            return res
        }
        return nil
    }

    public init(directory: URL) throws {
        var sources: [String: String] = [:]
        for name in Self.files {
            let url = directory.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                sources[name] = text
            } else if name != "local.config.js" {
                throw JSError(message: "Missing \(name) in \(directory.path). Rebuild to bundle Refine's JS.", isPlaceholderError: false)
            }
        }

        guard let context = JSContext() else {
            throw JSError(message: "Could not start JavaScriptCore", isPlaceholderError: false)
        }
        context.exceptionHandler = { ctx, exception in ctx?.exception = exception }
        self.context = context

        // A minimal CommonJS loader: enough for require("./x.js") between the
        // extension's files. A missing file throws MODULE_NOT_FOUND, which
        // config.js treats as "no local config".
        let loaderSource = #"""
        (function (sources) {
          const cache = {};
          function require(name) {
            const file = String(name).replace(/^\.\//, "");
            if (cache[file]) return cache[file].exports;
            if (!Object.prototype.hasOwnProperty.call(sources, file)) {
              const error = new Error("Cannot find module '" + name + "'");
              error.code = "MODULE_NOT_FOUND";
              throw error;
            }
            const module = { exports: {} };
            cache[file] = module;
            new Function("module", "exports", "require", sources[file])(module, module.exports, require);
            return module.exports;
          }
          const prompt = require("./prompt.js");
          const redact = require("./redact.js");
          return {
            info() {
              return JSON.stringify({
                apiURL: prompt.API_URL,
                defaultModel: prompt.DEFAULT_MODEL,
                fallbackModel: prompt.FALLBACK_MODEL,
              });
            },
            prepare(text, hiddenTerms, notes) {
              const { masked, items: allItems } = redact.redact(String(text).trim(), hiddenTerms || "");
              // Rewrites honor "/*" writer's notes, like refine.js does.
              const { draft, items } = notes ? prompt.prepareRewrite(masked, allItems) : { draft: masked, items: allItems };
              return JSON.stringify({
                masked,
                items: JSON.stringify(items),
                hiddenCount: items.length,
                refinable: redact.hasRefinableText(draft),
              });
            },
            body(masked, styleId, model) {
              return JSON.stringify(prompt.buildRequestBody(masked, styleId, model));
            },
            translateBody(masked, model) {
              return JSON.stringify(prompt.buildTranslateRequestBody(masked, model));
            },
            wrap(original, rewritten) {
              return prompt.keepSurroundingWhitespace(String(original), String(rewritten));
            },
            finish(responseJSON, itemsJSON) {
              try {
                return redact.restore(prompt.extractText(JSON.parse(responseJSON)), JSON.parse(itemsJSON));
              } catch (error) {
                if (error instanceof redact.PlaceholderError) error.message = "PLACEHOLDER: " + error.message;
                throw error;
              }
            },
          };
        })
        """#

        let loader = context.evaluateScript(loaderSource)
        let bridge = loader?.call(withArguments: [sources])
        if let exception = context.exception {
            throw JSError(message: "Loading Refine's JS failed: \(exception)", isPlaceholderError: false)
        }
        guard let bridge, bridge.isObject else {
            throw JSError(message: "Loading Refine's JS failed", isPlaceholderError: false)
        }
        self.bridge = bridge

        let infoJSON = try Self.call(context, bridge, "info", [])
        self.info = try JSONDecoder().decode(Info.self, from: Data(infoJSON.utf8))
    }

    /// Masks the text for sending. With `notes` (rewrites), text after "/*" is a writer's
    /// note: it's masked too, sent as context, and left out of the result.
    public func prepare(_ text: String, hiddenTerms: String, notes: Bool = true) throws -> Prepared {
        struct Raw: Decodable { let masked: String; let items: String; let hiddenCount: Int; let refinable: Bool }
        let json = try Self.call(context, bridge, "prepare", [text, hiddenTerms, notes])
        let raw = try JSONDecoder().decode(Raw.self, from: Data(json.utf8))
        return Prepared(masked: raw.masked, itemsJSON: raw.items, hiddenCount: raw.hiddenCount, refinable: raw.refinable)
    }

    /// The chat request for a rewrite in one of prompt.js's styles (me, polite, short, fix, spoken).
    public func requestBody(masked: String, style: String, model: String) throws -> Data {
        Data(try Self.call(context, bridge, "body", [masked, style, model]).utf8)
    }

    /// The chat request for the 🇮🇩 translation into Bahasa Indonesia.
    public func translateBody(masked: String, model: String) throws -> Data {
        Data(try Self.call(context, bridge, "translateBody", [masked, model]).utf8)
    }

    /// Keeps the leading/trailing whitespace of the original around a rewrite.
    public func keepSurroundingWhitespace(original: String, rewritten: String) throws -> String {
        try Self.call(context, bridge, "wrap", [original, rewritten])
    }

    /// Reads the model's reply and puts the hidden items back. Throws if a
    /// placeholder was lost, so a broken result is never shown.
    public func finish(response: Data, itemsJSON: String) throws -> String {
        let json = String(decoding: response, as: UTF8.self)
        return try Self.call(context, bridge, "finish", [json, itemsJSON])
    }

    private static func call(_ context: JSContext, _ bridge: JSValue, _ name: String, _ args: [Any]) throws -> String {
        context.exception = nil
        let result = bridge.invokeMethod(name, withArguments: args)
        if let exception = context.exception {
            context.exception = nil
            var message = exception.objectForKeyedSubscript("message")?.toString() ?? exception.toString() ?? "JS error"
            let isPlaceholder = message.hasPrefix("PLACEHOLDER: ")
            if isPlaceholder { message = String(message.dropFirst("PLACEHOLDER: ".count)) }
            throw JSError(message: message, isPlaceholderError: isPlaceholder)
        }
        guard let result, result.isString, let string = result.toString() else {
            throw JSError(message: "\(name) returned nothing", isPlaceholderError: false)
        }
        return string
    }
}
