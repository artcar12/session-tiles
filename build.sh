#!/bin/bash
# Builds SessionTiles.app into ./build. Usage: ./build.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")"
CONFIG="${1:-release}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SessionTiles"

APP="build/SessionTiles.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SessionTiles"
# claude-open: the same instance routing as a tile click, for the agent (and scripts) to call.
cp "$(dirname "$BIN")/ClaudeOpen" "$APP/Contents/MacOS/claude-open"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Session Tiles</string>
    <key>CFBundleDisplayName</key><string>Session Tiles</string>
    <key>CFBundleIdentifier</key><string>com.arthurcarroll.SessionTiles</string>
    <key>CFBundleExecutable</key><string>SessionTiles</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Session Tiles opens each session in the Claude instance it belongs to.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper/TCC treat it as a stable local app.
codesign --force --sign - "$APP/Contents/MacOS/claude-open" >/dev/null 2>&1 || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
