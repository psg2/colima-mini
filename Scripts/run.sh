#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build-app.sh" >/dev/null
for argument in "$@"; do
  if [[ "$argument" == --fixture ]]; then
    exec open -n "$ROOT/dist/Colima Mini.app" --args "$@"
  fi
done
open "$ROOT/dist/Colima Mini.app" --args "$@"
