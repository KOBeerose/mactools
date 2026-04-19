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
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>100</string>
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

echo "Ad-hoc signing installed app (frameworks first, then app, no --deep)..."
# Sign each nested binary explicitly so we don't double-sign and accidentally strip the
# hardened-runtime flag that Sparkle was first signed with. --deep would re-sign Sparkle
# without --options runtime and produce a half-broken bundle.
if [[ -d "$DEST_PATH/Contents/Frameworks/Sparkle.framework" ]]; then
  SPARKLE_VERSIONS="$DEST_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
  for nested in \
    "$SPARKLE_VERSIONS/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSIONS/XPCServices/Downloader.xpc" \
    "$SPARKLE_VERSIONS/Autoupdate" \
    "$SPARKLE_VERSIONS/Updater.app"; do
    if [[ -e "$nested" ]]; then
      codesign --force --sign - --timestamp=none --options runtime "$nested" >/dev/null 2>&1 || true
    fi
  done
  codesign --force --sign - --timestamp=none --options runtime "$DEST_PATH/Contents/Frameworks/Sparkle.framework" >/dev/null 2>&1 || true
fi
codesign --force --sign - "$DEST_PATH"

# Every ad-hoc rebuild produces a new code-directory hash. macOS keys TCC entries on that
# hash, so the previously-granted Accessibility permission is silently invalidated and the
# event tap is created but receives zero events. Reset the entry so the next launch
# triggers a fresh prompt and a clean grant. This requires no admin rights when scoped to
# our own bundle id.
echo "Resetting Accessibility TCC entry for $BUNDLE_ID..."
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Opening installed app..."
open "$DEST_PATH"

cat <<EOF

Installed $APP_NAME to:
  $DEST_PATH

ONE-TIME PER REBUILD: macOS just dropped the old Accessibility grant for this bundle id.
When the app launches it should prompt you - click "Open System Settings" and toggle
$APP_NAME on. Then press Tab+1 once. The Last triggered field on the General page must
update; if it does not, look for "[BetterModifiers] first event received" with:
  log stream --predicate 'eventMessage CONTAINS "[BetterModifiers]"' --info
EOF
