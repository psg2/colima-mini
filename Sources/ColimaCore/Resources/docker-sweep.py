#!/usr/bin/env python3
"""Find Docker containers nobody is using and, with --apply, clean them up.

Containers are grouped by compose project (standalone containers are their own
group) and each group gets one verdict:

  orphan  a compose stack whose project folder no longer exists (a deleted
          worktree). --apply removes its containers and networks.
  active  a host process is connected to a published port, or the containers
          sent or received traffic during the sample window. Never touched.
  idle    running, but nothing connected, no traffic, and no log line for at
          least --idle-for. --apply stops it (docker start brings it back).
  recent  running and quiet, but logged something within --idle-for. Kept.
  stale   not running for at least --idle-for. --apply removes its containers
          and networks; `docker compose up` recreates them on the same volumes.
  stopped not running, but stopped within --idle-for. Kept.

Volumes are never removed, so everything --apply removes can be recreated.

Usage:
  docker-sweep                  report only
  docker-sweep --apply          remove orphan and stale groups, stop idle ones
  docker-sweep --idle-for 3d    idle threshold (m, h or d; default 24h)
  docker-sweep --sample 10      traffic sample window in seconds (default 30, 0 skips)
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

DOCKER = os.environ.get("DOCKER_SWEEP_DOCKER", "docker")
LSOF = os.environ.get("DOCKER_SWEEP_LSOF", "lsof")
DOCKER_PROCESSES = ("com.docke", "vpnkit", "docker")


def run(*args, stderr=subprocess.DEVNULL):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=stderr, text=True).stdout.strip()


def parse_duration(text):
    match = re.fullmatch(r"(\d+)([mhd])", text)
    if not match:
        raise argparse.ArgumentTypeError("use a number followed by m, h or d, e.g. 24h")
    return int(match[1]) * {"m": 60, "h": 3600, "d": 86400}[match[2]]


def parse_time(stamp):
    """Docker timestamps carry nanoseconds; seconds are enough here."""
    if not stamp or stamp.startswith("0001-"):
        return None
    return datetime.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)


def human(seconds):
    if seconds >= 86400:
        return f"{seconds // 86400}d"
    if seconds >= 3600:
        return f"{seconds // 3600}h"
    return f"{seconds // 60}m"


def net_io():
    lines = run(DOCKER, "stats", "--no-stream", "--format", "{{.ID}}\t{{.NetIO}}")
    return dict(line.split("\t", 1) for line in lines.splitlines() if "\t" in line)


def host_clients():
    """Map published host port -> processes connected to it from the host."""
    clients = {}
    for line in run(LSOF, "-nP", "-iTCP", "-sTCP:ESTABLISHED").splitlines()[1:]:
        fields = line.split()
        if len(fields) < 9 or fields[0].startswith(DOCKER_PROCESSES) or "->" not in line:
            continue
        name = next(f for f in fields if "->" in f)
        port = name.split("->")[1].rsplit(":", 1)[-1]
        clients.setdefault(port, set()).add(f"{fields[0]}({fields[1]})")
    return clients


def last_activity(container):
    state = container["State"]
    if not state["Running"]:
        return parse_time(state.get("FinishedAt"))
    # Many images (Postgres included) log to stderr, so read both streams.
    logged = run(DOCKER, "logs", "-t", "--tail", "1", container["Id"], stderr=subprocess.STDOUT)
    stamps = [parse_time(logged.split()[0])] if logged else []
    return max([t for t in stamps if t] + [parse_time(state["StartedAt"])])


def classify(group, clients, traffic, idle_for, now):
    first = group["containers"][0]
    workdir = first["Config"]["Labels"].get("com.docker.compose.project.working_dir")
    if workdir and not os.path.isdir(workdir):
        return "orphan", f"folder gone: {workdir}"
    running = [c for c in group["containers"] if c["State"]["Running"]]
    if not running:
        # A container created but never started has no FinishedAt.
        stopped_at = max(
            parse_time(c["State"].get("FinishedAt")) or parse_time(c["Created"])
            for c in group["containers"]
        )
        stopped_for = int((now - stopped_at).total_seconds())
        if stopped_for >= idle_for:
            return "stale", f"not running for {human(stopped_for)}"
        return "stopped", f"stopped {human(stopped_for)} ago"
    connected = sorted(
        client
        for c in running
        for bindings in (c["NetworkSettings"]["Ports"] or {}).values()
        for binding in bindings or []
        for client in clients.get(binding["HostPort"], ())
    )
    if connected:
        return "active", "clients: " + " ".join(dict.fromkeys(connected))
    if any(c["Id"][:12] in traffic for c in running):
        return "active", "network traffic during sample"
    quiet_for = int((now - max(last_activity(c) for c in running)).total_seconds())
    if quiet_for >= idle_for:
        return "idle", f"no clients, no traffic, quiet for {human(quiet_for)}"
    return "recent", f"no clients, no traffic, last log {human(quiet_for)} ago"


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--apply", action="store_true", help="remove orphan and stale groups, stop idle ones")
    parser.add_argument("--idle-for", type=parse_duration, default=parse_duration("24h"))
    parser.add_argument("--sample", type=int, default=30)
    args = parser.parse_args()

    ids = run(DOCKER, "ps", "-aq").split()
    if not ids:
        print("No containers.")
        return
    containers = json.loads(run(DOCKER, "inspect", *ids))

    groups = {}
    for c in containers:
        labels = c["Config"]["Labels"] = c["Config"]["Labels"] or {}
        project = labels.get("com.docker.compose.project")
        key = project or c["Name"].lstrip("/")
        groups.setdefault(key, {"name": key, "project": project, "containers": []})
        groups[key]["containers"].append(c)

    traffic = set()
    if args.sample > 0:
        print(f"Sampling network traffic for {args.sample}s…", file=sys.stderr)
        before = net_io()
        time.sleep(args.sample)
        after = net_io()
        traffic = {cid[:12] for cid, io in after.items() if before.get(cid) not in (None, io)}

    clients = host_clients()
    now = datetime.now(timezone.utc)
    verdicts = []
    for group in groups.values():
        verdict, reason = classify(group, clients, traffic, args.idle_for, now)
        verdicts.append((verdict, group, reason))

    order = ["orphan", "stale", "idle", "recent", "active", "stopped"]
    verdicts.sort(key=lambda v: (order.index(v[0]), v[1]["name"]))
    for verdict, group, reason in verdicts:
        count = len(group["containers"])
        name = group["name"] + (f" ({count})" if count > 1 else "")
        print(f"{verdict:<8} {name:<50} {reason}")

    removable = [g for v, g, _ in verdicts if v in ("orphan", "stale")]
    idle = [g for v, g, _ in verdicts if v == "idle"]
    if not removable and not idle:
        print("\nNothing to clean up.")
        return
    if not args.apply:
        print(
            f"\n{len(removable)} orphan or stale group(s) would be removed and"
            f" {len(idle)} idle group(s) stopped. Re-run with --apply to do it."
        )
        return

    for group in removable:
        run(DOCKER, "rm", "-f", *[c["Id"] for c in group["containers"]])
        if group["project"]:
            label = f"label=com.docker.compose.project={group['project']}"
            networks = run(DOCKER, "network", "ls", "-q", "--filter", label).split()
            if networks:
                run(DOCKER, "network", "rm", *networks)
        print(f"removed  {group['name']}")
    for group in idle:
        run(DOCKER, "stop", *[c["Id"] for c in group["containers"] if c["State"]["Running"]])
        print(f"stopped  {group['name']}")


if __name__ == "__main__":
    main()
