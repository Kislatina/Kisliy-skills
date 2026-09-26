#!/bin/zsh
# Rebuild offstage and install it into bin/. Stops a running daemon first:
# overwriting a mapped binary in place gets it SIGKILLed by the kernel.
set -e
cd "$(dirname "$0")"
if [ -S ~/Library/Caches/offstage/offstage.sock ]; then ./bin/offstage down >/dev/null 2>&1 || true; sleep 0.5; fi
(cd tool && swift build -c release 2>&1 | grep -E "error|warning: var|Compiling|Build" || true)
rm -f bin/offstage
cp tool/.build/release/offstage bin/offstage
codesign -s - -f bin/offstage
echo "installed: $(pwd)/bin/offstage"
