#!/usr/bin/env bash
# Builds RefineBar.app, the menu bar helper.
#
#   ./RefineBar/build.sh             build into RefineBar/build/RefineBar.app
#   ./RefineBar/build.sh --install   also copy it to ~/Applications and open it
#
# The extension's JS (prompt.js, redact.js, config.js and your gitignored
# local.config.js) is copied into the app, so re-run this after editing them.
set -euo pipefail
cd "$(dirname "$0")"

EXT="../Refine.popclipext"
APP="build/RefineBar.app"
INSTALL_DIR="$HOME/Applications"

if command -v node >/dev/null; then
  node -e 'require("../Refine.popclipext/prompt.js")'
  [ -f "$EXT/local.config.js" ] && node -e 'require("../Refine.popclipext/local.config.js")'
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/RefineBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/js"
cp "$BIN" "$APP/Contents/MacOS/RefineBar"
cp Info.plist "$APP/Contents/Info.plist"
cp "$EXT/config.js" "$EXT/prompt.js" "$EXT/redact.js" "$APP/Contents/Resources/js/"
if [ -f "$EXT/local.config.js" ]; then
  cp "$EXT/local.config.js" "$APP/Contents/Resources/js/"
  echo "Using your local.config.js."
fi

# Ad-hoc signature: enough to run locally and to ask for microphone access.
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x RefineBar 2>/dev/null || true
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/RefineBar.app"
  ditto "$APP" "$INSTALL_DIR/RefineBar.app"
  open "$INSTALL_DIR/RefineBar.app"
  echo "Installed to $INSTALL_DIR/RefineBar.app. Look for the speech bubble icon in the menu bar."
fi
