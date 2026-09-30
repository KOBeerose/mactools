#!/usr/bin/env bash
# Restore mactools apps' settings and macOS keyboard shortcuts from the private
# app-settings repo. Quit the apps first; they overwrite their settings when they quit.
#
#   scripts/restore-settings.sh [computer]   default: this Mac's backup, or the
#                                            only backup if this Mac has none
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_REPO="${SETTINGS_REPO:-$(dirname "$REPO_ROOT")/app-settings}"
HOST="${1:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}"
HOST="$(echo "$HOST" | tr '[:upper:]' '[:lower:]')"
SRC="$SETTINGS_REPO/mac/$HOST"

git -C "$SETTINGS_REPO" pull -q --ff-only 2>/dev/null || true
if [[ ! -d "$SRC" && -z "${1:-}" ]]; then
  # New Mac: no backup under its name yet. Use the only one there is.
  backups=("$SETTINGS_REPO"/mac/*/)
  if [[ ${#backups[@]} -eq 1 && -d "${backups[0]}" ]]; then
    HOST="$(basename "${backups[0]}")"
    SRC="$SETTINGS_REPO/mac/$HOST"
    echo "No backup for this Mac; restoring $HOST."
  fi
fi
[[ -d "$SRC" ]] || {
  echo "No backup for $HOST. Pick one: scripts/restore-settings.sh <computer>" >&2
  echo "Available: $(ls "$SETTINGS_REPO/mac" 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
}

for plist in "$SRC"/*.plist; do
  [[ -e "$plist" ]] || continue
  domain="$(basename "$plist" .plist)"
  defaults import "$domain" "$plist" && echo "  restored $domain"
done

restore() {  # restore <name in backup> <destination>
  if [[ -e "$SRC/files/$1" ]]; then
    mkdir -p "$(dirname "$2")"
    rm -rf "$2"
    cp -R "$SRC/files/$1" "$2"
    echo "  restored $1"
  fi
}
restore "BetterModifiers" "$HOME/Library/Application Support/BetterModifiers"
restore "FineTune/settings.json" "$HOME/Library/Application Support/FineTune/settings.json"
restore "spaceman-backups" "$HOME/.spaceman"

MACCY="$HOME/Library/Containers/org.p0deje.Maccy/Data/Library"
restore "Maccy/org.p0deje.Maccy.plist" "$MACCY/Preferences/org.p0deje.Maccy.plist"
restore "Maccy/history" "$MACCY/Application Support/Maccy"

# macOS keyboard shortcuts saved by backup-settings.sh.
MACOS="$SRC/macos"
if [[ -d "$MACOS" ]]; then
  for plist in "$MACOS"/app-shortcuts/*.plist; do
    [[ -e "$plist" ]] || continue
    app="$(basename "$plist" .plist)"
    dst="-g"; [[ "$app" == NSGlobalDomain ]] || dst="$app"
    defaults write "$dst" NSUserKeyEquivalents "$(cat "$plist")" && echo "  restored app shortcuts: $app"
    # Lets System Settings → App Shortcuts list the restored entries.
    if ! defaults read com.apple.universalaccess com.apple.custommenu.apps 2>/dev/null | grep -qF -- "$app"; then
      defaults write com.apple.universalaccess com.apple.custommenu.apps -array-add "$app"
    fi
  done
  if [[ -e "$MACOS/symbolichotkeys.plist" ]]; then
    defaults import com.apple.symbolichotkeys "$MACOS/symbolichotkeys.plist" && echo "  restored system shortcuts"
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
  fi
  if [[ -e "$MACOS/double-click-action.txt" ]]; then
    defaults write -g AppleActionOnDoubleClick "$(cat "$MACOS/double-click-action.txt")"
  fi
fi

echo
echo "Done. Reopen the apps (quit with ⌘Q) so they pick up restored shortcuts."
