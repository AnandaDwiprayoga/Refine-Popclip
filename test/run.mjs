// Tune the prompt without PopClip. Uses the exact same prompt.js as the extension.
//
//   export GROQ_API_KEY=gsk_...
//   node test/run.mjs                          # every sample × every style, default model
//   node test/run.mjs --styles me,fix          # only some styles
//   node test/run.mjs --styles translate       # the 🇮🇩 Bahasa Indonesia translation
//   node test/run.mjs --styles spoken          # RefineBar's spoken style (said aloud in meetings)
//   node test/run.mjs --models all             # compare every model side by side
//   node test/run.mjs --models openai/gpt-oss-20b
//   node test/run.mjs --latency 20             # latency benchmark (first sample, "me" style)
//
// Samples live in test/samples.local.txt (your own, gitignored) or else test/samples.txt,
// separated by lines containing only "---".

import { createRequire } from "node:module";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const here = dirname(fileURLToPath(import.meta.url));
const {
  API_URL,
  MODELS,
  DEFAULT_MODEL,
  apiHeaders,
  STYLES,
  SPOKEN,
  buildRequestBody,
  TRANSLATE,
  buildTranslateRequestBody,
  extractText,
} = require("../Refine.popclipext/prompt.js");
const { redact, restore } = require("../Refine.popclipext/redact.js");
const hiddenTerms = process.env.REFINE_HIDDEN_TERMS || "";

const apiKey = process.env.GROQ_API_KEY;
if (!apiKey) {
  console.error("Set GROQ_API_KEY first.");
  process.exit(1);
}

const args = process.argv.slice(2);
const argValue = (name) => {
  const i = args.indexOf(name);
  return i === -1 ? undefined : args[i + 1];
};
// "translate" and "spoken" are accepted as extra style names; they are not in the default run.
const styles = (argValue("--styles") || Object.keys(STYLES).join(",")).split(",");
const buildBody = (text, styleId, model) =>
  styleId === "translate" ? buildTranslateRequestBody(text, model) : buildRequestBody(text, styleId, model);
const iconFor = (styleId) =>
  styleId === "translate" ? TRANSLATE.icon : styleId === "spoken" ? SPOKEN.icon : (STYLES[styleId]?.icon ?? "?");
const modelsArg = argValue("--models") || DEFAULT_MODEL;
const models = modelsArg === "all" ? Object.keys(MODELS) : modelsArg.split(",");
const latencyRuns = Number(argValue("--latency") || 0);

const localSamples = join(here, "samples.local.txt");
const samplesFile = existsSync(localSamples) ? localSamples : join(here, "samples.txt");
const samples = readFileSync(samplesFile, "utf8")
  .split(/^---\s*$/m)
  .map((s) => s.replace(/^#.*$/gm, "").trim())
  .filter(Boolean);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Same privacy guard as the extension: only the masked text is sent.
async function callModel(text, styleId, model, attempt = 1) {
  const { masked, items } = redact(text, hiddenTerms);
  const started = performance.now();
  const res = await fetch(API_URL, {
    method: "POST",
    headers: apiHeaders(apiKey),
    body: JSON.stringify(buildBody(masked, styleId, model)),
  });
  const data = await res.json();
  const ms = Math.round(performance.now() - started);
  if (res.status === 429 && attempt <= 3) {
    const wait = Number(res.headers.get("retry-after") || 5) * 1000;
    console.log(`   (rate limited, waiting ${wait / 1000}s)`);
    await sleep(wait);
    return callModel(text, styleId, model, attempt + 1);
  }
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${JSON.stringify(data.error || data)}`);
  return { text: restore(extractText(data), items), ms, usage: data.usage || {} };
}

// Things that must survive the rewrite untouched.
const PROTECTED = [
  /@[\w.-]+/g, // @mentions
  /(?<![\w/])#[\w-]+/g, // #channels
  /https?:\/\/\S+/g, // URLs
  /`[^`]+`/g, // inline code
  /\b[A-Z][A-Z0-9]+-\d+\b/g, // ticket keys
  /:[a-z0-9_+-]+:/g, // emoji shortcodes
];
const PREAMBLE = /^(here('s| is)|sure|certainly|rewritten|revised|berikut|terjemahan|"|')/i;

function check(input, output) {
  const problems = [];
  for (const pattern of PROTECTED) {
    for (const token of input.match(pattern) || []) {
      if (!output.includes(token)) problems.push(`lost "${token}"`);
    }
  }
  if (PREAMBLE.test(output)) problems.push("starts with preamble/quote");
  if (/—/.test(output)) problems.push("contains em dash");
  if (/<\/?(text|style)>/i.test(output)) problems.push("echoed tags");
  return problems;
}

function percentile(values, p) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))];
}

const short = (model) => model.split("/").pop();

if (latencyRuns > 0) {
  for (const model of models) {
    const times = [];
    for (let i = 0; i < latencyRuns; i++) {
      const { ms, usage } = await callModel(samples[0], "me", model);
      times.push(ms);
      const cached = usage.prompt_tokens_details?.cached_tokens ?? 0;
      console.log(`${short(model)} run ${i + 1}: ${ms} ms  cached_tokens=${cached}`);
    }
    console.log(`${short(model)}: p50 ${percentile(times, 50)} ms · p90 ${percentile(times, 90)} ms\n`);
  }
  process.exit(0);
}

let failures = 0;
for (const [i, sample] of samples.entries()) {
  console.log(`\n━━━ Sample ${i + 1} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(sample);
  const { masked, items } = redact(sample, hiddenTerms);
  if (items.length) console.log(`\n🔒 sent to Groq:\n${masked}`);
  for (const styleId of styles) {
    for (const model of models) {
      const label = `${iconFor(styleId)} ${styleId}${models.length > 1 ? ` · ${short(model)}` : ""}`;
      try {
        const { text, ms } = await callModel(sample, styleId, model);
        const problems = check(sample, text);
        if (problems.length) failures++;
        console.log(`\n${label}  (${ms} ms)${problems.length ? `  ⚠️  ${problems.join(", ")}` : ""}`);
        console.log(text);
      } catch (error) {
        failures++;
        console.log(`\n${label}  ❌ ${error.message}`);
      }
    }
  }
}
console.log(`\n${failures === 0 ? "✅ All checks passed" : `⚠️  ${failures} output(s) need a look`}`);
