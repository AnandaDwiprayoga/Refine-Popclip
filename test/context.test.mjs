// Writer's note tests ("/*" context). Run: node --test test/

import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { splitContext, prepareRewrite, buildRequestBody, buildTranslateRequestBody, SYSTEM_PROMPT } = require(
  "../Refine.popclipext/prompt.js",
);
const guard = require("../Refine.popclipext/redact.js");
const { restore, hasRefinableText, PlaceholderError } = guard;
const redact = (text, hiddenTerms = "") => guard.redact(text, hiddenTerms, {});

const userContent = (body) => body.messages[body.messages.length - 1].content;

test("splitContext: note runs to the end of the text", () => {
  assert.deepEqual(splitContext("saya mandi di seberang /*i already finish mandi"), {
    draft: "saya mandi di seberang",
    context: "i already finish mandi",
  });
});

test("splitContext: */ closes a note in the middle", () => {
  assert.deepEqual(splitContext("aku deploy /*besok pagi*/ terus kabarin QA ya"), {
    draft: "aku deploy  terus kabarin QA ya",
    context: "besok pagi",
  });
});

test("splitContext: several notes are joined, multi-line notes kept", () => {
  const { draft, context } = splitContext("dia /*Budi*/ udah approve\n/*for my manager\nkeep it short");
  assert.equal(draft, "dia  udah approve");
  assert.equal(context, "Budi\nfor my manager\nkeep it short");
});

test("splitContext: a note at the very start", () => {
  assert.deepEqual(splitContext("/*past tense*/ saya makan"), { draft: "saya makan", context: "past tense" });
});

test("splitContext: /* inside a word or path is text, not a note", () => {
  for (const text of ["cek file src/*.js ya", "glob nya docs/* aja", "a/*b*/c"]) {
    assert.deepEqual(splitContext(text), { draft: text, context: "" });
  }
});

test("splitContext: no note, empty note, note only", () => {
  assert.deepEqual(splitContext("biasa aja"), { draft: "biasa aja", context: "" });
  assert.deepEqual(splitContext("halo /*"), { draft: "halo", context: "" });
  assert.deepEqual(splitContext("/*cuma catatan"), { draft: "", context: "cuma catatan" });
});

test("buildRequestBody: note goes in <context>, not in <text>", () => {
  const content = userContent(buildRequestBody("saya mandi di seberang /*i already finish mandi", "me"));
  assert.match(content, /<context>\ni already finish mandi\n<\/context>/);
  assert.match(content, /<text>\nsaya mandi di seberang\n<\/text>/);
  assert.ok(!content.split("<text>")[1].includes("finish"));
});

test("buildRequestBody: no <context> block without a note", () => {
  assert.ok(!userContent(buildRequestBody("saya mandi", "fix")).includes("<context>"));
});

test("system prompt is identical with and without a note (prompt cache)", () => {
  const withNote = buildRequestBody("saya mandi /*udah", "me").messages[0].content;
  const without = buildRequestBody("saya mandi", "me").messages[0].content;
  assert.equal(withNote, SYSTEM_PROMPT);
  assert.equal(without, SYSTEM_PROMPT);
});

test("translate keeps /* as literal text", () => {
  const content = userContent(buildTranslateRequestBody("run rm /*tmp first"));
  assert.ok(content.includes("rm /*tmp first"));
  assert.ok(!content.includes("<context>"));
});

test("a link inside the note is masked before sending", () => {
  const { masked } = redact("saya mandi /*lihat https://example.com/a dulu");
  assert.ok(!masked.includes("example.com"));
  const content = userContent(buildRequestBody(masked, "me"));
  assert.ok(!content.includes("example.com"));
  assert.match(content, /<context>\nlihat \{\{LINK_1\}\} dulu\n<\/context>/);
});

test("/* inside inline code or a URL can't start a note", () => {
  const { masked } = redact("jalanin `rm -rf /*` jangan ya, cek https://example.com /*nanti");
  const { draft, context } = splitContext(masked);
  assert.equal(context, "nanti");
  assert.match(draft, /\{\{CODE_1\}\}/);
  assert.match(draft, /\{\{LINK_1\}\}/);
});

test("prepareRewrite: placeholders only in the note are optional", () => {
  const { masked, items } = redact("cek https://a.example.com ya /*detail di https://b.example.com");
  const { draft, items: marked } = prepareRewrite(masked, items);
  assert.equal(draft, "cek {{LINK_1}} ya");
  assert.equal(marked.find((i) => i.placeholder === "{{LINK_1}}").optional, undefined);
  assert.equal(marked.find((i) => i.placeholder === "{{LINK_2}}").optional, true);
  // A placeholder in both the draft and the note stays required.
  const both = redact("cek https://a.example.com /*https://a.example.com itu prod");
  assert.ok(prepareRewrite(both.masked, both.items).items.every((i) => !i.optional));
});

test("restore: optional placeholders may be dropped, required ones may not", () => {
  const { masked, items } = redact("cek https://a.example.com ya /*detail di https://b.example.com");
  const { items: marked } = prepareRewrite(masked, items);
  assert.equal(restore("Please check {{LINK_1}}.", marked), "Please check https://a.example.com.");
  // If the model does use a note's placeholder, it's still put back.
  assert.equal(restore("See {{LINK_1}} ({{LINK_2}}).", marked), "See https://a.example.com (https://b.example.com).");
  assert.throws(() => restore("Please check it.", marked), PlaceholderError);
  assert.throws(() => restore("Check {{LINK_1}} {{LINK_3}}", marked), PlaceholderError);
});

test("note-only selection has nothing to refine", () => {
  const { masked, items } = redact("/*ini cuma catatan");
  assert.equal(hasRefinableText(prepareRewrite(masked, items).draft), false);
});
