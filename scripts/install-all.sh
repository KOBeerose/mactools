#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="scripts/build-install-local.sh"

# Explicit tool list — update this when adding a new tool (see .agent/knowledge-base.md)
TOOLS=(
  bettermodifiers
  spaceman
  maccy
  finetune
  dockdoor
)

# Fork submodules: folder -> upstream URL
# Update this when adding a new fork submodule (see .cursor/skills/sync-fork-submodule/submodule-guide.md)
# "folder=url" pairs, not `declare -A`: macOS ships bash 3.2, which has no associative arrays.
UPSTREAM_REMOTES=(
  "spaceman=https://github.com/ruittenb/Spaceman.git"
  "maccy=https://github.com/p0deje/Maccy.git"
  "finetune=https://github.com/ronitsingh10/FineTune.git"
  "dockdoor=https://github.com/ejbills/DockDoor.git"
  "wox=https://github.com/Wox-launcher/Wox.git"
)

# ── Submodules ────────────────────────────────────────────────────────────────

echo "Initializing submodules..."
cd "$REPO_ROOT"
git submodule update --init --recursive

echo "Setting up upstream remotes for fork submodules..."
for entry in "${UPSTREAM_REMOTES[@]}"; do
  folder="${entry%%=*}"
  url="${entry#*=}"
  if git -C "$REPO_ROOT/$folder" remote get-url upstream &>/dev/null; then
    echo "  $folder: upstream already set"
  else
    git -C "$REPO_ROOT/$folder" remote add upstream "$url"
    echo "  $folder: upstream added -> $url"
  fi
done
echo

# ── Install tools ─────────────────────────────────────────────────────────────

FAILED=()

for tool in "${TOOLS[@]}"; do
  tool_dir="$REPO_ROOT/$tool"
  script_path="$tool_dir/$BUILD_SCRIPT"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Installing $tool..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if (cd "$tool_dir" && bash "$script_path"); then
    echo "  ✓ $tool installed"
  else
    echo "  ✗ $tool failed"
    FAILED+=("$tool")
  fi
  echo
done

# ── Summary ───────────────────────────────────────────────────────────────────

total="${#TOOLS[@]}"
failed=${#FAILED[@]}
passed=$((total - failed))

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Done: $passed/$total tools installed"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "Failed:"
  for t in "${FAILED[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
