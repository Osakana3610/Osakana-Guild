#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

CONFIG="${SCRIPT_INPUT_FILE_0:-${SRCROOT}/periphery.yml}"
OUT="${SCRIPT_OUTPUT_FILE_0:-${PROJECT_TEMP_DIR}/periphery.last-run}"

if [ ! -f "$CONFIG" ]; then
  exit 0
fi

ARGS=(scan --config "$CONFIG")
if [ -n "${INDEX_STORE_PATH:-}" ]; then
  ARGS+=(--index-store-path "$INDEX_STORE_PATH")
fi

if command -v periphery >/dev/null 2>&1; then
  RUNNER=(periphery)
elif command -v mint >/dev/null 2>&1; then
  RUNNER=(mint run peripheryapp/periphery@latest periphery)
else
  echo "periphery または mint が見つからないためスキャンをスキップします。"
  mkdir -p "$(dirname "$OUT")"; date > "$OUT"
  exit 0
fi

"${RUNNER[@]}" "${ARGS[@]}" || true

mkdir -p "$(dirname "$OUT")"
date > "$OUT"
