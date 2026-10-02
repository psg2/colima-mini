#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build-app.sh" >/dev/null
open "$ROOT/dist/Colima Mini.app" --args "$@"
