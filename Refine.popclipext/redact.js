// Privacy guard: hide sensitive parts of the text BEFORE it leaves the Mac, and put
// them back AFTER the rewrite. Groq only ever sees placeholders like {{LINK_1}}.
//
//   const { masked, items } = redact(text, hiddenTerms);
//   const rewritten = await callModel(masked);
//   const result = restore(rewritten, items);   // throws if a placeholder went missing
//
// Over-masking is safe (that part just isn't refined); under-masking leaks.
// So when in doubt, the rules below mask.
//
// Your own extra link schemes and hidden words can go in local.config.js (gitignored).

const { LOCAL } = require("./config.js");

// Link schemes that are always hidden. Add your company's app schemes in local.config.js.
const DEFAULT_LINK_SCHEMES = ["https?", "ftp", "sftp", "ssh", "git", "s3", "file", "slack", "intent"];

// Rules run in order; earlier rules win because their matches become placeholders.
// A rule may name a capture group `secret` to mask only that part of the match.
function buildRules(linkSchemes = []) {
  const schemes = [...DEFAULT_LINK_SCHEMES, ...linkSchemes.map(escapeRegExp)].join("|");
  return [
    // Code first: it may contain anything, and it doesn't need rewriting.
    ["CODE", /```[\s\S]*?```/g],
    ["SECRET", /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----/g],
    // Text that already looks like our placeholders (e.g. templates) so it can't clash.
    ["CODE", /\{\{[\s\S]*?\}\}/g],
    ["CODE", /`[^`\n]+`/g],

    // Links and addresses.
    ["LINK", new RegExp(`\\b(?:${schemes}):\\/\\/[^\\s<>|"'\`]+`, "gi")],
    ["EMAIL", /\b[A-Z0-9._%+-]+@[A-Z0-9-]+(?:\.[A-Z0-9-]+)*\.[A-Z]{2,}\b/gi],
    [
      "LINK",
      /\b(?:www\.)?(?:[a-z0-9-]+\.)+(?:com|net|org|io|co|id|dev|app|ai|me|xyz|th|ph|sg|my|vn|us|uk|cloud|tech|info|biz|gov|edu|internal|local|corp)\b(?::\d+)?(?:\/[^\s<>|"'`]*)?/gi,
    ],
    ["IP", /\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{2,5})?\b/g],

    // Credentials with a recognizable shape.
    [
      "SECRET",
      new RegExp(
        [
          "\\bsk-ant-[\\w-]{20,}", // Anthropic
          "\\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}", // OpenAI
          "\\bgsk_[A-Za-z0-9]{20,}", // Groq
          "\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b", // AWS access key id
          "\\bgh[pousr]_[A-Za-z0-9]{30,}", // GitHub
          "\\bgithub_pat_\\w{30,}",
          "\\bglpat-[\\w-]{20,}", // GitLab
          "\\bxox[abposr]-[\\w-]{10,}", // Slack
          "\\bAIza[0-9A-Za-z_-]{35}", // Google API key
          "\\bya29\\.[\\w-]{20,}", // Google OAuth token
          "\\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}", // Stripe
          "\\bSG\\.[\\w-]{16,}\\.[\\w-]{16,}", // SendGrid
          "\\bATATT[\\w=-]{20,}", // Atlassian API token
          "\\bnpm_[A-Za-z0-9]{30,}",
          "\\bshp(?:at|ss|ca|pa)_[A-Fa-f0-9]{32}", // Shopify
          "\\beyJ[\\w-]{8,}\\.[\\w-]{8,}\\.[\\w-]{8,}", // JWT
          "\\b(?:Bearer|Basic|Token)\\s+[A-Za-z0-9._~+/=-]{16,}", // auth headers
        ].join("|"),
        "g",
      ),
    ],
    // "password: hunter2", "token=abc", "passwordnya xyz", "pin adalah 1234".
    [
      "SECRET",
      /\b(?:pass(?:word)?|passwd|pwd|kata ?sandi|sandi|secret|token|api[_ -]?key|access[_ -]?key|secret[_ -]?key|private[_ -]?key|client[_ -]?secret|credential|otp|pin|cvv)(?:nya\s*[:=]?\s*|\s+nya\s+|\s*[:=]\s*|\s+(?:is|adalah)\s+)(?<secret>[^\s,;]+)/gi,
    ],

    // Personal and financial numbers.
    ["CARD", /\b(?:\d[ -]?){12,18}\d\b/g], // kept only if it passes the Luhn check
    ["PHONE", /(?:\+62|\b62|\b0)8\d{1,2}[\s.-]?\d{3,4}[\s.-]?\d{3,5}\b/g], // Indonesian mobile
    ["PHONE", /\+\d{1,3}[\s.-]?\(?\d{1,4}\)?(?:[\s.-]?\d{2,4}){2,4}\b/g], // international
    ["NUMBER", /\b\d{10,}\b/g], // NIK (16 digits), account numbers, long IDs

    // Anything else that looks like a random key: 24+ chars mixing letters and digits.
    ["SECRET", /(?<![\w{])(?=[A-Za-z0-9+/=_-]*\d)(?=[A-Za-z0-9+/=_-]*[A-Za-z])[A-Za-z0-9+/=_-]{24,}/g],
  ];
}

function luhnValid(digits) {
  let sum = 0;
  for (let i = 0; i < digits.length; i++) {
    let d = Number(digits[digits.length - 1 - i]);
    if (i % 2 === 1) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 === 0;
}

// Drop trailing punctuation that belongs to the sentence, not the link.
function trimLink(value) {
  let trimmed = value.replace(/[.,;:!?]+$/, "");
  while (trimmed.endsWith(")") && (trimmed.match(/\(/g) || []).length < (trimmed.match(/\)/g) || []).length) {
    trimmed = trimmed.slice(0, -1);
  }
  return trimmed;
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Words you never want sent (client names, project code names...).
// `hiddenTerms` is a comma- or newline-separated string from the PopClip settings,
// `extraTerms` an array from local.config.js.
function termsRule(hiddenTerms, extraTerms = []) {
  const terms = [...String(hiddenTerms || "").split(/[,\n]/), ...extraTerms]
    .map((t) => String(t).trim())
    .filter(Boolean)
    .sort((a, b) => b.length - a.length);
  if (!terms.length) return null;
  return ["TERM", new RegExp(`(?<![\\p{L}\\p{N}])(?:${terms.map(escapeRegExp).join("|")})(?![\\p{L}\\p{N}])`, "giu")];
}

// `config` defaults to local.config.js; tests pass {} to get the public defaults.
function redact(text, hiddenTerms = "", config = LOCAL) {
  const items = []; // { placeholder, type, value }, in creation order
  const byValue = new Map(); // same value -> same placeholder
  const counters = {};

  const placeholderFor = (type, value) => {
    const key = `${type}\u0000${value}`;
    if (byValue.has(key)) return byValue.get(key);
    counters[type] = (counters[type] || 0) + 1;
    const placeholder = `{{${type}_${counters[type]}}}`;
    items.push({ placeholder, type, value });
    byValue.set(key, placeholder);
    return placeholder;
  };

  const rules = buildRules(config.linkSchemes || []);
  const terms = termsRule(hiddenTerms, config.hiddenTerms || []);
  if (terms) rules.splice(4, 0, terms); // after code, before links

  let masked = text;
  for (const [type, pattern] of rules) {
    masked = masked.replace(pattern, (...args) => {
      const match = args[0];
      const groups = typeof args[args.length - 1] === "object" ? args[args.length - 1] : undefined;
      if (/^\{\{[A-Z]+_\d+\}\}$/.test(match)) return match; // already a placeholder

      if (groups && groups.secret !== undefined) {
        if (/^\{\{[A-Z]+_\d+\}\}$/.test(groups.secret)) return match;
        const at = match.lastIndexOf(groups.secret);
        return match.slice(0, at) + placeholderFor(type, groups.secret) + match.slice(at + groups.secret.length);
      }
      if (type === "CARD") {
        const digits = match.replace(/\D/g, "");
        if (digits.length < 13 || !luhnValid(digits)) return match;
      }
      if (type === "LINK") {
        const link = trimLink(match);
        return placeholderFor(type, link) + match.slice(link.length);
      }
      return placeholderFor(type, match);
    });
  }
  return { masked, items };
}

// True if there is still something worth rewriting once placeholders are removed.
function hasRefinableText(masked) {
  return /\p{L}/u.test(masked.replace(/\{\{[A-Z]+_\d+\}\}/g, ""));
}

class PlaceholderError extends Error {}

// Put the hidden values back. Throws PlaceholderError if the model dropped, invented
// or mangled a placeholder, so nothing broken is ever pasted.
function restore(rewritten, items) {
  if (!items.length) return rewritten;
  // Accept small formatting slips like "{{ link_1 }}" or "{{LINK 1}}".
  let text = rewritten.replace(/\{\{\s*([A-Za-z]+)[_ ]?(\d+)\s*\}\}/g, (_, type, n) => `{{${type.toUpperCase()}_${n}}}`);

  const known = new Set(items.map((i) => i.placeholder));
  for (const found of text.match(/\{\{[A-Z]+_\d+\}\}/g) || []) {
    if (!known.has(found)) throw new PlaceholderError(`Model invented placeholder ${found}`);
  }
  // Items marked optional (e.g. only in a writer's note) may be left out of the reply.
  for (const { placeholder, optional } of items) {
    if (!optional && !text.includes(placeholder)) throw new PlaceholderError(`Model dropped placeholder ${placeholder}`);
  }
  // Restore newest first: a later mask may contain an earlier placeholder.
  for (const { placeholder, value } of [...items].reverse()) {
    text = text.split(placeholder).join(value);
  }
  return text;
}

module.exports = { redact, restore, hasRefinableText, PlaceholderError };
