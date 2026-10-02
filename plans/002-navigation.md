# Plan 002: Align the sidebar and expose group controls directly

> **Executor instructions:** Read the entire plan before editing. Follow the steps and verification gates. Stop and report on a STOP condition. Update this plan's row in `plans/README.md` when done.
>
> **Drift check (run first):** `git diff --stat ecf0266ff731f93f7cfa95c3d2f13f505b4d725c..HEAD -- Package.swift Sources/ColimaMini/State/Dashboard.swift Sources/ColimaAppState/ Sources/ColimaMini/ColimaMiniApp.swift Sources/ColimaMini/Views/ Tests/ColimaAppStateTests/ README.md`. Compare changed files against the current-state excerpts. Changes explicitly required by dependency plans are expected; verify their listed postconditions. Unexplained drift or conflicting behavior is a STOP condition.

## Status

- Priority: P1
- Effort: M
- Risk: MED
- Depends on: 001-runtime-reliability.md
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

- `Package.swift`
- `Sources/ColimaMini/State/Dashboard.swift`
- `Sources/ColimaAppState/`
- `Sources/ColimaMini/ColimaMiniApp.swift`
- `Sources/ColimaMini/Views/`
- `Tests/ColimaAppStateTests/`
- `README.md`
- This plan's status row in `plans/README.md`.

Do not modify other projects, dotfiles, installed apps, actual Colima configuration, runtime/container/volume state, CI, release tags, dependency versions or the app logo. No automatic cleanup. No private logs, environment dumps or credentials in tests or evidence.

## Why this matters

The Groups dropdown adds an extra step to a basic action. Footer buttons do not align with sidebar navigation, and every container selection reserves a bottom pane. Introduce a clear route model and aligned shell, with behavioral state coverage protecting refresh and navigation during the refactor.

## Current state

`DashboardView.swift:45–72` has `List(selection: $model.project)` followed by separately padded Unused containers and Settings buttons. `:104–114` has `Menu("Groups")`. `:127–130` has a VSplitView containing ContainerList and containerDetail. `ContainerRow.swift:12–14` sets selectedID. `ProjectSection.swift:11–17` forces expanded groups when search is nonempty.

`Dashboard.swift:87–94`:

```swift
func refresh() async {
  guard !refreshing, !busy else { return }
  refreshing = true
  defer { refreshing = false }
  let updated = try await backend.snapshot() // within do/catch
  guard !Task.isCancelled else { return }
  snapshot = updated
}
```

`perform:131–146` mutates without invalidating a prior refresh. Package.swift currently tests only ColimaCore. No AppState target exists yet. Use package access as demonstrated in Backend; keep ObservableObject state on MainActor. Move only presentation state into a small ColimaAppState library target, add its test target, and import it from current app consumers. Do not split every view into a separate package.

## Design contract

Primary sidebar rows: Containers, Volumes, Storage. Projects form a named section below. Settings uses the same row height, leading icon slot and text alignment, pinned at the bottom. Unused containers belongs to Storage as Review unused containers, not an orphan sidebar button. Keep Command+, and menu bar Settings opening the existing Settings scene. Volumes/Storage initially show truthful not-yet-available screens until plan 004; never fabricated runtime numbers.

One visible Collapse all / Expand all control applies to visible groups. If any visible group is expanded, it says Collapse all. If every visible group is collapsed, it says Expand all. Hide in flat mode. Each group retains its chevron. Search temporarily reveals matches, disables collapse with a clear explanation, and restores saved collapse state on clearing. Project actions must explicitly target either all project containers or displayed containers; retain the documented displayed scope until a separate change is chosen.

Container route includes an ID and an origin list context. Use Back to restore project/filter/collapse/scroll state. The signature relationship strip comes in plan 003/004. Use semantic native colors, quiet separators, compact metric text and existing llama assets. Native controls, SF Pro body, restrained rounded titles and SF Mono data; maintain light/dark/high-contrast support. The HTML preview is a study, not code to port literally.

## Steps

### 1. Isolate observable state and protect mutation ordering

Move Dashboard and PendingAction to ColimaAppState with package access. Add typed routes for containers/project/container ID/volumes/volume name/storage; keep settings as native scene presentation. Introduce a refresh generation or coordinator so snapshots begun before a mutation cannot publish afterward and a post-action refresh is guaranteed. Prefer controlled local runtime helpers like BackendTests; add a narrow async collaborator only if needed to deterministically hold completions. Tests assert resulting visible state/routes/errors, not private fields or exact call sequences.

**Verify:** `swift test` → existing tests plus state cases pass; `swift build` → app consumers compile with the new target. At least one delayed-refresh test fails on the old behavior and passes after coordination.

### 2. Rebuild the shell navigation and direct group control

Extract a small sidebar/shell view as needed within Views. Keep stable row alignment and native selection styling. Replace Groups with the direct stateful control and meaningful accessibility labels/IDs. Add the route shell while preserving existing details temporarily if necessary; switch container rows to route navigation in plan 003. Storage report navigation still invokes the existing report-only scanner, with busy/error states from plan 001. Ensure MenuView opens the correct Containers/project route after previously visiting another page.

**Verify:** `./Scripts/check.sh` → exit 0. Build with `./Scripts/build-app.sh`, start the direct synthetic preview command and inspect: exactly one direct global group control; footer Settings aligns with primary rows; storage report is reachable; menu project opens its project list. No runtime mutations in Sample.

### 3. Verify return/filter behavior and update usage docs

Test collapsed/expanded/mixed groups, no matches, standalone containers, long project names and running-only filters. Verify at minimum supported window size 920×580 and usual size 1120×740; also light/dark and keyboard focus. Maintain selection-independent route behavior when a container disappears: a useful Container no longer exists state with Back, not a crash or silent unrelated selection.

**Verify:** `./Scripts/check.sh && ./Scripts/build-app.sh && ./Scripts/test-app.sh` → exit 0. Record the synthetic native scenarios and scope review in the executor report; no screenshot of real logs.

## Test plan

Use ColimaAppStateTests to observe navigation and state results: delayed pre-stop snapshot cannot make a stopped container appear running; failed actions keep visible errors; disappeared container has a recoverable route; menu/project navigation restores the correct view. Test group-toggle behavior at its public state boundary: mixed groups collapse, all collapsed expand, search does not erase preferences. Returning from detail restores filters and collapse state. Native accessibility/manual checks cover alignment and keyboard focus; do not assert source strings, view implementation structure or mock configuration.

## Done criteria

- [ ] Checks/build/package checks pass.
- [ ] Sidebar rows align in the native app and have keyboard focus.
- [ ] Global expand/collapse is one visible action; individual chevrons work.
- [ ] Filter clearing restores saved collapsed groups.
- [ ] Stale refresh completions cannot overwrite a completed action.
- [ ] AppState tests cover observable route/error/removal behavior.
- [ ] Menu and Command+, still work; sample guards remain active.
- [ ] Scope/index status reviewed.

## STOP conditions

Stop if public state extraction needs a third-party package, fixture mode loses mutation guards, menu and dashboard disagree about the selected route, restoration requires changing project-action semantics, or verification fails twice. Dependencies can change existing excerpts; compare against their explicit outcomes, not guessed code.

## Maintenance notes

Route identity should use IDs, not visible labels such as All containers. Back context belongs to navigation state. Independent storage/loading state must not reuse the dashboard-wide busy flag for reads. Future pages should not recreate polling loops in every view.
