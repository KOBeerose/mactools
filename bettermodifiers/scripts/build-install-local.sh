#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="bettermodifiers"
APP_NAME="BetterModifiers"
BUILD_MODE="${BUILD_MODE:-release}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
BUNDLE_ID="${BUNDLE_ID:-dev.tahaelghabi.BetterModifiers}"

LEGACY_APP_PATHS=(
  "$INSTALL_DIR/LayerKey.app"
  "$INSTALL_DIR/ModifierOverride.app"
  "$INSTALL_DIR/Better Modifiers.app"
)

APP_BUILD_DIR="$REPO_ROOT/.build-app"
BUNDLE_PATH="$APP_BUILD_DIR/$APP_NAME.app"
DEST_PATH="$INSTALL_DIR/$APP_NAME.app"
ICON_SOURCE="$REPO_ROOT/assets/app-icon.svg"
ICONSET_DIR="$APP_BUILD_DIR/AppIcon.iconset"
ICON_ICNS="$APP_BUILD_DIR/AppIcon.icns"

generate_app_icon() {
  local master_png="$APP_BUILD_DIR/app-icon-master.png"

  rm -rf "$ICONSET_DIR" "$ICON_ICNS" "$master_png"
  mkdir -p "$ICONSET_DIR"

  sips -s format png "$ICON_SOURCE" --out "$master_png" >/dev/null

  for size in 16 32 128 256 512; do
    local retina_size=$((size * 2))
    sips -z "$size" "$size" "$master_png" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    sips -z "$retina_size" "$retina_size" "$master_png" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
}

echo "Building $PACKAGE_NAME ($BUILD_MODE)..."
swift package clean
swift build -c "$BUILD_MODE"

BIN_PATH="$(swift build -c "$BUILD_MODE" --show-bin-path)/$PACKAGE_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Expected built executable at:"
  echo "  $BIN_PATH"
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH/Contents/MacOS" "$BUNDLE_PATH/Contents/Resources" "$BUNDLE_PATH/Contents/Frameworks"
ditto "$BIN_PATH" "$BUNDLE_PATH/Contents/MacOS/$APP_NAME"

SPARKLE_SRC="$(swift build -c "$BUILD_MODE" --show-bin-path)/Sparkle.framework"
if [[ -d "$SPARKLE_SRC" ]]; then
  echo "Embedding Sparkle.framework..."
  ditto "$SPARKLE_SRC" "$BUNDLE_PATH/Contents/Frameworks/Sparkle.framework"
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$BUNDLE_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || true

if [[ -f "$ICON_SOURCE" ]]; then
  echo "Generating app icon..."
  generate_app_icon
  ditto "$ICON_ICNS" "$BUNDLE_PATH/Contents/Resources/AppIcon.icns"
fi

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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
  <key>SUFeedURL</key>
  <string>https://kobeerose.github.io/mactools/bettermodifiers/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>REPLACE_ME_WITH_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>SUAllowsAutomaticUpdates</key>
  <true/>
</dict>
</plist>
EOF

mkdir -p "$INSTALL_DIR"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "Stopping running $APP_NAME instance..."
  pkill -x "$APP_NAME" || true
fi

for legacy in "${LEGACY_APP_PATHS[@]}"; do
  if [[ -d "$legacy" ]]; then
    echo "Removing legacy app at $legacy..."
    rm -rf "$legacy"
  fi
done

for legacy_proc in "LayerKey" "Better Modifiers"; do
  if pgrep -x "$legacy_proc" >/dev/null 2>&1; then
    echo "Stopping legacy $legacy_proc instance..."
    pkill -x "$legacy_proc" || true
  fi
done

echo "Installing to $DEST_PATH..."
ditto "$BUNDLE_PATH" "$DEST_PATH"

echo "Ad-hoc signing installed app (frameworks first)..."
if [[ -d "$DEST_PATH/Contents/Frameworks/Sparkle.framework" ]]; then
  codesign --force --sign - --timestamp=none --options runtime --deep "$DEST_PATH/Contents/Frameworks/Sparkle.framework" || true
fi
codesign --force --deep --sign - "$DEST_PATH"

echo "Opening installed app..."
open "$DEST_PATH"

echo
echo "Installed $APP_NAME to:"
echo "  $DEST_PATH"
