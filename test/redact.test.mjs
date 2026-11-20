// Privacy guard tests. Run: node --test test/
// All secrets below are fake, made-up values in the right shape.

import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const guard = require("../Refine.popclipext/redact.js");
const { restore, hasRefinableText, PlaceholderError } = guard;
// Test the public defaults: ignore whatever is in your local.config.js.
const redact = (text, hiddenTerms, config = {}) => guard.redact(text, hiddenTerms, config);

// The sensitive value must not appear in what gets sent, and must come back on restore.
function assertHidden(text, secret, type, hiddenTerms) {
  const { masked, items } = redact(text, hiddenTerms);
  assert.ok(!masked.includes(secret), `"${secret}" leaked into: ${masked}`);
  const item = items.find((i) => i.value === secret);
  assert.ok(item, `"${secret}" not recorded; items: ${JSON.stringify(items)}`);
  if (type) assert.equal(item.type, type);
  assert.equal(restore(masked, items), text, "round trip must give back the original");
  return masked;
}

function assertKept(text, fragment) {
  const { masked } = redact(text);
  assert.ok(masked.includes(fragment), `"${fragment}" should be sent as text, got: ${masked}`);
}

const fakeGroq = "gsk_" + "Ab12Cd34Ef56Gh78Ij90Kl12Mn34Op56Qr78St90Uv12Wx34";

test("links: full URLs, bare domains, trailing punctuation", () => {
  const m = assertHidden("cek ini ya https://bitbucket.org/acme/app/pull-requests/123.", "https://bitbucket.org/acme/app/pull-requests/123", "LINK");
  assert.match(m, /\{\{LINK_1\}\}\.$/); // the sentence's period stays outside
  assertHidden("dashboard nya di grafana.internal/d/abc?from=now-1h ya", "grafana.internal/d/abc?from=now-1h", "LINK");
  assertHidden("buka www.example.com aja", "www.example.com", "LINK");
  assertHidden("(see https://example.com/a_(b))", "https://example.com/a_(b)", "LINK");
  assertHidden("deeplink intent://checkout?id=9 error", "intent://checkout?id=9", "LINK");
});

test("extra link schemes from local config", () => {
  const text = "deeplink myapp://checkout?id=9 error";
  assert.ok(redact(text).masked.includes("myapp://"), "unknown schemes aren't links by default");
  const { masked, items } = redact(text, "", { linkSchemes: ["myapp"] });
  assert.equal(masked, "deeplink {{LINK_1}} error");
  assert.equal(restore(masked, items), text);
});

test("extra hidden terms from local config", () => {
  const { masked } = redact("Project Falcon sama Acme Bank", "Acme Bank", { hiddenTerms: ["Project Falcon"] });
  assert.equal(masked, "{{TERM_1}} sama {{TERM_2}}");
});

test("same link twice uses one placeholder", () => {
  const { masked, items } = redact("https://a.com dan https://a.com lagi");
  assert.equal(items.length, 1);
  assert.equal(masked, "{{LINK_1}} dan {{LINK_1}} lagi");
});

test("emails, IPs, phone numbers", () => {
  assertHidden("email aku alex@example.co.id ya", "alex@example.co.id", "EMAIL");
  assertHidden("server nya 10.20.30.40:8080 down", "10.20.30.40:8080", "IP");
  assertHidden("wa aku 0812-3456-7890", "0812-3456-7890", "PHONE");
  assertHidden("call +62 812 3456 7890", "+62 812 3456 7890", "PHONE");
  assertHidden("ring me +1 415 555 0123", "+1 415 555 0123", "PHONE");
});

test("credentials by shape", () => {
  assertHidden(`key nya ${fakeGroq} jangan di share`, fakeGroq, "SECRET");
  assertHidden("pakai sk-ant-api03-FAKEfakeFAKEfake1234567890abcd", "sk-ant-api03-FAKEfakeFAKEfake1234567890abcd", "SECRET");
  assertHidden("aws AKIAIOSFODNN7EXAMPLE ya", "AKIAIOSFODNN7EXAMPLE", "SECRET");
  assertHidden("token ghp_FAKE1234567890abcdefghijklmnopqrstu", "ghp_FAKE1234567890abcdefghijklmnopqrstu");
  assertHidden("slack xoxb-1234567890-FAKEfakeFAKE", "xoxb-1234567890-FAKEfakeFAKE", "SECRET");
  const jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.FAKEsignature_abc123";
  assertHidden(`jwt nya ${jwt}`, jwt, "SECRET");
  assertHidden("header Bearer abcDEF1234567890ghiJKL", "Bearer abcDEF1234567890ghiJKL", "SECRET");
  const pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIFAKE\n-----END RSA PRIVATE KEY-----";
  assertHidden(`ini key nya\n${pem}`, pem, "SECRET");
});

test("labelled secrets: only the value is hidden", () => {
  const m = assertHidden("password: hunter2 jangan lupa", "hunter2", "SECRET");
  assert.match(m, /^password: \{\{SECRET_1\}\}/);
  assertHidden("passwordnya S3cr3t!2026 ya", "S3cr3t!2026", "SECRET");
  assertHidden("otp nya 482913", "482913", "SECRET");
  assertHidden("pin adalah 1234", "1234", "SECRET");
  assertHidden("api_key=abc123", "abc123", "SECRET");
});

test("random-looking keys without a known prefix", () => {
  assertHidden("pakai 9f8e7d6c5b4a39281706f5e4d3c2b1a0 buat staging", "9f8e7d6c5b4a39281706f5e4d3c2b1a0", "SECRET");
});

test("cards (Luhn), NIK and long IDs", () => {
  assertHidden("kartu 4111 1111 1111 1111 expired", "4111 1111 1111 1111", "CARD");
  assertHidden("NIK 3171234567890001 salah", "3171234567890001"); // CARD or NUMBER: hidden either way
  assertHidden("NIK 3171234567890002 salah", "3171234567890002");
  assertHidden("password nya rahasia123", "rahasia123", "SECRET");
  assertHidden("order 12345678901 stuck", "12345678901", "NUMBER");
});

test("code is never sent", () => {
  assertHidden("kenapa `/v2/bills` empty?", "`/v2/bills`", "CODE");
  const block = "```\nval key = \"x\"\n```";
  assertHidden(`coba ini\n${block}\ngimana?`, block, "CODE");
  assertHidden("template {{user_name}} nya kosong", "{{user_name}}", "CODE");
});

test("hidden terms from settings", () => {
  assertHidden("Project Falcon delay ke Q3", "Project Falcon", "TERM", "Project Falcon, Acme Bank");
  assertHidden("meeting sama acme bank besok", "acme bank", "TERM", "Project Falcon, Acme Bank");
  assertKept("falconry is a hobby", "falconry"); // whole words only
});

test("normal chat text is still sent for refining", () => {
  for (const [text, kept] of [
    ["REP-6789 udah fixed di staging", "REP-6789"],
    ["cc @alex tolong cek", "@alex"],
    ["#mobile-squad meeting jam 3", "#mobile-squad"],
    ["limit nya Rp 1.500.000 ya", "Rp 1.500.000"],
    ["versi 2.4.0 udah rilis", "2.4.0"],
    ["the token is expired", "the token is"],
    ["Node.js sama README.md", "Node.js sama README.md"],
  ]) {
    assertKept(text, kept);
  }
});

test("nothing left to refine", () => {
  assert.equal(hasRefinableText(redact("https://a.com").masked), false);
  assert.equal(hasRefinableText(redact("https://a.com cek").masked), true);
});

test("restore is strict about placeholders", () => {
  const { items } = redact("cek https://a.com sama https://b.com");
  assert.equal(restore("Check {{LINK_1}} and {{LINK_2}}.", items), "Check https://a.com and https://b.com.");
  assert.equal(restore("Check {{ link_1 }} and {{LINK 2}}.", items), "Check https://a.com and https://b.com.");
  assert.throws(() => restore("Check {{LINK_1}}.", items), PlaceholderError); // dropped
  assert.throws(() => restore("Check {{LINK_1}} {{LINK_2}} {{LINK_3}}", items), PlaceholderError); // invented
});

test("restores nested masks", () => {
  const text = "token: `abc`";
  const { masked, items } = redact(text);
  assert.ok(!masked.includes("abc"));
  assert.equal(restore(masked, items), text);
});
