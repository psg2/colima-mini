#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/Colima Mini.app}"
codesign --verify --deep --strict "$APP"
SUMMARY="$("$APP/Contents/MacOS/ColimaMini" --check --fixture "$ROOT/Tests/ColimaCoreTests/Fixtures/sample.json")"
summary() { plutil -extract "$1" "$2" -o - - <<<"$SUMMARY"; }
test "$(summary containers raw)" = 3
test "$(summary running raw)" = 2
test "$(summary localhostPorts json)" = '[5432,8080]'
echo 'Packaged app summary passed'
"$APP/Contents/MacOS/ColimaMini" --scan --fixture "$ROOT/Tests/ColimaCoreTests/Fixtures/sample.json" | grep -q '^stale    worker'
test -s "$APP/Contents/Resources/AppIcon.icns"
"$APP/Contents/MacOS/ColimaMini" --help >/dev/null
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION"
# The binary's minimum macOS must match the plist, and a universal build must
# hold both architectures.
MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/ColimaMini")"
for architecture in $ARCHITECTURES; do
  minos="$(vtool -arch "$architecture" -show-build "$APP/Contents/MacOS/ColimaMini" | awk '$1 == "minos" {print $2; exit}')"
  test "$minos" = "$MINIMUM" || {
    echo "$architecture targets macOS $minos, but Info.plist says $MINIMUM" >&2
    exit 1
  }
done
if [[ "${EXPECT_UNIVERSAL:-}" == 1 ]]; then
  [[ " $ARCHITECTURES " == *" arm64 "* && " $ARCHITECTURES " == *" x86_64 "* ]] || {
    echo "Expected a universal binary, got: $ARCHITECTURES" >&2
    exit 1
  }
fi
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
ditto "$APP" "$TEMP/Colima Mini.app"
cat > "$TEMP/docker" <<'DOCKER'
#!/bin/sh
test -z "${DOCKER_HOST:-}" || exit 41
test "$*" = "--context colima ps -aq" || exit 42
DOCKER
chmod +x "$TEMP/docker"
COLIMA_MINI_DOCKER="$TEMP/docker" DOCKER_HOST=unix:///nonexistent/foreign-engine.sock \
  "$TEMP/Colima Mini.app/Contents/MacOS/ColimaMini" --scan | grep -q 'No containers'
echo 'Relocated app passed'
