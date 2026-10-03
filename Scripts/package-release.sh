#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
"$ROOT/Scripts/build.sh" --universal
cd "$ROOT/build"
ARCHIVE="ColimaMini-$VERSION-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent 'Colima Mini.app' "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
printf '%s\n' "$ROOT/build/$ARCHIVE"
