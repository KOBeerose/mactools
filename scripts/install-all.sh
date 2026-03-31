#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="scripts/build-install-local.sh"

# Explicit tool list — update this when adding a new tool (see .agent/knowledge-base.md)
TOOLS=(
  layerkey
  spaceman
)

# ── Submodules ────────────────────────────────────────────────────────────────

echo "Initializing submodules..."
cd "$REPO_ROOT"
git submodule update --init --recursive
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
