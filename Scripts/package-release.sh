#!/usr/bin/env bash
set -euo pipefail

# Builds the universal release archive and its SHA-256 checksum in build/release.
#
# Signing modes:
#   COLIMA_MINI_RELEASE_SIGNING=adhoc  Ad hoc signing without notarization.
# Developer ID signing and notarization aren't set up yet, so the script refuses
# to package unless the ad hoc mode is chosen explicitly.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${COLIMA_MINI_RELEASE_SIGNING:-}" != "adhoc" ]]; then
  echo "Set COLIMA_MINI_RELEASE_SIGNING=adhoc for an unnotarized release." >&2
  exit 1
fi
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
OUTPUT="$ROOT/build/release"
ARCHIVE="ColimaMini-$VERSION-macos-universal.zip"
"$ROOT/Scripts/build.sh" --universal >/dev/null
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/Colima Mini.app" "$OUTPUT/$ARCHIVE"
(cd "$OUTPUT" && shasum -a 256 "$ARCHIVE" >"$ARCHIVE.sha256")
printf '%s\n' "$OUTPUT/$ARCHIVE"
