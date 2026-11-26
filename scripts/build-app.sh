#!/bin/sh
# Builds "AI Tools Manager.app" (release, Apple silicon + Intel) and copies it to ~/Applications.
#   ./scripts/build-app.sh            build + install
#   ./scripts/build-app.sh --no-install
#   ./scripts/build-app.sh --zip      build + build/AI-Tools-Manager.zip (for a GitHub release), no install
set -eu
cd "$(dirname "$0")/.."

ARCHS="--arch arm64 --arch x86_64"
swift build -c release --product AIToolsManager $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/AIToolsManager"

APP="build/AI Tools Manager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AIToolsManager"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AI Tools Manager</string>
  <key>CFBundleDisplayName</key><string>AI Tools Manager</string>
  <key>CFBundleIdentifier</key><string>local.aitoolsmanager</string>
  <key>CFBundleExecutable</key><string>AIToolsManager</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS runs it without complaining on this Mac.
codesign --force --sign - "$APP" >/dev/null
echo "Built: $APP"

if [ "${1:-}" = "--zip" ]; then
  rm -f build/AI-Tools-Manager.zip
  ditto -c -k --keepParent "$APP" build/AI-Tools-Manager.zip
  echo "Zipped: build/AI-Tools-Manager.zip"
elif [ "${1:-}" != "--no-install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/AI Tools Manager.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed: ~/Applications/AI Tools Manager.app"
fi
