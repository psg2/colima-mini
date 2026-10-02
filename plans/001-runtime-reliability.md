# Plan 001: Report scan failures and restore the authoritative running set

> **Executor instructions:** Read the entire plan before editing. Follow the steps and verification gates. Stop and report on a STOP condition. Update this plan's row in `plans/README.md` when done.
>
> **Drift check (run first):** `git diff --stat ecf0266ff731f93f7cfa95c3d2f13f505b4d725c..HEAD -- Sources/ColimaCore/Backend.swift Sources/ColimaCore/Resources/docker-sweep.py Tests/ColimaCoreTests/BackendTests.swift Scripts/test-sweep.sh Tests/SweepHelpers/ README.md`. Compare changed files against the current-state excerpts. Changes explicitly required by dependency plans are expected; verify their listed postconditions. Unexplained drift or conflicting behavior is a STOP condition.

## Status

- Priority: P1
- Effort: M
- Risk: MED
- Depends on: none
- Category: bug
- Planned at: `ecf0266ff731f93f7cfa95c3d2f13f505b4d725c`, 2026-10-02
- State: DONE — executed 2026-10-02; validation recorded in plans/README.md

## Repository contract

Repository: `/Users/sereno/workspace/psg2/colima-mini`, public `https://github.com/psg2/colima-mini`. Native macOS 14+ SwiftUI/AppKit; Swift 6 toolchain, Swift 5 language mode, SwiftPM. No third-party Swift dependencies. Core uses Foundation, package access and two-space formatting; match `Sources/ColimaCore/Backend.swift`. UI state is MainActor. Preserve the default Colima profile and explicit Docker context `colima`, foreign Docker environment scrubbing, sample-mode mutation guards and report-only cleanup. Keep the user's current 10 CPUs / 20 GiB. CPU/RAM application still requires the existing confirmation. Code and comments are English.

## Commands you will need

Run from the repository root. No dependency installation is needed.

| Purpose | Command | Expected result |
|---|---|---|
| Baseline and final checks | `./Scripts/check.sh` | exit 0: Swift format lint, XCTest, sweep scenarios, shell/Python syntax |
| Build app | `./Scripts/build-app.sh` | exit 0; `dist/Colima Mini.app` exists |
| Packaged checks | `./Scripts/test-app.sh` | exit 0; fixture summary, resource and relocated scanner checks pass |
| Synthetic preview | `./Scripts/run.sh --fixture "$PWD/Tests/ColimaCoreTests/Fixtures/sample.json"` | separate Sample instance, once plan 005 is implemented; otherwise launch its executable directly |
| Direct synthetic preview | `"dist/Colima Mini.app/Contents/MacOS/ColimaMini" --fixture "$PWD/Tests/ColimaCoreTests/Fixtures/sample.json"` | Sample window; runtime mutations disabled |
| Review scope | `git diff --name-only` and `git status --short` | only explicitly scoped files and plan status changed |

## Git workflow

Use a `codex/` branch and commits describing observable behavior (history example: `Isolate backend tests from executable overrides`). Do not push or open a PR unless the operator instructs it. If a PR is requested, open ready for review, write English title/body using Why / What changed / Validation / Visual evidence, apply unslop, include only synthetic screenshot evidence and monitor CI/review comments. Do not merge without an explicit request.

## Scope

Only modify these paths (directories mean new files narrowly serving the named feature):

- `Sources/ColimaCore/Backend.swift`
- `Sources/ColimaCore/Resources/docker-sweep.py`
- `Tests/ColimaCoreTests/BackendTests.swift`
- `Scripts/test-sweep.sh`
- `Tests/SweepHelpers/`
- `README.md`
- This plan's status row in `plans/README.md`.

Do not modify other projects, dotfiles, installed apps, actual Colima configuration, runtime/container/volume state, CI, release tags, dependency versions or the app logo. No automatic cleanup. No private logs, environment dumps or credentials in tests or evidence.

## Why this matters

A failed Docker command currently looks like a successful empty cleanup report. Applying resources uses the last dashboard snapshot to choose containers to restore, which can disagree with recent terminal activity. Correct these boundaries before making the report and resource controls more prominent.

## Current state

`Sources/ColimaCore/Resources/docker-sweep.py:41–42`:

```python
def run(*args, stderr=subprocess.DEVNULL):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=stderr, text=True).stdout.strip()
```

`Backend.swift:42–46` saves configuration, stops the VM if `snapshot.vm.running`, then starts it. At `:55–57` it derives `previouslyRunning` from the caller-supplied snapshot. `Backend.sweep:96–101` passes only `--sample 2` to the bundled scanner. Keep that report-only invocation.

`Tests/ColimaCoreTests/BackendTests.swift:9–80` creates a real temporary executable runtime backed by JSON state. This is the testing pattern: assert final VM/container states, not exact internal calls. `Scripts/test-sweep.sh` already exercises CLI reports with local fake tools; extend those fakes for failures.

## Steps

### 1. Distinguish failed probes from empty successful results

Give the helper checked subprocess results. Mandatory Docker inventory failures must exit nonzero with a concise useful diagnostic. A successful empty inventory may still say No containers. Treat unavailable optional client/traffic observations as unknown and withhold idle verdicts dependent on them. lsof's no-match exit is expected absence, distinct from an invocation failure. Check cleanup results in the helper's existing standalone CLI path; the app continues to expose report only. Do not synchronize the separate dotfiles helper as part of this plan.

**Verify:** `./Scripts/test-sweep.sh` → existing scenarios plus failed inventory/activity cases pass. `DOCKER_SWEEP_DOCKER=/usr/bin/false python3 Sources/ColimaCore/Resources/docker-sweep.py --sample 0` → nonzero and an error, never a successful No containers report. This command contacts no Docker engine.

### 2. Capture current state at the restart boundary

Inside Backend.apply, fetch authoritative default VM/container inventory immediately before stopping. Capture running IDs independently of optional stats. Respect already-stopped VM behavior. Restore only that captured set after verified restart; do not restart a container merely because the old UI snapshot said it ran. Verify the captured IDs are running afterward. Missing/deleted or unrestored IDs must produce a partial-restoration diagnostic rather than unconditional success. Do not retry destructive actions blindly or invent automatic rollback.

**Verify:** `swift test --filter BackendTests` → existing restoration/save/context/log tests plus new stale-input and partial-restoration tests pass.

### 3. Document the resulting outcomes

Update README restoration wording to the mutation-time inventory. Explain failed/partial scan probes and report-only behavior concisely. Keep fixture examples synthetic and preserve explicit context/environment isolation.

**Verify:** `./Scripts/check.sh && ./Scripts/build-app.sh && ./Scripts/test-app.sh` → all exit 0. Inspect `git diff --name-only` → scoped paths only.

## Test plan

Regression cases: failing Docker inventory is not empty success; missing lsof results do not prove no clients; failed traffic probes do not prove idleness; standalone helper does not claim a rejected fake cleanup succeeded. All mutation tests use fake Docker. For resources, change fake runtime state after taking the old UI snapshot: one formerly running container is stopped and another starts. After applying, restore the current running set, keep the manually stopped one stopped, and report a missing or failed restoration. Preserve Save for next start's non-interruption contract.

## Done criteria

- [ ] Checks, package build and relocated scanner checks exit 0.
- [ ] A failed fake Docker scan exits nonzero with a useful error.
- [ ] External state changes before fake restart produce correct final running IDs.
- [ ] Partial restoration cannot produce the UI's unconditional success message.
- [ ] No live VM restart, cleanup or volume mutation was used for automated verification.
- [ ] Scope and index status verified.

## STOP conditions

Stop if scanner probes cannot distinguish normal empty observations from errors, inventory requires exposing environment secrets, restart semantics require an unrelated profile/config change, or a verification fails twice. If live restart validation is needed, report the remaining manual gap; do not interrupt the user's current workloads as an audit follow-up.

## Maintenance notes

Optional probes need explicit unknown semantics as more activity signals are added. Docker or Colima CLI schema changes should fail usefully. Reviewer should scrutinize restoration of terminal-started/stopped containers and the guarantee that app cleanup stays report-only.
