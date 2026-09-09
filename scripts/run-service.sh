#!/bin/bash
set -euo pipefail

# Runs the binary from a stable path so the Accessibility grant survives Homebrew
# upgrades, and signs it with a stable identity so replacing that file with a new
# build keeps the stored code requirement valid.

source_binary="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/cursor-resize-window"
run_binary="$(cd ~ && pwd)/Library/Application Support/cursor-resize-window/cursor-resize-window"
identity="cursor-resize-window-signing"

if [[ ! -f "$run_binary" ]] || ! cmp -s "$source_binary" "$run_binary"; then
  mkdir -p "$(dirname "$run_binary")"
  staged="$run_binary.staged.$$"
  cp "$source_binary" "$staged"
  chmod 0755 "$staged"
  identities="$(security find-identity -p codesigning 2>/dev/null || true)"
  if [[ "$identities" == *"$identity"* ]]; then
    if ! output="$(codesign --force --sign "$identity" --identifier "com.zuozh11.cursor-resize-window" --timestamp=none "$staged" 2>&1)"; then
      echo "cursor-resize-window: failed to sign with '$identity': $output" >&2
      echo "cursor-resize-window: Accessibility approval may be required again" >&2
    fi
  fi
  mv -f "$staged" "$run_binary"
fi

exec "$run_binary"
