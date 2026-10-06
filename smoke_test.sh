#!/usr/bin/env bash
# Verify a built WakeAlarm.app looks sane and can launch briefly.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/WakeAlarm.app"
BIN="$APP/Contents/MacOS/WakeAlarm"
PLIST="$APP/Contents/Info.plist"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

if [[ ! -d "$APP" ]]; then
  echo "No build found — running ./build.sh first …"
  "$ROOT/build.sh"
fi

[[ -x "$BIN" ]] || fail "missing executable $BIN"
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || fail "missing AppIcon.icns"
[[ -f "$APP/Contents/Resources/Fonts/DSEG7Classic-Bold.ttf" ]] || fail "missing DSEG font"
[[ -f "$APP/Contents/Resources/Fonts/DSEG-LICENSE.txt" ]] || fail "missing DSEG license"
[[ -f "$PLIST" ]] || fail "missing Info.plist"

ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
ICON="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")"

[[ "$ID" == "app.wakealarm" ]] || fail "unexpected bundle id: $ID"
[[ "$NAME" == "WakeAlarm" ]] || fail "unexpected bundle name: $NAME"
[[ "$ICON" == "AppIcon" ]] || fail "unexpected icon key: $ICON"
pass "plist $NAME $VER ($ID)"

file "$BIN" | grep -q "Mach-O" || fail "binary is not Mach-O"
pass "binary $(file -b "$BIN")"

# codesign should at least be ad-hoc
codesign -v --strict "$APP" 2>/dev/null || fail "codesign verification failed"
pass "codesign ok"

# Launch briefly, confirm process, then quit
killall WakeAlarm 2>/dev/null || true
open "$APP"
for _ in $(seq 1 20); do
  if pgrep -x WakeAlarm >/dev/null; then
    break
  fi
  sleep 0.25
done
pgrep -x WakeAlarm >/dev/null || fail "WakeAlarm did not launch"
pass "process running (pid $(pgrep -x WakeAlarm | tr '\n' ' '))"

# Give SwiftUI a moment to finish launching, then quit cleanly
sleep 1.5
osascript -e 'tell application "WakeAlarm" to quit' 2>/dev/null || killall WakeAlarm 2>/dev/null || true
sleep 0.5
if pgrep -x WakeAlarm >/dev/null; then
  killall -9 WakeAlarm 2>/dev/null || true
  fail "WakeAlarm did not quit cleanly"
fi
pass "quit cleanly"

echo
echo "All smoke checks passed."
