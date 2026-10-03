#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNIVERSAL=false
INSTALL=false
for argument in "$@"; do
  case "$argument" in
    --universal) UNIVERSAL=true ;;
    --install) INSTALL=true ;;
    *) echo "Usage: $0 [--universal] [--install]" >&2; exit 1 ;;
  esac
done
VERSION="$(cat "$ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION.' >&2; exit 1; }
mkdir -p "$ROOT/build"
STAGING="$(mktemp -d "$ROOT/build/.app-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Colima Mini.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGING/AppIcon.iconset"
ARCHITECTURES=("$(uname -m)")
if $UNIVERSAL; then ARCHITECTURES=(arm64 x86_64); fi
BINARIES=()
for architecture in "${ARCHITECTURES[@]}"; do
  TRIPLE="$architecture-apple-macosx14.0"
  SCRATCH="$ROOT/.build-app/$architecture"
  swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release --product ColimaMini --triple "$TRIPLE" >&2
  BIN_DIR="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release --triple "$TRIPLE" --show-bin-path)"
  BINARIES+=("$BIN_DIR/ColimaMini")
  if [[ ! -d "$APP/Contents/Resources/ColimaMini_ColimaCore.bundle" ]]; then
    ditto "$BIN_DIR/ColimaMini_ColimaCore.bundle" "$APP/Contents/Resources/ColimaMini_ColimaCore.bundle"
  fi
done
if $UNIVERSAL; then
  lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/ColimaMini"
else
  cp "${BINARIES[0]}" "$APP/Contents/MacOS/ColimaMini"
fi
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/Resources/app-icon.png" --out "$STAGING/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$ROOT/Resources/app-icon.png" --out "$STAGING/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$STAGING/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
# The plist is versioned; the build stamps VERSION into it.
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >&2
codesign --verify --deep --strict "$APP"
FINAL="$ROOT/build/Colima Mini.app"
if [[ -e "$FINAL" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$FINAL/Contents/Info.plist" 2>/dev/null || true)" == 'com.psg2.colima-mini' ]] || { echo 'Another app exists in build.' >&2; exit 1; }
  rm -rf "$FINAL"
fi
mv "$APP" "$FINAL"
if $INSTALL; then
  TARGET="$HOME/Applications/Colima Mini.app"
  if [[ -e "$TARGET" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || true)" == 'com.psg2.colima-mini' ]] || { echo "Another app exists at $TARGET." >&2; exit 1; }
  fi
  mkdir -p "$HOME/Applications"
  ditto "$FINAL" "$TARGET"
fi
printf '%s\n' "$FINAL"
