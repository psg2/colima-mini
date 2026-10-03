#!/usr/bin/env bash
set -euo pipefail

# Removes the installed app and, optionally, its preferences. Colima, its VM
# and your containers are never touched.

APP="$HOME/Applications/Colima Mini.app"
BUNDLE_IDENTIFIER="com.psg2.colima-mini"
remove_app=0
remove_preferences=0

usage() {
  cat <<'EOF'
Usage: ./Scripts/uninstall-local.sh [options]

  --app          Remove ~/Applications/Colima Mini.app
  --preferences  Remove Colima Mini user defaults
  --all          Both
EOF
}

for argument in "$@"; do
  case "$argument" in
    --app) remove_app=1 ;;
    --preferences) remove_preferences=1 ;;
    --all)
      remove_app=1
      remove_preferences=1
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $argument" >&2
      usage >&2
      exit 2
      ;;
  esac
done
if [[ "$remove_app" -eq 0 && "$remove_preferences" -eq 0 ]]; then
  usage >&2
  exit 2
fi

if [[ "$remove_app" -eq 1 && -e "$APP" ]]; then
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$identifier" != "$BUNDLE_IDENTIFIER" ]]; then
    echo "$APP isn't Colima Mini; leaving it in place." >&2
    exit 1
  fi
  pkill -f "$APP/Contents/MacOS/ColimaMini" || true
  rm -rf -- "$APP"
  echo "Removed $APP"
fi
if [[ "$remove_preferences" -eq 1 ]]; then
  defaults delete "$BUNDLE_IDENTIFIER" 2>/dev/null || true
  echo "Removed $BUNDLE_IDENTIFIER preferences"
fi
