#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -d "/opt/homebrew/opt/ruby/bin" ]]; then
  export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:${PATH}"
fi

if [[ -f "$ROOT_DIR/fastlane/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/fastlane/.env"
  set +a
fi

if [[ ! -f "$ROOT_DIR/Gemfile.lock" ]]; then
  echo "Installing fastlane (first run)..."
  bundle install
fi

exec bundle exec fastlane "$@"
