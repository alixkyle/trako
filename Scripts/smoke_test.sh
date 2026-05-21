#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXECUTABLE="${ROOT_DIR}/.build/release/Trako.app/Contents/MacOS/Trako"
LOG_FILE="${TMPDIR:-/tmp}/trako-smoke.log"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Missing executable app. Run Scripts/build_app.sh first." >&2
  exit 1
fi

"$APP_EXECUTABLE" >"$LOG_FILE" 2>&1 &
pid=$!
sleep 3
kill "$pid" >/dev/null 2>&1 || true
wait "$pid" >/dev/null 2>&1 || true

if grep -Eiq "fatal|exception|crash" "$LOG_FILE"; then
  cat "$LOG_FILE" >&2
  exit 1
fi

echo "Smoke test passed"
