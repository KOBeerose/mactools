#!/usr/bin/env bash
# Back up mactools apps' settings into the private app-settings repo, under
# mac/<computer>/, then commit and push. Restore with scripts/restore-settings.sh.
#
#   SETTINGS_REPO=<path>   clone of KOBeerose/app-settings (default: next to mactools)
#   INCLUDE_HISTORY=1      also copy Maccy's clipboard history (off: it can hold secrets)
#   NO_PUSH=1              commit only
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_REPO="${SETTINGS_REPO:-$(dirname "$REPO_ROOT")/app-settings}"
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
HOST="$(echo "$HOST" | tr '[:upper:]' '[:lower:]')"
DEST="$SETTINGS_REPO/mac/$HOST"

[[ -d "$SETTINGS_REPO/.git" ]] || {
  echo "No app-settings clone at $SETTINGS_REPO. Clone it first:" >&2
  echo "  git clone https://github.com/KOBeerose/app-settings.git \"$SETTINGS_REPO\"" >&2
  exit 1
}

rm -rf "$DEST"
mkdir -p "$DEST"

# Plain UserDefaults domains (apps not sandboxed).
DOMAINS=(
  dev.tahaelghabi.BetterModifiers
  dev.ruittenb.Spaceman
  com.ethanbills.DockDoor
  com.finetuneapp.FineTune
)
for domain in "${DOMAINS[@]}"; do
  if defaults export "$domain" "$DEST/$domain.plist" 2>/dev/null; then
    # XML so git shows readable diffs between backups.
    plutil -convert xml1 "$DEST/$domain.plist"
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

cd "$SETTINGS_REPO"
git add -A "mac/$HOST"
if git diff --cached --quiet; then
  echo "No changes since the last backup."
  exit 0
fi
git commit -q -m "backup mac/$HOST"
[[ "${NO_PUSH:-0}" == 1 ]] || git push -q
echo "Backed up to app-settings/mac/$HOST$([[ "${NO_PUSH:-0}" == 1 ]] && echo " (not pushed)")."
