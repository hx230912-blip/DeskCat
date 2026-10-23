#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is not installed. Install Xcode Command Line Tools first."
  exit 1
fi

echo "Building DeskCat for this Mac..."
swift build -c release

BINARY="$ROOT/.build/release/DeskCat"
if [[ ! -f "$BINARY" ]]; then
  echo "Build did not produce DeskCat executable."
  exit 1
fi

DEST="$ROOT/dist/DeskCat.app"
STAGING="$ROOT/dist/.DeskCat-staging.app"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BINARY" "$STAGING/Contents/MacOS/DeskCat"
chmod 755 "$STAGING/Contents/MacOS/DeskCat"

cat > "$STAGING/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DeskCat</string>
  <key>CFBundleDisplayName</key><string>DeskCat</string>
  <key>CFBundleIdentifier</key><string>io.github.hx230912-blip.DeskCat</string>
  <key>CFBundleExecutable</key><string>DeskCat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Optional local ad-hoc signature. Not a notarized distribution signature.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$STAGING" || echo "Warning: ad-hoc signing skipped."
fi

if [[ -d "$DEST" ]]; then
  mv "$DEST" "$ROOT/dist/DeskCat-previous.app"
  rm -rf "$ROOT/dist/DeskCat-previous.app"
fi
mv "$STAGING" "$DEST"

echo ""
echo "DeskCat.app is ready:"
echo "$DEST"
echo "Double-click it in Finder to launch."
open -R "$DEST"
