#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

mkdir -p "$fixture_dir/live-project"
log="$fixture_dir/docker.log"
touch "$log"

ago() { date -u -v-"$1" +%Y-%m-%dT%H:%M:%S.123456789Z; }

container() { # id name project workdir host_port started [finished]
  python3 - "$@" <<'PY'
import json, sys
cid, name, project, workdir, port, started, *finished = sys.argv[1:]
labels = {}
if project:
    labels = {"com.docker.compose.project": project,
              "com.docker.compose.project.working_dir": workdir}
ports = {"5432/tcp": [{"HostIp": "127.0.0.1", "HostPort": port}]} if port else {}
print(json.dumps({"Id": cid, "Name": "/" + name, "Created": started,
  "State": {"Running": not finished, "StartedAt": started,
            "FinishedAt": finished[0] if finished else "0001-01-01T00:00:00Z"},
  "Config": {"Labels": labels}, "NetworkSettings": {"Ports": ports}}))
PY
}

write_state() { # logs_to_stderr
  cat >"$fixture_dir/state.json" <<JSON
{
  "logs_to_stderr": $1,
  "containers": [
    $(container orphan000001 gone-postgres gone-proj /nonexistent/worktree "" "$(ago 3d)"),
    $(container busy00000001 busy-pg "" "" 55001 "$(ago 5d)"),
    $(container idle00000001 old-postgres old-proj "$fixture_dir/live-project" "" "$(ago 5d)"),
    $(container fresh0000001 fresh-pg "" "" 55003 "$(ago 5d)"),
    $(container stale0000001 stale-postgres stale-proj "$fixture_dir/live-project" "" "$(ago 9d)" "$(ago 8d)"),
    $(container paused000001 paused-pg "" "" "" "$(ago 2d)" "$(ago 30M)")
  ],
  "logs": {
    "busy00000001": "$(ago 4d) LOG: checkpoint complete",
    "idle00000001": "$(ago 3d) LOG: checkpoint complete",
    "fresh0000001": "$(ago 10M) LOG: checkpoint complete"
  },
  "networks": {"gone-proj": "net-gone", "stale-proj": "net-stale"}
}
JSON
}

sweep() {
  DOCKER_SWEEP_DOCKER="$project_dir/Tests/SweepHelpers/fake-docker" \
  DOCKER_SWEEP_LSOF="$project_dir/Tests/SweepHelpers/fake-lsof" \
  FAKE_DOCKER_STATE="$fixture_dir/state.json" \
  FAKE_DOCKER_LOG="$log" \
    python3 "$project_dir/Sources/ColimaCore/Resources/docker-sweep.py" --sample 0 "$@"
}

fail() { printf 'FAIL: %s\n' "$1" >&2; printf '%s\n' "$output" >&2; exit 1; }

# Postgres logs to stderr: a container that logged minutes ago must not look idle.
write_state true

output="$(sweep)"
[[ ! -s "$log" ]] || fail "the report changed containers without --apply"
grep -Eq '^orphan +gone-proj' <<<"$output" || fail "stack with a deleted folder not reported as orphan"
grep -Eq '^active +busy-pg .*node\(31993\)' <<<"$output" || fail "container with a host client not reported as active"
grep -Eq '^idle +old-proj' <<<"$output" || fail "quiet stack not reported as idle"
grep -Eq '^recent +fresh-pg' <<<"$output" || fail "container that logged 10 minutes ago not reported as recent"
grep -Eq '^stale +stale-proj' <<<"$output" || fail "stack stopped 8 days ago not reported as stale"
grep -Eq '^stopped +paused-pg' <<<"$output" || fail "container stopped 30 minutes ago not reported as stopped"

output="$(sweep --json)"
[[ ! -s "$log" ]] || fail "the JSON report changed containers"
python3 - "$output" <<'PY' || fail "JSON report does not match the text verdicts"
import json, sys
groups = {g["name"]: g for g in json.loads(sys.argv[1])}
assert groups["gone-proj"]["verdict"] == "orphan" and groups["gone-proj"]["project"] == "gone-proj"
assert groups["gone-proj"]["containers"] == ["orphan000001"]
assert groups["old-proj"]["verdict"] == "idle"
assert groups["stale-proj"]["verdict"] == "stale"
assert groups["paused-pg"]["verdict"] == "stopped" and groups["paused-pg"]["project"] is None
PY
if sweep --json --apply >/dev/null 2>&1; then fail "--json --apply was accepted"; fi
[[ ! -s "$log" ]] || fail "--json --apply changed containers"

output="$(sweep --apply)"
expected="$(printf '%s\n' 'rm -f orphan000001' 'network rm net-gone' 'rm -f stale0000001' 'network rm net-stale' 'stop idle00000001')"
[[ "$(cat "$log")" == "$expected" ]] || { output="$(cat "$log")"; fail "--apply did not remove only orphan and stale groups and stop only the idle one"; }

: >"$log"
output="$(sweep --apply --idle-for 4d)"
[[ "$(cat "$log")" == "$(printf '%s\n' 'rm -f orphan000001' 'network rm net-gone' 'rm -f stale0000001' 'network rm net-stale')" ]] \
  || { output="$(cat "$log")"; fail "--idle-for 4d stopped a stack quiet for only 3 days"; }

for operation in ps inspect logs stats; do
  if output="$(FAKE_DOCKER_FAIL="$operation" sweep --sample 1 2>&1)"; then
    fail "failed $operation probe was accepted"
  fi
  [[ "$output" == *"Scan failed:"* ]] || fail "failed probe did not show a scan error"
  [[ "$output" != *"No containers."* && "$output" != *"Nothing to clean up."* ]] \
    || fail "failed probe looked like a successful empty scan"
done
if output="$(FAKE_LSOF_MODE=fail sweep 2>&1)"; then
  fail "failed client probe was accepted"
fi
[[ "$output" == *"Scan failed:"* && "$output" != *"idle "* ]] \
  || fail "failed client probe classified containers as idle"
output="$(FAKE_LSOF_MODE=empty sweep)"
[[ "$output" != *"Scan failed:"* ]] || fail "lsof's successful empty query was rejected"
if output="$(FAKE_DOCKER_FAIL=rm sweep --apply 2>&1)"; then
  fail "rejected cleanup was accepted"
fi
[[ "$output" == *"Scan failed:"* && "$output" != *"removed  "* ]] \
  || fail "rejected cleanup claimed it removed containers"

printf 'docker-sweep: ok\n'
