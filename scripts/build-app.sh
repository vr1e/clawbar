#!/bin/bash
# Builds build/ClawBar.app: release binary, Info.plist, an icon drawn from Clawd's pixels, ad-hoc signature.
# --install copies it to ~/Applications, quitting a running copy first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

install=false
for arg in "$@"; do
    case "$arg" in
        --install) install=true ;;
        *) echo "usage: scripts/build-app.sh [--install]" >&2; exit 2 ;;
    esac
done

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClawBar"

APP="$ROOT/build/ClawBar.app"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClawBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

"$BIN" --make-icon "$ROOT/build" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "built $APP"

if $install; then
    DEST="$HOME/Applications/ClawBar.app"
    # A running copy keeps the old binary mapped: ask it to quit, then wait for that process to go. Only the
    # default root's copy: an exported CLAWBAR_HOME would aim at a sandbox, and sandbox copies keep running.
    pid=$(env -u CLAWBAR_HOME "$BIN" --dump-state 2>/dev/null | sed -n 's/^app: .*(pid \([0-9]*\))$/\1/p' || true)
    if [ -n "$pid" ] && env -u CLAWBAR_HOME "$BIN" --command quit >/dev/null 2>&1; then
        for _ in $(seq 1 100); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
    fi
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
    echo "installed $DEST"
fi
