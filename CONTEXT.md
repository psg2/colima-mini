# Colima Mini

Colima Mini is a native macOS dashboard and menu bar panel for Docker on the default Colima profile.

## Language

**Project**:
The containers that share one `com.docker.compose.project` label, or else one **Testcontainers session**. Other containers belong to **Standalone**.
_Avoid_: Stack, app, group

**Testcontainers session**:
The containers that share one `org.testcontainers.session-id` label, shown as the project `testcontainers <first 8 characters>`. Its **Ryuk** container, `testcontainers-ryuk-<session-id>` from the `testcontainers/ryuk` image, removes them once its clients disconnect.
_Avoid_: Test project

**Owner labels**:
Labels any tool can set on a container to name its owner. Colima Mini reads them; it never sets them.
- `dev.owner.working_dir`: the folder the container was created for. It is the container's **Origin** when Compose recorded none.
- `dev.owner.pid`: the PID, on this Mac, of the process that created the container. A missing, malformed or reused PID reads as alive.
_Avoid_: Owner tags

**Origin**:
Where a project ran: a folder, or a worktree created by Claude, Codex, Conductor or Orca. Read from the `com.docker.compose.project.working_dir` label, else `dev.owner.working_dir`.
_Avoid_: Path, source

**Orphaned project**:
A project whose origin folder no longer exists.
_Avoid_: Dead project, stale project

**Orphaned container**:
A container whose owner is gone: its origin folder no longer exists, its `dev.owner.pid` process exited, or its **Testcontainers session** has no running Ryuk (unless a live owner PID vouches for it). Nothing will ever remove it.
_Avoid_: Leaked container, zombie

**Unused containers**:
The result of a scan that gives each project a verdict: owner gone (orphaned), stopped for over a day, idle, quiet, or in use. Orphaned containers of a project that is otherwise alive form their own group. The scan changes nothing.
_Avoid_: Sweep (the code's internal name)

**Background scan**:
The unused-container scan run on a timer (every 15 minutes by default, never in **Sample mode**). New orphaned containers, or Colima CPU above 80% of its cores for 5 minutes, mark the menu bar and notify; both open the review. It never removes anything.
_Avoid_: Auto-cleanup

**Reclaim space**:
A preview of removable Docker objects by kind, followed by a confirmed removal of exactly the listed items. Never includes named volumes.
_Avoid_: Prune, cleanup

**Sample mode**:
The app running on a fixture file instead of the real runtime. It never runs a mutation.
_Avoid_: Demo, mock mode
