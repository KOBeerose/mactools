#!/usr/bin/env bash
# Restore a backup made by scripts/backup-settings.sh. Quit the apps first;
# they overwrite their settings when they quit.
#
#   scripts/restore-settings.sh ~/Documents/mactools-settings/<timestamp>
set -euo pipefail

SRC="${1:?usage: $0 <backup folder>}"
[[ -d "$SRC" ]] || { echo "No such backup: $SRC" >&2; exit 1; }

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
