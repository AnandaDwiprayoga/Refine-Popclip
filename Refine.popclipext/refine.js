// PopClip module.
// Style buttons (editable fields only): click = replace the selection.
//   Option-click (⌥) = show a preview in the PopClip bubble; click the preview to paste.
// 🇮🇩 button (any selection): shows a Bahasa Indonesia translation, never replaces.

const axios = require("axios");
const {
  API_URL,
  MODELS,
  DEFAULT_MODEL,
  FALLBACK_MODEL,
  apiHeaders,
  STYLES,
  buildRequestBody,
  TRANSLATE,
  buildTranslateRequestBody,
  extractText,
  keepSurroundingWhitespace,
} = require("./prompt.js");
const { redact, restore, hasRefinableText } = require("./redact.js");

// PopClip's compact bubble truncates text longer than this.
const BUBBLE_MAX_CHARS = 160;

// Shared by every button: key check, privacy guard, request, fallback model.
// `buildBody(maskedText, model)` builds the Groq request. Returns the model's reply
// with hidden items put back, or null when there is nothing worth sending.
async function runWithGuard(input, options, buildBody) {
  const apiKey = (options.apiKey || "").trim();
  if (!apiKey) {
    // Opens this extension's settings so the key can be entered.
    throw new Error("settings error: Groq API key is missing");
  }
  const model = MODELS[options.model] ? options.model : DEFAULT_MODEL;

  // Privacy guard: links, emails, keys, code, phone numbers, IDs and your hidden
  // terms are swapped for placeholders here, on the Mac. Only `masked` is sent.
  const { masked, items } = redact(input.text.trim(), options.hiddenTerms);
  if (!hasRefinableText(masked)) return null;
  if (items.length) print(`Refine: hid ${items.length} item(s): ${items.map((i) => i.placeholder).join(", ")}`);

  // Restoring inside the attempt means a reply that lost a placeholder counts as a
  // failure: it is retried on the fallback model, and never shown or pasted broken.
  const attempt = async (m) => restore(await callGroq(buildBody(masked, m), m, apiKey), items);

  try {
    try {
      return await attempt(model);
    } catch (error) {
      if (error.status === 401 || model === FALLBACK_MODEL) throw error;
      // Preview model removed, rate limited (limits are per model), a lost
      // placeholder, or a bad reply: try once more on the production model.
      print(`Refine: ${model} failed (${error.message}), retrying with ${FALLBACK_MODEL}`);
      return await attempt(FALLBACK_MODEL);
    }
  } catch (error) {
    // A bad key opens the extension settings; anything else shows ✗, text untouched.
    if (error.status === 401) throw new Error("settings error: Groq API key was rejected");
    throw error;
  }
}

async function refine(styleId, input, options) {
  const rewritten = await runWithGuard(input, options, (text, model) => buildRequestBody(text, styleId, model));
  if (rewritten === null) {
    popclip.showText("Nothing to refine");
    return;
  }

  const result = keepSurroundingWhitespace(input.text, rewritten);

  if (popclip.modifiers.option) {
    popclip.showText(result, { preview: true });
  } else {
    await popclip.pasteText(result, { restore: true });
  }
}

async function translate(input, options) {
  const translated = await runWithGuard(input, options, buildTranslateRequestBody);
  if (translated === null) {
    popclip.showText("Nothing to translate");
    return;
  }

  if (translated.length <= BUBBLE_MAX_CHARS) {
    // In an editable field the bubble is clickable and pastes the translation.
    popclip.showText(translated, { preview: true });
  } else {
    // Too long for the bubble: copy the full text, then show it full screen.
    popclip.copyText(translated);
    popclip.showText(translated, { style: "large" });
  }
}

async function callGroq(body, model, apiKey) {
  let response;
  try {
    response = await axios.post(API_URL, body, {
      headers: apiHeaders(apiKey),
      timeout: 15000,
    });
  } catch (error) {
    const status = error.response && error.response.status;
    const detail = error.response && JSON.stringify(error.response.data);
    print(`Refine: ${model} request failed (status ${status}): ${detail || error.message}`);
    const wrapped = new Error(`Groq request failed (${status || error.message})`);
    wrapped.status = status;
    throw wrapped;
  }
  return extractText(response.data);
}

module.exports = {
  actions: [
    ...Object.keys(STYLES).map((styleId) => ({
      title: STYLES[styleId].title,
      icon: STYLES[styleId].icon,
      // Rewrites replace the selection, so they only appear where you can paste.
      requirements: ["text", "paste"],
      code: (input, options) => refine(styleId, input, options),
    })),
    {
      title: TRANSLATE.title,
      icon: TRANSLATE.icon,
      // Reading aid: appears on any selected text, editable or not.
      requirements: ["text"],
      code: (input, options) => translate(input, options),
    },
  ],
};
