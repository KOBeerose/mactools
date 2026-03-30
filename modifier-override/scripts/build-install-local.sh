#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="modifier-override"
APP_NAME="ModifierOverride"
BUILD_MODE="${BUILD_MODE:-release}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
BUNDLE_ID="${BUNDLE_ID:-dev.tahaelghabi.ModifierOverride}"

APP_BUILD_DIR="$REPO_ROOT/.build-app"
BUNDLE_PATH="$APP_BUILD_DIR/$APP_NAME.app"
DEST_PATH="$INSTALL_DIR/$APP_NAME.app"

echo "Building $PACKAGE_NAME ($BUILD_MODE)..."
swift build -c "$BUILD_MODE"

BIN_PATH="$(swift build -c "$BUILD_MODE" --show-bin-path)/$PACKAGE_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Expected built executable at:"
  echo "  $BIN_PATH"
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH/Contents/MacOS" "$BUNDLE_PATH/Contents/Resources"
ditto "$BIN_PATH" "$BUNDLE_PATH/Contents/MacOS/$APP_NAME"

cat > "$BUNDLE_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

mkdir -p "$INSTALL_DIR"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "Stopping running $APP_NAME instance..."
  pkill -x "$APP_NAME" || true
fi

echo "Installing to $DEST_PATH..."
ditto "$BUNDLE_PATH" "$DEST_PATH"

echo "Ad-hoc signing installed app..."
codesign --force --deep --sign - "$DEST_PATH"

echo "Opening installed app..."
open "$DEST_PATH"

echo
echo "Installed $APP_NAME to:"
echo "  $DEST_PATH"
