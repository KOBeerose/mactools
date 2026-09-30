#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# Shared with build-snapshot-dmg.sh (Info.plist, Sparkle embed, icon, signing).
# shellcheck source=build-app-bundle.sh
source "$REPO_ROOT/scripts/build-app-bundle.sh"

export REPO_ROOT APP_BUILD_DIR APP_NAME BUNDLE_ID BUILD_MODE
build_bettermodifiers_bundle
sign_bettermodifiers_bundle

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

# Every ad-hoc rebuild produces a new code-directory hash. macOS keys TCC entries on that
# hash, so the previously-granted Accessibility permission is silently invalidated and the
# event tap is created but receives zero events. Reset the entry so the next launch
# triggers a fresh prompt and a clean grant. This requires no admin rights when scoped to
# our own bundle id.
# With the stable "KobeTools Dev" identity the grant survives rebuilds, so
# only reset it for ad-hoc builds.
if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
  echo "Resetting Accessibility TCC entry for $BUNDLE_ID..."
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

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
