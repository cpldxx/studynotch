#!/bin/bash
# Builds StudyNotch and wraps it as build/StudyNotch.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/StudyNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/StudyNotch "$APP/Contents/MacOS/StudyNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi

# A real signing identity keeps the macOS permissions (Accessibility, Screen Recording) across rebuilds.
# Without one the app is signed ad hoc and the permissions have to be granted again after a rebuild.
IDENTITY="${STUDYNOTCH_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')"
fi

signed="no"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1 &
  pid=$!
  ( sleep 30; kill "$pid" 2>/dev/null ) &
  watchdog=$!
  if wait "$pid" 2>/dev/null; then signed="identity"; fi
  kill "$watchdog" 2>/dev/null || true
fi
if [ "$signed" = "no" ]; then
  codesign --force --sign - "$APP"
  signed="ad hoc"
fi

echo "built $APP (signed: $signed)"
