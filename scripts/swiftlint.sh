#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.swiftlint.yml"

# SwiftLint writes a cache file during linting. Keep that cache in a location we
# control (DerivedData when invoked from Xcode, otherwise a temp directory) so
# it works in restricted/sandboxed environments.
if [[ -n "${SWIFTLINT_CACHE_PATH:-}" ]]; then
  CACHE_PATH="$SWIFTLINT_CACHE_PATH"
elif [[ -n "${DERIVED_FILE_DIR:-}" ]]; then
  CACHE_PATH="${DERIVED_FILE_DIR}/swiftlint-cache"
else
  CACHE_PATH="${TMPDIR:-/tmp}/swiftlint-cache"
fi
mkdir -p "$CACHE_PATH"

# SwiftLint depends on SourceKit. When `xcode-select` points at CommandLineTools,
# SourceKitten can crash. Prefer the full Xcode toolchain when available.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$DEV_DIR" == *"CommandLineTools"* ]] && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "SwiftLint is not installed. Install via Homebrew: brew install swiftlint" >&2
  exit 1
fi

MODE="${1:-lint}"

case "$MODE" in
  lint)
    swiftlint lint --config "$CONFIG_FILE" --cache-path "$CACHE_PATH"
    ;;
  fix|autocorrect)
    swiftlint lint --fix --config "$CONFIG_FILE" --cache-path "$CACHE_PATH"
    swiftlint lint --config "$CONFIG_FILE" --cache-path "$CACHE_PATH"
    ;;
  *)
    echo "Usage: scripts/swiftlint.sh [lint|fix]" >&2
    exit 1
    ;;
 esac
