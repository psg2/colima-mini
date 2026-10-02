#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift format lint --strict --recursive Sources Tests Package.swift
swift test
./Scripts/test-sweep.sh
for script in Scripts/*.sh run-ui.command; do bash -n "$script"; done
python3 - "$ROOT/Sources/ColimaCore/Resources/docker-sweep.py" <<'PY'
import ast
import pathlib
import sys
ast.parse(pathlib.Path(sys.argv[1]).read_text())
PY
