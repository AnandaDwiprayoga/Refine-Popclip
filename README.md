# Refine ✨

**Turn rough drafts into natural English, right where you type, on macOS.**

Refine is a [PopClip](https://www.popclip.app) extension. Select text in any Mac app (Slack, Mail, Jira, a browser text box…), click a button in the PopClip bar, and the selection is replaced with a clean English rewrite in *your* own voice.

It was built for non-native speakers who write in a mix of languages. Drafts in Bahasa Indonesia, Indonesian chat slang (`td`, `udh`, `blm`, `gpp`…) and broken English all come out as natural, friendly-professional English. It runs on [Groq](https://groq.com)'s free tier, so a rewrite usually takes under a second and costs nothing.

```
you select:   bro sorry telat, td aku cek api nya masih error 500, mungkin dr BE side ya? cc @alex
you get:      Sorry for the late reply! I just checked and the API is still returning a 500.
              Could it be on the BE side? cc @alex
```

## Features

| Button | Style | What it does |
|---|---|---|
| ✨ | My style | Rewrites in your own voice, using your style profile |
| 🙏 | Polite | Softer and more diplomatic, without groveling |
| ✂️ | Short | As concise as possible, keeps every fact, name, number and link |
| ✅ | Fix only | Translates Bahasa and fixes grammar, keeps your wording |
| 🇮🇩 | Translate | Shows a Bahasa Indonesia translation of any selected text (English or any other language). Doesn't replace anything |

- **Click** a button to replace the selection. Press **⌘Z** to undo. Your clipboard is restored afterwards.
- **⌥-click** (Option-click) to see a preview in the PopClip bubble first. Click the preview to paste it.
- The rewrite buttons only appear in editable text fields.
- **🇮🇩 Translate** works on any selected text, including web pages, PDFs and messages from others. Short translations show in the PopClip bubble. Longer ones (over 160 characters, PopClip's bubble limit) open full screen in Large Type and are also copied to your clipboard. In an editable field you can click the bubble to paste the translation.
- Keeps `@mentions`, `#channels`, links, code, emoji, ticket keys (`REP-1234`), numbers and Slack formatting intact.
- **Privacy guard:** links, emails, API keys, passwords, phone numbers, card numbers, code and your own private words are replaced with placeholders *before* anything leaves your Mac. [More below](#privacy-guard).
- Falls back to a second model automatically if the first one fails or is rate limited.

## Requirements

- **macOS** with [PopClip](https://www.popclip.app) installed (PopClip is a paid app with a free trial).
- A free **Groq API key** from [console.groq.com](https://console.groq.com/keys).
- **[Node.js](https://nodejs.org) 18 or later**, only for `install.sh` and the test tools. The extension itself runs inside PopClip and needs nothing else.

## Setup

### 1. Install PopClip

Download PopClip from [popclip.app](https://www.popclip.app), open it, and grant it **Accessibility** permission when asked (System Settings → Privacy & Security → Accessibility).

### 2. Get a Groq API key

1. Sign up at [console.groq.com](https://console.groq.com).
2. Go to **API Keys** → **Create API Key** and copy the key (it starts with `gsk_`).
3. Optional but recommended: under **Settings → Data Controls**, turn off data retention. See [Security notes](#security-notes).

### 3. Clone and install the extension

```bash
git clone https://github.com/AnandaDwiprayoga/refine-popclip.git
cd refine-popclip
./install.sh
```

`install.sh` checks the files with Node, then opens the extension in PopClip. PopClip warns that the extension isn't signed: confirm the install dialog.

> No Node.js? You can also double-click `Refine.popclipext` in Finder to install it.

### 4. Add your API key

Open PopClip's settings → **Extensions** → **Refine**, open its options, and paste your Groq key. It's stored in your macOS keychain, not in any file.

In the same settings you can pick the [model](#models) and list words that should never be sent (see [Privacy guard](#privacy-guard)).

### 5. Try it

Type something like `td aku udh cek, tp blm fix ya` into any text field, select it, and click ✨ in the PopClip bar.

### 6. Make it sound like you (recommended)

Out of the box, Refine uses a generic friendly-professional voice. To teach it *your* style, create a personal config file:

```bash
cp Refine.popclipext/local.config.example.js Refine.popclipext/local.config.js
```

Edit `local.config.js`, then run `./install.sh` again. This file is **gitignored**, so your real messages and private words never end up in a commit. See [Personal configuration](#personal-configuration).

## Personal configuration

Everything personal lives in `Refine.popclipext/local.config.js`. Every field is optional:

```js
module.exports = {
  // Your company's app link schemes, hidden like normal links: myapp://checkout?id=9
  linkSchemes: ["myapp"],

  // Words that are always hidden (client names, project code names, hostnames…)
  hiddenTerms: ["Project Falcon", "Acme Bank"],

  // Your tone rules, 10-20 real messages you sent and liked,
  // and 3-5 "messy draft -> rewrite I liked" pairs.
  styleProfile: `
Tone rules:
- Friendly-professional, short sentences, no em dashes.
...
`,
};
```

| File | Committed? | What it's for |
|---|---|---|
| `Refine.popclipext/local.config.example.js` | Yes | Template to copy |
| `Refine.popclipext/local.config.js` | **No** (gitignored) | Your style profile, link schemes and hidden words |
| `test/samples.txt` | Yes | Generic example drafts for the test runner |
| `test/samples.local.txt` | **No** (gitignored) | Your own real drafts; used instead of `samples.txt` when present |

> The style profile is sent to Groq with every request, so don't put secrets in it.

After any change, run `./install.sh` again so PopClip picks it up.

## Privacy guard

Before anything leaves your Mac, `redact.js` replaces sensitive parts with placeholders. Groq only sees the placeholders, and the real values are put back locally before pasting.

```
you select:     cek https://grafana.internal/d/abc, token nya ghp_abc…xyz
sent to Groq:   cek {{LINK_1}}, token nya {{SECRET_1}}
Groq returns:   Please check {{LINK_1}}. The token is {{SECRET_1}}.
pasted:         Please check https://grafana.internal/d/abc. The token is ghp_abc…xyz.
```

| Always hidden | Examples |
|---|---|
| Links | `https://…`, `ssh://…`, `intent://…`, your own `linkSchemes`, bare domains like `grafana.internal/d/x`, `www.…` |
| Emails, IPs | `name@company.co.id`, `10.20.30.40:8080` |
| Credentials by shape | Anthropic, OpenAI, Groq, AWS, GitHub, GitLab, Slack, Google, Stripe, SendGrid, Atlassian, npm and Shopify tokens, JWTs, `Bearer …`, private key blocks |
| Labelled secrets | the value after `password:`, `passwordnya`, `token=`, `api_key=`, `otp`, `pin adalah`, `cvv`… |
| Random-looking keys | any 24+ character string that mixes letters and digits |
| Personal numbers | card numbers (checksum-validated), Indonesian and international phone numbers, NIK and any 10+ digit number |
| Code | `` `inline` ``, fenced code blocks, `{{templates}}` |
| Your own words | the "Never send these words" setting and `hiddenTerms` in `local.config.js` |

**Safety rules:**
- If the model drops or invents a placeholder, the reply is thrown away. Refine retries once on the fallback model, and if that also fails you get ✗. Text with a broken placeholder is never pasted.
- If nothing is left to refine after hiding (for example, you selected only a link), nothing is sent and PopClip shows "Nothing to refine".
- The selected text is never written to the logs. Console.app only shows placeholder names like `{{LINK_1}}`.

**What it can't catch:** ordinary words. A customer's name, an internal project name, or a sentence that describes something confidential is sent as normal text. Add names you never want sent to your hidden words, and don't refine text that is confidential in itself.

**Check what would be sent:** `node test/run.mjs` prints a `🔒 sent to Groq:` line for every sample that has hidden parts.

## Security notes

- **Groq data controls:** Groq keeps abuse and reliability logs for up to 30 days by default. Turn that off, or enable Zero Data Retention, under Settings → Data Controls at console.groq.com.
- **Prompt injection:** selected text could contain instructions aimed at the model. The prompt tells the model never to follow the draft, and the result only goes into your own text field, so you still see it before you press Send. Use ⌥-click to preview when the text came from someone else. The 🇮🇩 translation prompt also treats the selected text as data only, and its result is just shown to you, never pasted automatically.
- **Clipboard:** the result is pasted through the clipboard, then your previous clipboard is restored. A clipboard-history app may still record the refined text. That stays on your Mac, but it's worth knowing.
- **API key:** stored in your keychain, local to this Mac. If it was ever pasted somewhere else (a chat, a ticket, a commit), revoke it and create a new one at console.groq.com.

## Models

| Model | Typical speed | Notes |
|---|---|---|
| `qwen/qwen3.8-27b` (default) | ~0.4 s | Most natural rewrites in testing. Groq lists it as a **preview** model, so it may be removed. |
| `openai/gpt-oss-120b` (fallback) | ~0.7 s, occasional 3 s | Production model. If the default fails, Refine retries once with this model. |
| `openai/gpt-oss-20b` | ~0.5 s | Lighter. Sometimes adds things that weren't in the draft. |

Change the model in the extension's settings. Groq's model list changes over time: if a model disappears, update `MODELS` in `prompt.js` and the `values` list in `Config.json`.

Free-tier limits are per model, about 8K tokens per minute. One refine uses about 900 tokens, so roughly 8 refines a minute per model, which is plenty for chat. If the default model hits the limit, the retry on the fallback model uses that model's separate limit.

## Development

### Project structure

```
refine-popclip/
├── Refine.popclipext/           # the PopClip extension bundle
│   ├── Config.json              # name, buttons, settings (API key, model, hidden words)
│   ├── refine.js                # PopClip entry point: one action per style + 🇮🇩 translate, calls Groq
│   ├── prompt.js                # system prompts, styles, default style profile, request bodies
│   ├── redact.js                # privacy guard: mask before sending, restore after
│   ├── config.js                # loads local.config.js if it exists
│   └── local.config.example.js  # template for your personal settings
├── test/
│   ├── redact.test.mjs          # privacy guard unit tests (no network)
│   ├── run.mjs                  # prompt tuning harness (calls Groq)
│   └── samples.txt              # example drafts for run.mjs
└── install.sh                   # validates and installs the extension into PopClip
```

### Run the tests

The privacy guard tests need no API key and no network:

```bash
node --test test/
```

### Tune the prompt without PopClip

`test/run.mjs` uses the exact same `prompt.js` and `redact.js` as the extension, and checks every output for lost mentions, links, code, ticket keys, preambles and em dashes.

```bash
export GROQ_API_KEY=gsk_...
node test/run.mjs                    # every sample × every style
node test/run.mjs --models all       # compare all models side by side
node test/run.mjs --styles me,fix    # just some styles
node test/run.mjs --latency 10       # p50/p90 latency
REFINE_HIDDEN_TERMS="Project Falcon" node test/run.mjs   # test with hidden words
```

What the model sees:

- `STYLES` in `prompt.js`: the 4 button instructions.
- `SYSTEM_PROMPT` in `prompt.js`: the rewrite rules (what to preserve, no preamble, never answer the draft).
- `styleProfile` in your `local.config.js`, or the generic `DEFAULT_STYLE_PROFILE` in `prompt.js`.

When you're happy with the results, run `./install.sh` again to update PopClip.

### How it works

PopClip's bundled `axios` sends one `POST https://api.groq.com/openai/v1/chat/completions` request per click, with:

- `temperature` 0.3 and reasoning set to the minimum for each model.
- The same system prompt for every style (the style goes in the user message), so Groq can cache it.
- 🇮🇩 Translate uses its own system prompt (`TRANSLATE_SYSTEM_PROMPT` in `prompt.js`), `temperature` 0.2, and goes through the same privacy guard and fallback model. Tune it with `node test/run.mjs --styles translate`.

A few fixes are applied to every reply: em dashes become commas, non-breaking hyphens become plain hyphens, and echoed `<text>` tags are stripped.

Debug output goes to Console.app: filter on "Refine".

## Troubleshooting

| Problem | Fix |
|---|---|
| The Refine buttons don't show up | They only appear when the selected text is in an editable field. Check that the extension is enabled in PopClip's Extensions list. |
| PopClip opens the extension settings when I click | The API key is missing or was rejected. Paste a valid key from console.groq.com. |
| I get ✗ | The request failed on both models (network, rate limit, or a broken placeholder). Open Console.app and filter on "Refine" to see why. |
| "Nothing to refine" | After hiding links, code and secrets, there was no text left to rewrite. |
| My `local.config.js` changes aren't used | Run `./install.sh` again. PopClip uses its own copy of the extension. |
| PopClip's bar overlaps an app's own toolbar | Hide PopClip's built-in Cut/Copy/Paste buttons so the bar stays small, or add the app to PopClip's excluded apps and use PopClip's keyboard shortcut there. |

## Contributing

Issues and pull requests are welcome. Before opening a PR:

1. Run `node --test test/` and make sure everything passes.
2. If you change the privacy guard, add a test to `test/redact.test.mjs`. Use fake values only, never real keys or personal data.
3. Keep personal settings in `local.config.js`, not in the committed files.

## License

[MIT](LICENSE) © AnandaDwiprayoga
