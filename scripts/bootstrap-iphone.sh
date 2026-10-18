#!/usr/bin/env sh
# Terminal-IPHONE environment bootstrap (iOS).
#
# The Node.js runtime and npm ship inside the .deb (staged by
# scripts/fetch-runtime.mjs at build time). Every AI CLI is installed
# on-device through npm by the aienv manager; no external package manager
# is touched and no third-party version manager is used.
#
# This file is a thin shell around aienv: postinst runs it in the background
# after the package is installed, and `terminal-iphone` (or `aienv`) can be
# run again any time from the Terminal app.
set -u

d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 1
ROOT=$(CDPATH= cd -- "$d/../../.." 2>/dev/null && pwd -P) || exit 1

AIENV="$ROOT/usr/local/bin/aienv"
if [ -x "$AIENV" ]; then
	exec "$AIENV" bootstrap
fi

# self-contained fallback if aienv disappeared (rootful scheme edge cases)
echo "[*] aienv not found at $AIENV — minimal check only." >&2
"$ROOT/usr/local/bin/node" --version 2>/dev/null \
	|| echo "[!] Node.js runtime not working. Run 'aienv fix-node' from the Terminal app." >&2
exit 0
