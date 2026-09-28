#!/usr/bin/env bash
# Shared app-bundle builder for BetterModifiers.
# Source this file, then call: build_bettermodifiers_bundle
#
# Required env (set by caller):
#   REPO_ROOT, APP_BUILD_DIR, APP_NAME, BUNDLE_ID
# Optional:
#   BUILD_MODE (default: release)
#   VERSION (default: 1.0.0)
#   BUILD_NUMBER (default: 100)
#   SKIP_CLEAN (default: 0) — set to 1 to skip `swift package clean`

build_bettermodifiers_bundle() {
  local PACKAGE_NAME="bettermodifiers"
  local BUILD_MODE="${BUILD_MODE:-release}"
  local VERSION="${VERSION:-1.0.0}"
  local BUILD_NUMBER="${BUILD_NUMBER:-100}"
  local ICON_SOURCE="$REPO_ROOT/assets/app-icon.svg"
  local ICONSET_DIR="$APP_BUILD_DIR/AppIcon.iconset"
  local ICON_ICNS="$APP_BUILD_DIR/AppIcon.icns"
  local BUNDLE_PATH="$APP_BUILD_DIR/$APP_NAME.app"

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
  if [[ "${SKIP_CLEAN:-0}" != "1" ]]; then
    swift package clean
  fi
  swift build -c "$BUILD_MODE"

  local BIN_PATH
  BIN_PATH="$(swift build -c "$BUILD_MODE" --show-bin-path)/$PACKAGE_NAME"
  if [[ ! -x "$BIN_PATH" ]]; then
    echo "Expected built executable at: $BIN_PATH" >&2
    return 1
  fi

  echo "Creating app bundle at $BUNDLE_PATH..."
  rm -rf "$BUNDLE_PATH"
  mkdir -p "$BUNDLE_PATH/Contents/MacOS" "$BUNDLE_PATH/Contents/Resources" "$BUNDLE_PATH/Contents/Frameworks"
  ditto "$BIN_PATH" "$BUNDLE_PATH/Contents/MacOS/$APP_NAME"

  local SPARKLE_SRC
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
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
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
  <false/>
  <key>SUAllowsAutomaticUpdates</key>
  <false/>
</dict>
</plist>
EOF
}

sign_bettermodifiers_bundle() {
  local BUNDLE_PATH="$APP_BUILD_DIR/$APP_NAME.app"
  if [[ -d "$BUNDLE_PATH/Contents/Frameworks/Sparkle.framework" ]]; then
    local SPARKLE_VERSIONS="$BUNDLE_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
    for nested in \
      "$SPARKLE_VERSIONS/XPCServices/Installer.xpc" \
      "$SPARKLE_VERSIONS/XPCServices/Downloader.xpc" \
      "$SPARKLE_VERSIONS/Autoupdate" \
      "$SPARKLE_VERSIONS/Updater.app"; do
      if [[ -e "$nested" ]]; then
        codesign --force --sign - --timestamp=none --options runtime "$nested" >/dev/null 2>&1 || true
      fi
    done
    codesign --force --sign - --timestamp=none --options runtime "$BUNDLE_PATH/Contents/Frameworks/Sparkle.framework" >/dev/null 2>&1 || true
  fi
  codesign --force --sign - "$BUNDLE_PATH"
}
