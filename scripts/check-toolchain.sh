#!/usr/bin/env bash
# Warn when the local Xcode / Swift differ from toolchain.env. Sourced by
# install-all.sh; safe to run on its own.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../toolchain.env
source "$ROOT/toolchain.env"

xcode="$(xcodebuild -version 2>/dev/null | awk 'NR==1 {print $2}')"
swift="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9.]*\).*/\1/p' | head -1)"

check() {  # check <name> <wanted> <found>
  if [[ "$3" == "$2" ]]; then
    echo "  $1 $3 ✓"
  else
    echo "  warning: $1 ${3:-missing}, tested with $2 (builds may differ; bump toolchain.env once it works)" >&2
  fi
}
echo "Toolchain:"
check Xcode "$XCODE_VERSION" "$xcode"
check Swift "$SWIFT_VERSION" "$swift"
