#!/usr/bin/env bash
# Print what an upstream sync would bring into a fork submodule, grouped by
# what matters for a build-from-source, audit-before-merge policy. Read-only:
# it fetches `upstream` and diffs; it never merges or checks anything out.
#
# Usage: scripts/audit-upstream.sh <submodule>     e.g. scripts/audit-upstream.sh maccy
# Works with macOS's stock bash 3.2.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${1:?usage: $0 <submodule>}"
DIR="$REPO_ROOT/$NAME"
BRANCH="$(git -C "$REPO_ROOT" config -f .gitmodules "submodule.$NAME.branch" || echo main)"

[[ -d "$DIR" ]] || { echo "No submodule folder: $DIR" >&2; exit 1; }
git -C "$DIR" remote get-url upstream >/dev/null 2>&1 \
  || { echo "$NAME has no 'upstream' remote (run scripts/install-all.sh)" >&2; exit 1; }

echo "Fetching upstream for $NAME ($BRANCH)..."
git -C "$DIR" fetch -q upstream

LOCAL="$BRANCH"
REMOTE="upstream/$BRANCH"
BASE="$(git -C "$DIR" merge-base "$LOCAL" "$REMOTE")"
RANGE="$BASE..$REMOTE"
g() { git -C "$DIR" "$@"; }

section() { printf '\n━━ %s ━━\n' "$1"; }

# Files changed upstream matching an extended regex, with line counts.
changed() {
  g diff --stat=120 "$RANGE" -- . | grep -E "$1" || echo "  (none)"
}

# Added lines (upstream side only) matching a regex, with their file (first 40).
# Capped inside awk, not with `head`: under pipefail a closed pipe aborts the script.
# awk -v eats backslashes, so write literal parens as [(] in patterns.
added_lines() {
  g diff -U0 "$RANGE" -- "${@:2}" \
    | awk -v re="$1" '/^\+\+\+ /{f=substr($0,7)} /^\+[^+]/ && $0 ~ re && n++ < 40 {print "  " f ": " substr($0,2)}'
}

section "Commits ($(g rev-list --count "$RANGE") new, $(g rev-list --count "$REMOTE..$LOCAL") fork-only)"
g log -n 60 --format='  %h %ad %s' --date=short "$RANGE"
echo "  fork-only:"
g log --format='    %h %s' "$REMOTE..$LOCAL"

section "Dependencies (review every bump; note binaryTarget = prebuilt)"
changed 'Package\.(swift|resolved)|Podfile|Cartfile|package(-lock)?\.json|yarn\.lock|Cargo\.(toml|lock)|go\.(mod|sum)|Gemfile'
added_lines 'binaryTarget|"version"|"revision"|minimumVersion|XCRemoteSwiftPackageReference' \
  '*Package.swift' '*Package.resolved' '*.pbxproj' '*Podfile*' '*Cargo.toml' '*package.json'

section "Permissions: entitlements, Info.plist, privacy strings"
changed '\.entitlements|Info\.plist|PrivacyInfo|\.xcprivacy'
added_lines 'NS[A-Za-z]+UsageDescription|com\.apple\.security|SUFeedURL|SUPublicEDKey|LSUIElement' .

section "Build-time code: run-script phases, Makefiles, scripts"
changed 'project\.pbxproj|Makefile|\.sh$|\.py$|scripts/'
added_lines 'shellScript|ShellScriptBuildPhase' '*.pbxproj'

section "Updater (should stay off in the fork)"
added_lines 'Sparkle|SPU[A-Za-z]+|startingUpdater|checkForUpdates|autoUpdater|SUFeedURL' .

section "Network, processes and telemetry in added code"
added_lines 'https?://|URLSession|URL[(]string|NSTask|Process[(][)]|posix_spawn|socket|[Aa]nalytics|[Tt]elemetry|[Ss]entry|[Ff]irebase|[Cc]rashlytics|mixpanel|amplitude|posthog' \
  ':(exclude)*.md' ':(exclude)*.strings' ':(exclude)*.xcstrings' ':(exclude)*.lproj/*' ':(exclude)appcast.xml'

section "Agent and CI instructions (upstream-controlled text agents will follow)"
changed 'CLAUDE\.md|AGENTS\.md|\.claude/|\.cursor/|copilot-instructions|\.github/workflows'

section "Merge preview against $LOCAL"
if tree="$(g merge-tree --write-tree "$LOCAL" "$REMOTE" 2>/dev/null)"; then
  echo "  clean (tree ${tree%%$'\n'*})"
else
  echo "  CONFLICTS:"
  g merge-tree --write-tree --name-only "$LOCAL" "$REMOTE" 2>/dev/null | tail -n +2 | sed 's/^/    /' || true
fi

echo
echo "Nothing was merged. Review the sections above, then follow step 3 of"
echo ".cursor/skills/sync-fork-submodule/SKILL.md."
