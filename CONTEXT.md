# Colima Mini

Colima Mini is a native macOS dashboard and menu bar panel for Docker on the default Colima profile.

## Language

**Project**:
The containers that share one `com.docker.compose.project` label. Containers without one belong to **Standalone**.
_Avoid_: Stack, app, group

**Origin**:
Where Compose ran a project: a folder, or a worktree created by Claude, Codex, Conductor or Orca. Read from the `com.docker.compose.project.working_dir` label.
_Avoid_: Path, source

**Orphaned project**:
A project whose origin folder no longer exists.
_Avoid_: Dead project, stale project

**Unused containers**:
The result of a scan that gives each project a verdict: folder deleted, stopped for over a day, idle, quiet, or in use. The scan changes nothing.
_Avoid_: Sweep (the code's internal name)

**Reclaim space**:
A preview of removable Docker objects by kind, followed by a confirmed removal of exactly the listed items. Never includes named volumes.
_Avoid_: Prune, cleanup

**Sample mode**:
The app running on a fixture file instead of the real runtime. It never runs a mutation.
_Avoid_: Demo, mock mode
