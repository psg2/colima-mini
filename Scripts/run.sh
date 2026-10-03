#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build.sh" >/dev/null
for argument in "$@"; do
  if [[ "$argument" == --fixture ]]; then
    exec open -n "$ROOT/build/Colima Mini.app" --args "$@"
  fi
done
open "$ROOT/build/Colima Mini.app" --args "$@"
