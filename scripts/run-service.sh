#!/bin/bash
set -euo pipefail

# Signs the installed binary with the stable identity when it is available, then
# runs it. This runs under launchd rather than Homebrew's build sandbox, which
# cannot read the login keychain, so the signature survives every rebuild and
# macOS keeps the Accessibility grant.

binary="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/cursor-resize-window"
identity="cursor-resize-window-signing"

identities="$(security find-identity -p codesigning 2>/dev/null || true)"
if [[ "$identities" == *"$identity"* ]]; then
  signature="$(codesign -dv --verbose=4 "$binary" 2>&1 || true)"
  if [[ "$signature" != *"Authority=$identity"* ]]; then
    chmod u+w "$binary"
    if ! output="$(codesign --force --sign "$identity" --identifier "com.zuozh11.cursor-resize-window" --timestamp=none "$binary" 2>&1)"; then
      echo "cursor-resize-window: failed to sign with '$identity': $output" >&2
      echo "cursor-resize-window: Accessibility approval may be required again" >&2
    fi
  fi
fi

exec "$binary"
