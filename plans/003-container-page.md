# Plan 003: Open containers on a dedicated diagnosis page

> **Executor instructions:** Read the entire plan before editing. Follow the steps and verification gates. Stop and report on a STOP condition. Update this plan's row in `plans/README.md` when done.
>
> **Drift check (run first):** `git diff --stat ecf0266ff731f93f7cfa95c3d2f13f505b4d725c..HEAD -- Sources/ColimaCore/Backend.swift Sources/ColimaCore/Command.swift Sources/ColimaCore/Models/ Sources/ColimaCore/Fixture.swift Sources/ColimaAppState/ Sources/ColimaMini/Views/ Tests/ColimaCoreTests/ Tests/ColimaAppStateTests/ README.md`. Compare changed files against the current-state excerpts. Changes explicitly required by dependency plans are expected; verify their listed postconditions. Unexplained drift or conflicting behavior is a STOP condition.

## Status

- Priority: P1
- Effort: L
- Risk: MED
- Depends on: 002-navigation.md
- Category: direction
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
- `Sources/ColimaCore/Command.swift`
- `Sources/ColimaCore/Models/`
- `Sources/ColimaCore/Fixture.swift`
- `Sources/ColimaAppState/`
- `Sources/ColimaMini/Views/`
- `Tests/ColimaCoreTests/`
- `Tests/ColimaAppStateTests/`
- `README.md`
- This plan's status row in `plans/README.md`.

Do not modify other projects, dotfiles, installed apps, actual Colima configuration, runtime/container/volume state, CI, release tags, dependency versions or the app logo. No automatic cleanup. No private logs, environment dumps or credentials in tests or evidence.

## Why this matters

Logs deserve the width and height of the selected task. Moving the existing bottom pane alone would preserve reordered stdout/stderr, unnecessary polling and slow cancellation. Build an object page with explicit loading/error/lifecycle behavior.

## Current state

At the audit SHA, DashboardView.swift:195–257 implements the selected bottom pane. Its task at :184–192 fetches logs every refreshInterval for any selected container, including Ports. Command.swift:104–105 concatenates stdout then stderr specifically when arguments look like Docker logs. Backend.logs:74–76 requests `logs --timestamps --tail 200`. Container.endpoints:37–47 guesses HTTP for every matched published TCP port except container port 443. BackendTests:115–120 checks stream presence but not chronology.

Plan 002 supplies typed container routes, origin context and a testable application-state target. Read its actual interface before editing; do not recreate selected-ID navigation separately.

## Design contract

Container page: Back/breadcrumb, service/container name, image, status and lifecycle actions at top. Tabs Overview / Logs / Ports / Mounts. Overview contains structured health/state details and a concise project/service/data relationship strip. Logs uses the main content area with Live/Pause, Follow latest, timestamps, search and Copy visible logs. Searching freezes automatic follow without losing the user's position. Limit retention and state the loaded range. Do not label a refresh-only buffer as an unbounded live stream.

Ports shows host address → container port/protocol. TCP does not imply HTTP: a PostgreSQL port must get Copy address, not an invented browser URL. Open in browser should be explicit HTTP(S), e.g. a user-chosen action or stored scheme preference; do not silently infer application protocol from a port number. Mounts uses typed names/types/destination/read-only flags and later links to plan 004. Linux mount paths are not Finder URLs. Avoid displaying all raw inspect JSON/environment by default.

## Steps

### 1. Establish chronological log and cancellation contracts

Give Command an explicit output policy, independent of argv string matching. For logs, capture a shared combined output file when suitable, or merge timestamped records with stable tie handling and multiline preservation at a log boundary. Do not lose stderr content, change ordinary command diagnostic behavior, or parse/rewrite message bodies. Make cancellation wake a waiting command and start the existing bounded termination grace immediately; canceled tasks must not wait until the original 15/45-second deadline. Preserve private temporary files, timeout caps and cleanup.

**Verify:** `swift test --filter CommandTests` and `swift test --filter BackendTests` → existing and new chronological/cancellation cases pass, including a local child that ignores TERM. No real Docker mutations.

### 2. Add structured container detail reads

Add a typed ContainerDetails model and Backend read for a specific full ID. Only decode needed fields: state/health/exit code/OOM flag, image identity, start/restart information, structured port bindings and mounts. Retrieve on page entry; use a bounded refresh for health if needed. Do not inspect every container on every list render. Distinguish unavailable/missing fields from zero or healthy. Extend Fixture with optional details so existing fixtures still decode. New synthetic data must contain mounts, a database TCP port, an HTTP port and an exited/OOM example.

**Verify:** `swift test` → fixture compatibility and detail-decoding tests pass; unknown fields and absent health checks remain supported. Fake runtime with removed ID produces a useful not-found result, not stale detail data.

### 3. Build the container page and scoped log session

Create ContainerDetailView and small tab views within Views. Remove the bottom details pane and its task from DashboardView once the route works. Fetch logs only while this container's Logs tab is visible and live refresh is enabled; pause while inactive or back off explicitly. Page leave/container switch cancels pending reads; returning loads current data. On repeated failures show a retained last-good buffer with a stale marker and a separate error, not error text disguised as a matching log line. Preserve search/scroll while new logs arrive. Avoid a streaming-process redesign in this plan; bounded polling is acceptable if accurately labeled.

**Verify:** `swift test` → state cases for page/tab leave, late previous-ID logs, pause/resume, not-found and visible error pass. `./Scripts/build-app.sh` → exit 0; direct Sample launch shows a full page and usable large log area.

### 4. Connect ports, mounts and navigation

Add Overview/Ports/Mounts and route-aware Back. Preserve list filters, collapse state and scroll on return. Mount links show the correct volume only when metadata identifies a named volume; bind mounts remain a distinct type. Until 004 is implemented, volume navigation may show metadata with an honest unavailable inventory state. Existing Start/Stop/Restart still use confirmation and are disabled in sample mode. Open project folder should remain usable in real mode when the verified host folder exists; it must not be grouped under mutation-disabled controls unnecessarily.

**Verify:** `./Scripts/check.sh && ./Scripts/build-app.sh && ./Scripts/test-app.sh` → exit 0. Synthetic manual scenarios: open postgres → Logs → search/Pause → Ports (no PostgreSQL browser link) → Mounts → Back; return state intact. Check 920×580, light/dark, keyboard and accessible tab labels.

## Test plan

Chronology regression: fake logs writes alternating timestamped stdout/stderr, equal timestamps and multiline messages; Backend.logs retains order and content. Cancellation regression: cancel a TERM-ignoring child with a much longer deadline; assert CancellationError and bounded child exit/temporary cleanup, using generous scheduling tolerance. Details tests assert meaningful decoded states/ports/mounts rather than JSON formatting. State tests observe no stale logs after selection/route changes, no new fetches while paused/hidden, and a fresh buffer on return. Use controlled completion or local helper state; never sleep exact 5 seconds to prove polling.

## Done criteria

- [ ] Checks, build and package tests pass.
- [ ] Selecting a container opens a full page; no persistent bottom log pane remains.
- [ ] Mixed-stream chronological logs and bounded cancellation tests pass.
- [ ] Logs task stops outside visible/live Logs; old results cannot replace the current page.
- [ ] Database address/protocol stays accurate; no HTTP URL is invented.
- [ ] Missing/removed container and unavailable inspection have useful visible states.
- [ ] Back restores originating project/filter/collapse/scroll context.
- [ ] Native synthetic flow and scope/index status verified.

## STOP conditions

Stop if reliable stream ordering cannot be maintained with bounded output, process cancellation needs unsafe global killing, details require new runtime privileges/dependencies, raw environment secrets enter fixtures/evidence, or a test gate fails twice. Embedded terminal, arbitrary exec, filesystem editing, multi-profile support and a streaming engine-events redesign are outside scope.

## Maintenance notes

History and log retention need explicit bounds. CPU row convention remains Docker's 100% per core; overall VM normalization must be labeled separately. New inspect fields must be optional/typed and avoid sensitive environment dumps. A future terminal should be a separate capability with its own process/input lifecycle.
