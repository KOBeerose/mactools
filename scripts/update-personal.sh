#!/usr/bin/env bash
# Rebase the `personal` branch onto main, then build and install BetterModifiers
# from it. `personal` holds changes only for this setup (see "Personal branch"
# in .agent/knowledge-base.md); it lives in a worktree next to mactools so this
# checkout can stay on main.
#
#   NO_PUSH=1     don't push the rebased branch
#   NO_INSTALL=1  rebase only
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_REPO="$(git -C "$REPO_ROOT" worktree list --porcelain | awk 'NR==1 {print $2}')"
PERSONAL="${PERSONAL_DIR:-$(dirname "$MAIN_REPO")/mactools-personal}"

if [[ ! -d "$PERSONAL" ]]; then
  echo "Creating the personal worktree at $PERSONAL..."
  git -C "$MAIN_REPO" fetch -q origin personal
  git -C "$MAIN_REPO" worktree add -q "$PERSONAL" personal
fi

if [[ -n "$(git -C "$PERSONAL" status --porcelain)" ]]; then
  echo "$PERSONAL has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

echo "Rebasing personal onto main..."
if ! git -C "$PERSONAL" rebase -q main; then
  echo >&2
  echo "Conflict. Fix it in $PERSONAL, then:" >&2
  echo "  git -C \"$PERSONAL\" add <files> && git -C \"$PERSONAL\" rebase --continue" >&2
  echo "and run this script again. Or give up with: git -C \"$PERSONAL\" rebase --abort" >&2
  exit 1
fi
git -C "$PERSONAL" log --oneline main..personal | sed 's/^/  personal: /'

if [[ "${NO_PUSH:-0}" != 1 ]]; then
  # The rebase rewrites the branch, so a plain push would be refused.
  git -C "$PERSONAL" push -q --force-with-lease -u origin personal
  echo "Pushed personal."
fi

if [[ "${NO_INSTALL:-0}" != 1 ]]; then
  (cd "$PERSONAL/bettermodifiers" && ./scripts/build-install-local.sh)
fi
