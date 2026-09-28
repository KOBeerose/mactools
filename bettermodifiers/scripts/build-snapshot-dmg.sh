#!/usr/bin/env bash
# Build a frozen, timestamped BetterModifiers installer (.dmg).
#
# Each run writes a NEW file — nothing is overwritten:
#   releases/BetterModifiers-<version>-snapshot-<YYYYMMDD-HHMMSS>.dmg
#
# The app inside uses a unique bundle id and display name so:
#   - It can live beside ~/Applications/BetterModifiers.app (dev builds).
#   - Future ./scripts/build-install-local.sh runs do not replace this snapshot.
#
# Usage:
#   ./scripts/build-snapshot-dmg.sh
#   open releases/   # double-click the newest .dmg, drag app to Applications
#
# Options (env):
#   SKIP_CLEAN=1          Skip swift package clean (default: 1)
#   OPEN_DMG=1            Open the finished .dmg in Finder (default: 1)
#   VERSION=1.0.0         Marketing version embedded in Info.plist
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SNAPSHOT_STAMP="$(date +%Y%m%d-%H%M%S)"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$SNAPSHOT_STAMP}"
APP_NAME="BetterModifiers-${VERSION}-snapshot-${SNAPSHOT_STAMP}"
BUNDLE_ID="dev.tahaelghabi.BetterModifiers.snapshot.${SNAPSHOT_STAMP}"
BUILD_MODE="${BUILD_MODE:-release}"
SKIP_CLEAN="${SKIP_CLEAN:-1}"
OPEN_DMG="${OPEN_DMG:-1}"

RELEASES_DIR="$REPO_ROOT/releases"
APP_BUILD_DIR="$REPO_ROOT/.build-snapshot/$SNAPSHOT_STAMP"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="$RELEASES_DIR/$DMG_NAME"
STAGING_DIR="$APP_BUILD_DIR/dmg-staging"
VOLUME_NAME="BetterModifiers Snapshot"

mkdir -p "$RELEASES_DIR" "$APP_BUILD_DIR"

if [[ -e "$DMG_PATH" ]]; then
  echo "Refusing to overwrite existing snapshot: $DMG_PATH" >&2
  exit 1
fi

# shellcheck source=build-app-bundle.sh
source "$REPO_ROOT/scripts/build-app-bundle.sh"

export REPO_ROOT APP_BUILD_DIR APP_NAME BUNDLE_ID BUILD_MODE VERSION BUILD_NUMBER SKIP_CLEAN
build_bettermodifiers_bundle
sign_bettermodifiers_bundle

BUNDLE_PATH="$APP_BUILD_DIR/$APP_NAME.app"

echo "Assembling drag-to-Applications disk image..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$BUNDLE_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

# README dropped into the DMG so the snapshot is self-describing years later.
cat > "$STAGING_DIR/README.txt" <<EOF
BetterModifiers — frozen snapshot
=================================

Version:  $VERSION
Build:    $BUILD_NUMBER
Created:  $SNAPSHOT_STAMP
Bundle:   $BUNDLE_ID

Install:
  1. Drag "$APP_NAME.app" onto the Applications folder alias.
  2. Open the app from Applications.
  3. Grant Accessibility in System Settings (required for remaps).

This snapshot is independent of day-to-day dev installs (BetterModifiers.app).
Re-running build-install-local.sh will NOT replace this app.

Sparkle auto-update is OFF in snapshot builds.
EOF

echo "Creating $DMG_PATH ..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

# Sidecar manifest (also never overwritten — unique stamp in filename).
MANIFEST_PATH="$RELEASES_DIR/${APP_NAME}.manifest.txt"
cat > "$MANIFEST_PATH" <<EOF
dmg=$DMG_PATH
app=$APP_NAME.app
bundle_id=$BUNDLE_ID
version=$VERSION
build=$BUILD_NUMBER
created=$SNAPSHOT_STAMP
EOF

echo ""
echo "Snapshot installer ready:"
echo "  $DMG_PATH"
echo ""
echo "Installed app name (unique, won't be overwritten by dev builds):"
echo "  $APP_NAME.app"
echo ""
echo "To install: double-click the .dmg, drag the app to Applications."

if [[ "$OPEN_DMG" == "1" ]]; then
  open "$DMG_PATH"
fi
