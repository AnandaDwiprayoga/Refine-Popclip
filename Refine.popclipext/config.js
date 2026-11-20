// Loads your personal settings from local.config.js, if it exists.
// That file is gitignored, so your style profile, real messages, company link
// schemes and private words never end up in the public repo.
// Start from local.config.example.js: copy it to local.config.js and edit.

function loadLocalConfig() {
  try {
    return require("./local.config.js") || {};
  } catch (error) {
    // Node: no local file, use the defaults.
    if (error && error.code === "MODULE_NOT_FOUND") return {};
    // A typo in local.config.js should be visible, not silently ignored.
    // (install.sh also checks the file with Node before installing.)
    if (error instanceof SyntaxError || typeof process !== "undefined") throw error;
    // PopClip: no local file, use the defaults.
    return {};
  }
}

const LOCAL = loadLocalConfig();

module.exports = { LOCAL };
