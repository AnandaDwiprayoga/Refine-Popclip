// PopClip module: one button per style. Click = replace the selection.
// Option-click (⌥) = show a preview in the PopClip bubble; click the preview to paste.

const axios = require("axios");
const {
  API_URL,
  MODELS,
  DEFAULT_MODEL,
  FALLBACK_MODEL,
  apiHeaders,
  STYLES,
  buildRequestBody,
  extractText,
  keepSurroundingWhitespace,
} = require("./prompt.js");
const { redact, restore, hasRefinableText } = require("./redact.js");

async function refine(styleId, input, options) {
  const apiKey = (options.apiKey || "").trim();
  if (!apiKey) {
    // Opens this extension's settings so the key can be entered.
    throw new Error("settings error: Groq API key is missing");
  }
  const model = MODELS[options.model] ? options.model : DEFAULT_MODEL;

  const original = input.text;
  // Privacy guard: links, emails, keys, code, phone numbers, IDs and your hidden
  // terms are swapped for placeholders here, on the Mac. Only `masked` is sent.
  const { masked, items } = redact(original.trim(), options.hiddenTerms);
  if (!hasRefinableText(masked)) {
    popclip.showText("Nothing to refine");
    return;
  }
  if (items.length) print(`Refine: hid ${items.length} item(s): ${items.map((i) => i.placeholder).join(", ")}`);

  // Restoring inside the attempt means a reply that lost a placeholder counts as a
  // failure: it is retried on the fallback model, and never pasted broken.
  const attempt = async (m) => restore(await callGroq(masked, styleId, m, apiKey), items);

  let rewritten;
  try {
    try {
      rewritten = await attempt(model);
    } catch (error) {
      if (error.status === 401 || model === FALLBACK_MODEL) throw error;
      // Preview model removed, rate limited (limits are per model), a lost
      // placeholder, or a bad reply: try once more on the production model.
      print(`Refine: ${model} failed (${error.message}), retrying with ${FALLBACK_MODEL}`);
      rewritten = await attempt(FALLBACK_MODEL);
    }
  } catch (error) {
    // A bad key opens the extension settings; anything else shows ✗, text untouched.
    if (error.status === 401) throw new Error("settings error: Groq API key was rejected");
    throw error;
  }

  const result = keepSurroundingWhitespace(original, rewritten);

  if (popclip.modifiers.option) {
    popclip.showText(result, { preview: true });
  } else {
    await popclip.pasteText(result, { restore: true });
  }
}

async function callGroq(text, styleId, model, apiKey) {
  let response;
  try {
    response = await axios.post(API_URL, buildRequestBody(text, styleId, model), {
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
  actions: Object.keys(STYLES).map((styleId) => ({
    title: STYLES[styleId].title,
    icon: STYLES[styleId].icon,
    code: (input, options) => refine(styleId, input, options),
  })),
};
