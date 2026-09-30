#!/usr/bin/env bash
# Restore mactools apps' settings from the private app-settings repo. Quit the
# apps first; they overwrite their settings when they quit.
#
#   scripts/restore-settings.sh [computer]   default: this Mac's backup
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_REPO="${SETTINGS_REPO:-$(dirname "$REPO_ROOT")/app-settings}"
HOST="${1:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}"
HOST="$(echo "$HOST" | tr '[:upper:]' '[:lower:]')"
SRC="$SETTINGS_REPO/mac/$HOST"

git -C "$SETTINGS_REPO" pull -q --ff-only 2>/dev/null || true
[[ -d "$SRC" ]] || {
  echo "No backup for $HOST. Available: $(ls "$SETTINGS_REPO/mac" 2>/dev/null | tr '\n' ' ')" >&2
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

echo
echo "Done. Reopen the apps."
