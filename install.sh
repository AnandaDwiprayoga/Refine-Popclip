#!/usr/bin/env bash
# Installs (or updates) the Refine extension in PopClip.
# PopClip asks for confirmation because the extension isn't signed. Click "Install".
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d "/Applications/PopClip.app" ] && [ ! -d "$HOME/Applications/PopClip.app" ]; then
  echo "PopClip isn't installed. Get it from https://www.popclip.app first." >&2
  exit 1
fi

node -e 'JSON.parse(require("fs").readFileSync("Refine.popclipext/Config.json","utf8"))'
node -e 'require("./Refine.popclipext/prompt.js")'
if [ -f "Refine.popclipext/local.config.js" ]; then
  node -e 'require("./Refine.popclipext/local.config.js")'
  echo "Using your local.config.js."
fi

open -a "PopClip" "Refine.popclipext"
echo "Opened Refine.popclipext in PopClip. Confirm the install dialog, then add your API key in the extension's settings."
