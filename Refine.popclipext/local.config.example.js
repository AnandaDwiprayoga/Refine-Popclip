// Your personal Refine settings. Copy this file to local.config.js and edit it:
//
//   cp Refine.popclipext/local.config.example.js Refine.popclipext/local.config.js
//
// local.config.js is gitignored, so nothing in it is committed. It is copied into
// PopClip together with the extension when you run ./install.sh.
// Every field is optional: leave one out to use the default.

module.exports = {
  // Extra app link schemes to hide before sending, on top of the built-in ones
  // (http, https, ftp, sftp, ssh, git, s3, file, slack, intent).
  // "myapp" hides links like myapp://checkout?id=9.
  linkSchemes: ["myapp"],

  // Words that are always hidden, in addition to the "Never send these words"
  // setting in PopClip. Client names, project code names, internal hostnames...
  hiddenTerms: ["Project Falcon", "Acme Bank"],

  // Teaches the model how you write. Replaces the generic profile in prompt.js.
  // Add 10-20 real messages you sent and liked, plus 3-5 draft -> rewrite pairs.
  // Don't put secrets here: this text is sent to Groq with every request.
  styleProfile: `
Tone rules:
- Friendly-professional, like talking to a teammate you respect. Not stiff, not overly casual.
- Short, clear sentences. Get to the point quickly.
- No em dashes. Use commas, periods, or parentheses instead.

Examples of messages the writer sent and liked:
<examples>
Hey team, the fix is on staging now. Could someone give it a quick check before I merge? Thanks!
</examples>

Draft -> rewrite pairs the writer liked:
<pairs>
<pair>
<draft>sorry telat, td aku cek api nya masih error 500, mungkin dr BE side ya? cc @alex</draft>
<rewrite>Sorry for the late reply! I just checked and the API is still returning a 500. Could it be on the BE side? cc @alex</rewrite>
</pair>
</pairs>
`,
};
