#!/usr/bin/env bash
# Export each mactools app's settings to a private folder outside the repo, for
# moving to a new Mac. Restore with scripts/restore-settings.sh <folder>.
#
#   BACKUP_DIR=~/Documents/mactools-settings  where backups go
#   INCLUDE_HISTORY=1                          also copy Maccy's clipboard history
#                                              (off by default: it can hold secrets)
set -euo pipefail

DEST="${BACKUP_DIR:-$HOME/Documents/mactools-settings}/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"
chmod 700 "$DEST"

# Plain UserDefaults domains (app not sandboxed).
DOMAINS=(
  dev.tahaelghabi.BetterModifiers
  dev.ruittenb.Spaceman
  com.ethanbills.DockDoor
  com.finetuneapp.FineTune
)
for domain in "${DOMAINS[@]}"; do
  if defaults export "$domain" "$DEST/$domain.plist" 2>/dev/null; then
    echo "  saved $domain"
  fi
done

# Files kept outside UserDefaults.
copy() {  # copy <source> <name in backup>
  if [[ -e "$1" ]]; then
    mkdir -p "$DEST/files/$(dirname "$2")"
    cp -R "$1" "$DEST/files/$2"
    echo "  saved $2"
  fi
}
copy "$HOME/Library/Application Support/BetterModifiers" "BetterModifiers"
copy "$HOME/Library/Application Support/FineTune/settings.json" "FineTune/settings.json"
copy "$HOME/.spaceman" "spaceman-backups"

# Maccy is sandboxed: its preferences (and history) live in its container.
MACCY="$HOME/Library/Containers/org.p0deje.Maccy/Data/Library"
copy "$MACCY/Preferences/org.p0deje.Maccy.plist" "Maccy/org.p0deje.Maccy.plist"
if [[ "${INCLUDE_HISTORY:-0}" == 1 ]]; then
  copy "$MACCY/Application Support/Maccy" "Maccy/history"
fi

echo
echo "Backup written to: $DEST"
