import Foundation
import JavaScriptCore

/// Runs the PopClip extension's own JavaScript (prompt.js, redact.js, config.js and
/// your local.config.js) inside JavaScriptCore, so the prompt, style profile and
/// privacy guard live in one place and behave exactly like the PopClip buttons.
/// Not thread-safe: use it from the main actor only.
@MainActor
final class RefineJS {
    struct Prepared {
        let masked: String
        let itemsJSON: String
        let hiddenCount: Int
        let refinable: Bool
    }

    struct Info: Decodable {
        let apiURL: String
        let defaultModel: String
        let fallbackModel: String
    }

    struct JSError: LocalizedError {
        let message: String
        let isPlaceholderError: Bool
        var errorDescription: String? { message }
    }

    private let context: JSContext
    private let bridge: JSValue
    let info: Info

    /// The files the bridge loads. local.config.js is optional.
    static let files = ["config.js", "prompt.js", "redact.js", "local.config.js"]

    /// Finds the JS next to the app (Contents/Resources/js), or in REFINE_JS_DIR.
    static func defaultDirectory() -> URL? {
        if let dir = ProcessInfo.processInfo.environment["REFINE_JS_DIR"] {
            return URL(fileURLWithPath: dir)
        }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("js"),
           FileManager.default.fileExists(atPath: res.appendingPathComponent("prompt.js").path) {
            return res
        }
        return nil
    }

    init(directory: URL) throws {
        var sources: [String: String] = [:]
        for name in Self.files {
            let url = directory.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                sources[name] = text
            } else if name != "local.config.js" {
                throw JSError(message: "Missing \(name) in \(directory.path). Rebuild with build.sh.", isPlaceholderError: false)
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
            prepare(text, hiddenTerms) {
              const { masked, items } = redact.redact(String(text).trim(), hiddenTerms || "");
              return JSON.stringify({
                masked,
                items: JSON.stringify(items),
                hiddenCount: items.length,
                refinable: redact.hasRefinableText(masked),
              });
            },
            body(masked, styleId, model) {
              return JSON.stringify(prompt.buildRequestBody(masked, styleId, model));
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

    func prepare(_ text: String, hiddenTerms: String) throws -> Prepared {
        struct Raw: Decodable { let masked: String; let items: String; let hiddenCount: Int; let refinable: Bool }
        let json = try Self.call(context, bridge, "prepare", [text, hiddenTerms])
        let raw = try JSONDecoder().decode(Raw.self, from: Data(json.utf8))
        return Prepared(masked: raw.masked, itemsJSON: raw.items, hiddenCount: raw.hiddenCount, refinable: raw.refinable)
    }

    func requestBody(masked: String, style: String, model: String) throws -> Data {
        Data(try Self.call(context, bridge, "body", [masked, style, model]).utf8)
    }

    /// Reads the model's reply and puts the hidden items back. Throws if a
    /// placeholder was lost, so a broken result is never shown.
    func finish(response: Data, itemsJSON: String) throws -> String {
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
