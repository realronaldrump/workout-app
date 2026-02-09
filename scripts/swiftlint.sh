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

# With Xcode "User Script Sandboxing" enabled, tools typically need an explicit
# allowlist of readable files. Xcode's sandbox allowlist is driven by the script
# phase's input file list, but those entries are not always exported as
# `SCRIPT_INPUT_FILE_*` environment variables. When a file list is provided, we
# convert it into `SCRIPT_INPUT_FILE_*` vars so SwiftLint can use
# `--use-script-input-files` and avoid scanning the filesystem.
use_script_input_files=false
if [[ -n "${SWIFTLINT_INPUT_FILELIST:-}" ]] && [[ -f "${SWIFTLINT_INPUT_FILELIST}" ]]; then
  mapfile -t _swift_files < "${SWIFTLINT_INPUT_FILELIST}"
  swift_count=0
  for raw in "${_swift_files[@]}"; do
    [[ -z "$raw" ]] && continue
    line="$raw"
    if [[ "$line" == '$(SRCROOT)/'* ]]; then
      line="${SRCROOT}/${line#'$(SRCROOT)/'}"
    fi
    export "SCRIPT_INPUT_FILE_${swift_count}=${line}"
    swift_count=$((swift_count + 1))
  done
  export SCRIPT_INPUT_FILE_COUNT="${swift_count}"
  use_script_input_files=true
elif [[ -n "${SCRIPT_INPUT_FILE_COUNT:-}" ]] && [[ "${SCRIPT_INPUT_FILE_COUNT}" -gt 0 ]]; then
  use_script_input_files=true
fi

MODE="${1:-lint}"

case "$MODE" in
  lint)
    cache_args=(--cache-path "$CACHE_PATH")
    if [[ -n "${SWIFTLINT_NO_CACHE:-}" ]]; then
      cache_args=(--no-cache)
    fi

    args=(lint --config "$CONFIG_FILE" "${cache_args[@]}")
    if [[ "${use_script_input_files}" == "true" ]]; then
      args+=(--use-script-input-files)
    fi
    swiftlint "${args[@]}"
    ;;
  fix|autocorrect)
    cache_args=(--cache-path "$CACHE_PATH")
    if [[ -n "${SWIFTLINT_NO_CACHE:-}" ]]; then
      cache_args=(--no-cache)
    fi

    fix_args=(lint --fix --config "$CONFIG_FILE" "${cache_args[@]}")
    lint_args=(lint --config "$CONFIG_FILE" "${cache_args[@]}")
    if [[ "${use_script_input_files}" == "true" ]]; then
      fix_args+=(--use-script-input-files)
      lint_args+=(--use-script-input-files)
    fi
    swiftlint "${fix_args[@]}"
    swiftlint "${lint_args[@]}"
    ;;
  *)
    echo "Usage: scripts/swiftlint.sh [lint|fix]" >&2
    exit 1
    ;;
 esac
