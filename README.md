# Refine ✨

**Turn rough drafts into natural English, right where you type, on macOS.**

Refine is a [PopClip](https://www.popclip.app) extension. Select text in any Mac app (Slack, Mail, Jira, a browser text box…), click a button in the PopClip bar, and the selection is replaced with a clean English rewrite in *your* own voice.

It was built for non-native speakers who write in a mix of languages. Drafts in Bahasa Indonesia, Indonesian chat slang (`td`, `udh`, `blm`, `gpp`…) and broken English all come out as natural, friendly-professional English. It runs on [Groq](https://groq.com)'s free tier, so a rewrite usually takes under a second and costs nothing.

```
you select:   bro sorry telat, td aku cek api nya masih error 500, mungkin dr BE side ya? cc @alex
you get:      Sorry for the late reply! I just checked and the API is still returning a 500.
              Could it be on the BE side? cc @alex
```

For video calls there's also **RefineBar**, a small menu bar app: speak or type your question in broken English or Bahasa, and a clean English version appears in a second or two for you to read aloud. [More below](#refinebar-say-it-in-english-in-meetings).

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
- **Add context with `/*`:** anything after `/*` is a note for the model only, in Bahasa, English or a mix. It helps Refine get tense, timing, who's who or the audience right, and it's left out of the result. [Details below](#add-context-with-).
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

### Add context with `/*`

Bahasa often leaves out things English needs, like tense. Add a note after `/*` to tell Refine what you mean. The note can be Bahasa, English or a mix, and it never ends up in the result:

| You select | Refine pastes |
|---|---|
| `saya mandi di seberang /*i already finish mandi` | I took a bath across the street. |
| `saya mandi di seberang /*nanti sore` | I'll take a bath across the street. |
| `dia udah approve PR nya /*dia = Budi, BE lead` | Budi already approved the PR. |

- The note runs to the end of the selection. To put one in the middle, close it with `*/`: `aku deploy /*besok pagi*/ terus kabarin QA ya`.
- `/*` only starts a note at the beginning or after a space, so paths like `src/*.js` stay part of the text. It works in every rewrite style and in RefineBar, but not in 🇮🇩 Translate.
- Notes go through the [privacy guard](#privacy-guard) like the rest of the text.

### 6. Make it sound like you (recommended)

Out of the box, Refine uses a generic friendly-professional voice. To teach it *your* style, create a personal config file:

```bash
cp Refine.popclipext/local.config.example.js Refine.popclipext/local.config.js
```

Edit `local.config.js`, then run `./install.sh` again. This file is **gitignored**, so your real messages and private words never end up in a commit. See [Personal configuration](#personal-configuration).

## RefineBar: say it in English in meetings

Typing a question, translating it, then reading it aloud in Google Meet is slow. RefineBar is a menu bar app that makes it one step:

1. Click the speech bubble icon in the menu bar. A small panel opens.
2. **Speak:** click 🎙 (or press ⌘R), say it however it comes out ("aku mau tanya, API nya udah di-deploy ke staging belum ya?"), then click ■ Stop.
   **Or type:** write in the text box. When you stop typing for 1.5 seconds it refines automatically. Keep editing and it refines again after each pause.
3. The English version appears in large text in about 1–2 seconds:
   *"Quick question: has the API been deployed to staging yet?"*
4. Unmute in Meet (hold Space for push-to-talk) and read it aloud in your own voice.

What you said also goes into the text box, so if Whisper misheard a word, fix it there and it refines again. Add a [`/*` note](#add-context-with-) for context only Refine sees, like `aku review PR nya /*besok pagi`. Pick a style under the text box: **Spoken** (the default, made to be said aloud: short, easy-to-pronounce sentences), My style, Polite or Short. ⇧⌘C copies the result.

The panel stays open when you click into Meet, floats above other windows (full-screen Meet too) and can be dragged next to your camera. Press Esc or click the icon to hide it. Hiding it clears the text and the result (and discards a recording in progress), so it opens empty next time. Right-click the icon to quit.

### Install RefineBar

Needs Xcode or the Xcode Command Line Tools (for `swift`), on macOS 13 or later.

```bash
./RefineBar/build.sh --install
```

This builds `RefineBar.app`, copies it to `~/Applications` and opens it. Then:

1. Paste your Groq API key in the panel's settings (⚙). RefineBar keeps its own copy in your keychain, because PopClip's copy is private to PopClip.
2. Allow microphone access the first time you press 🎙.
3. **Launch at login** turns on automatically, so the icon is back after a restart. Turn it off in the panel's settings, or in System Settings → General → Login Items.

RefineBar uses the same `prompt.js`, `redact.js` and your `local.config.js` as the PopClip extension, so the style profile and privacy guard are shared. They're copied into the app when you build it, so run `./RefineBar/build.sh --install` again after changing them.

### RefineBar privacy

- **Your voice:** audio is recorded into memory only and never saved to disk. It's sent to Groq's `whisper-large-v3-turbo` speech-to-text model as-is, because sound can't be redacted. Groq's data controls apply (see [Security notes](#security-notes)). The microphone is only on between 🎙 and ■ Stop, up to 2 minutes.
- **The text:** the transcript, or what you type, goes through the same [privacy guard](#privacy-guard) as the PopClip buttons before the rewrite. RefineBar's "Never send these words" setting works like PopClip's.

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
- **RefineBar audio:** your voice can't be masked, so recordings go to Groq Whisper as-is. They're held in memory only, never written to disk. See [RefineBar privacy](#refinebar-privacy).
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
├── RefineCore/                  # shared Swift package (macOS + iOS): JS bridge, Groq client, refine/translate flow
│   └── Tests/                   # no-network tests against the real prompt.js / redact.js
├── RefineBar/                   # menu bar app for meetings (Swift, macOS 13+)
│   ├── Sources/RefineBar/       # panel UI, in-memory recorder, keychain, CLI
│   ├── Info.plist               # menu-bar-only app, microphone permission text
│   └── build.sh                 # builds RefineBar.app, bundles the extension's JS, --install
├── test/
│   ├── redact.test.mjs          # privacy guard unit tests (no network)
│   ├── context.test.mjs         # /* writer's note tests (no network)
│   ├── run.mjs                  # prompt tuning harness (calls Groq)
│   └── samples.txt              # example drafts for run.mjs
└── install.sh                   # validates and installs the extension into PopClip
```

### Run the tests

The privacy guard tests need no API key and no network:

```bash
node --test test/
swift test --package-path RefineCore   # the Swift bridge, against the same JS
```

`RefineCore` is also used by **Refine Keyboard**, the iPhone version, which lives in its own repo and includes this one as a git submodule.

### Tune the prompt without PopClip

`test/run.mjs` uses the exact same `prompt.js` and `redact.js` as the extension, and checks every output for lost mentions, links, code, ticket keys, preambles and em dashes.

```bash
export GROQ_API_KEY=gsk_...
node test/run.mjs                    # every sample × every style
node test/run.mjs --models all       # compare all models side by side
node test/run.mjs --styles me,fix    # just some styles
node test/run.mjs --styles spoken    # RefineBar's spoken style
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

RefineBar runs the same `prompt.js` and `redact.js` inside JavaScriptCore (built into macOS), so the prompt and privacy rules live in one place. Its Swift side records the microphone into an in-memory WAV, sends it to `POST /openai/v1/audio/transcriptions`, then sends the masked transcript through the same chat request and fallback model as the extension. Test it from the terminal without the UI:

```bash
B=RefineBar/build/RefineBar.app/Contents/MacOS/RefineBar
$B --dry-run "td aku cek api nya masih error"         # privacy guard + request, no network
$B --refine "td aku cek api nya masih error"          # full rewrite (Spoken style)
$B --refine "..." --style polite
$B --transcribe speech.wav                            # Whisper, then the rewrite
$B --snapshot panel.png                               # render the panel to a PNG
```

The key comes from `GROQ_API_KEY`, or from the keychain entry the app saved.

## Troubleshooting

| Problem | Fix |
|---|---|
| The Refine buttons don't show up | They only appear when the selected text is in an editable field. Check that the extension is enabled in PopClip's Extensions list. |
| PopClip opens the extension settings when I click | The API key is missing or was rejected. Paste a valid key from console.groq.com. |
| I get ✗ | The request failed on both models (network, rate limit, or a broken placeholder). Open Console.app and filter on "Refine" to see why. |
| "Nothing to refine" | After hiding links, code and secrets, there was no text left to rewrite. |
| My `local.config.js` changes aren't used | Run `./install.sh` again. PopClip uses its own copy of the extension. |
| RefineBar says microphone access is off | System Settings → Privacy & Security → Microphone → turn on RefineBar. A rebuild changes the app's ad-hoc signature, so macOS may ask again (and may ask once to let RefineBar read its keychain key). |
| RefineBar: "Didn't hear anything" | The recording was silent. Check the input device in System Settings → Sound → Input. |
| RefineBar doesn't come back after a restart | Settings (⚙) → Launch at login, or System Settings → General → Login Items. It only works for the copy in `~/Applications`, installed with `./RefineBar/build.sh --install`. |
| PopClip's bar overlaps an app's own toolbar | Hide PopClip's built-in Cut/Copy/Paste buttons so the bar stays small, or add the app to PopClip's excluded apps and use PopClip's keyboard shortcut there. |

## Contributing

Issues and pull requests are welcome. Before opening a PR:

1. Run `node --test test/` and make sure everything passes.
2. If you change the privacy guard, add a test to `test/redact.test.mjs`. Use fake values only, never real keys or personal data.
3. Keep personal settings in `local.config.js`, not in the committed files.

## License

[MIT](LICENSE) © AnandaDwiprayoga
