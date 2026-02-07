#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.swiftlint.yml"

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
    swiftlint --config "$CONFIG_FILE"
    ;;
  fix|autocorrect)
    swiftlint autocorrect --config "$CONFIG_FILE"
    swiftlint --config "$CONFIG_FILE"
    ;;
  *)
    echo "Usage: scripts/swiftlint.sh [lint|fix]" >&2
    exit 1
    ;;
 esac
