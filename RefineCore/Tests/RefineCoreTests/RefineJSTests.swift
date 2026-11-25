import XCTest
@testable import RefineCore

/// No network: runs the real prompt.js / redact.js from Refine.popclipext.
@MainActor
final class RefineJSTests: XCTestCase {
    private static let jsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // RefineCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // RefineCore
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Refine.popclipext")

    private var js: RefineJS!

    override func setUp() async throws {
        js = try RefineJS(directory: Self.jsDirectory)
    }

    private func reply(_ content: String) -> Data {
        let object: [String: Any] = ["choices": [["message": ["content": content], "finish_reason": "stop"]]]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func userMessage(_ body: Data) throws -> (model: String, user: String, system: String) {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        return (object["model"] as? String ?? "",
                messages.last?["content"] as? String ?? "",
                messages.first?["content"] as? String ?? "")
    }

    func testInfoNamesBothModels() {
        XCTAssertTrue(js.info.apiURL.hasPrefix("https://"))
        XCTAssertFalse(js.info.defaultModel.isEmpty)
        XCTAssertFalse(js.info.fallbackModel.isEmpty)
    }

    func testPrepareMasksLinks() throws {
        let prepared = try js.prepare("td aku cek https://grafana.example.com/d/abc masih error", hiddenTerms: "")
        XCTAssertFalse(prepared.masked.contains("grafana"))
        XCTAssertTrue(prepared.masked.contains("{{LINK_1}}"))
        XCTAssertEqual(prepared.hiddenCount, 1)
        XCTAssertTrue(prepared.refinable)
    }

    func testPrepareHidesYourWords() throws {
        let prepared = try js.prepare("update for Project Falcon today", hiddenTerms: "Project Falcon")
        XCTAssertFalse(prepared.masked.contains("Falcon"))
    }

    func testOnlyALinkIsNotRefinable() throws {
        XCTAssertFalse(try js.prepare("https://example.com/x", hiddenTerms: "").refinable)
    }

    func testRewriteBodyCarriesMaskedText() throws {
        let prepared = try js.prepare("cek https://example.com/x ya", hiddenTerms: "")
        let body = try js.requestBody(masked: prepared.masked, style: "polite", model: js.info.defaultModel)
        let message = try userMessage(body)
        XCTAssertEqual(message.model, js.info.defaultModel)
        XCTAssertTrue(message.user.contains("{{LINK_1}}"))
        XCTAssertFalse(message.user.contains("example.com"))
    }

    func testTranslateBodyUsesTranslatorPrompt() throws {
        let body = try js.translateBody(masked: "Could you check the PR?", model: js.info.fallbackModel)
        let message = try userMessage(body)
        XCTAssertEqual(message.model, js.info.fallbackModel)
        XCTAssertTrue(message.system.contains("Bahasa Indonesia"))
        XCTAssertTrue(message.user.contains("Could you check the PR?"))
    }

    func testFinishRestoresPlaceholders() throws {
        let prepared = try js.prepare("cek https://example.com/x ya", hiddenTerms: "")
        let output = try js.finish(response: reply("Please check {{LINK_1}}."), itemsJSON: prepared.itemsJSON)
        XCTAssertEqual(output, "Please check https://example.com/x.")
    }

    func testFinishRejectsALostPlaceholder() throws {
        let prepared = try js.prepare("cek https://example.com/x ya", hiddenTerms: "")
        XCTAssertThrowsError(try js.finish(response: reply("Please check the link."), itemsJSON: prepared.itemsJSON)) { error in
            XCTAssertTrue((error as? RefineJS.JSError)?.isPlaceholderError == true)
        }
    }

    func testWritersNoteIsContextOnly() throws {
        let prepared = try js.prepare("saya mandi /*udah selesai, lihat https://example.com/a", hiddenTerms: "")
        XCTAssertTrue(prepared.refinable)
        XCTAssertFalse(prepared.masked.contains("example.com"))
        let message = try userMessage(try js.requestBody(masked: prepared.masked, style: "spoken", model: js.info.defaultModel))
        XCTAssertTrue(message.user.contains("<context>\nudah selesai, lihat {{LINK_1}}\n</context>"))
        XCTAssertTrue(message.user.contains("<text>\nsaya mandi\n</text>"))
        // The note's link is optional: a reply without it is fine.
        let output = try js.finish(response: reply("I took a bath."), itemsJSON: prepared.itemsJSON)
        XCTAssertEqual(output, "I took a bath.")
    }

    func testNoteOnlyIsNotRefinable() throws {
        XCTAssertFalse(try js.prepare("/*cuma catatan", hiddenTerms: "").refinable)
    }

    func testTranslateKeepsSlashStarAsText() throws {
        let prepared = try js.prepare("https://example.com/a /*b", hiddenTerms: "", notes: false)
        XCTAssertTrue(prepared.refinable)
        XCTAssertThrowsError(try js.finish(response: reply("Lihat."), itemsJSON: prepared.itemsJSON))
    }

    func testKeepSurroundingWhitespace() throws {
        XCTAssertEqual(try js.keepSurroundingWhitespace(original: " hi there\n", rewritten: "Hi there!"), " Hi there!\n")
    }
}
