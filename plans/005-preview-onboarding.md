# Plan 005: Launch reliable synthetic previews and document first opening

> **Executor instructions:** Read the entire plan before editing. Follow the steps and verification gates. Stop and report on a STOP condition. Update this plan's row in `plans/README.md` when done.
>
> **Drift check (run first):** `git diff --stat ecf0266ff731f93f7cfa95c3d2f13f505b4d725c..HEAD -- Scripts/run.sh README.md docs/release-notes.md`. Compare changed files against the current-state excerpts. Changes explicitly required by dependency plans are expected; verify their listed postconditions. Unexplained drift or conflicting behavior is a STOP condition.

## Status

- Priority: P2
- Effort: S
- Risk: LOW
- Depends on: none
- Category: dx
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

- `Scripts/run.sh`
- `README.md`
- `docs/release-notes.md`
- This plan's status row in `plans/README.md`.

Do not modify other projects, dotfiles, installed apps, actual Colima configuration, runtime/container/volume state, CI, release tags, dependency versions or the app logo. No automatic cleanup. No private logs, environment dumps or credentials in tests or evidence.

## Why this matters

The documented fixture command can reuse an already-running real app instead of starting Sample mode. Release notes also promise first-open instructions that do not exist. Resolve these small onboarding gaps so screenshots and public installs have a trustworthy starting point.

## Current state

`Scripts/run.sh:4–5`:

```bash
"$ROOT/Scripts/build-app.sh" >/dev/null
open "$ROOT/dist/Colima Mini.app" --args "$@"
```

`ColimaMiniApp.swift:24–26` evaluates fixture mode only at process initialization. README:79–85 recommends the launcher for synthetic data. The installed open(1) manual states -n creates a new app instance, even if one is running; --args supplies main arguments. README:29–35 documents download/move and ad-hoc signing but no first-open procedure. docs/release-notes.md:9–11 promises such instructions.

## Steps

### 1. Isolate fixture launches

Detect a fixture preview in the launcher and use a distinct process/LaunchServices new-instance option for that preview. Preserve ordinary real launches. Preserve quoting and arguments with spaces; do not parse/rebuild arbitrary arguments unsafely. No installed real process should need to be quit or killed to preview synthetic data.

**Verify:** `bash -n Scripts/run.sh` → exit 0. `./Scripts/check.sh && ./Scripts/build-app.sh && ./Scripts/test-app.sh` → exit 0.

### 2. Document the app-specific first-open procedure

Link Apple's current per-app instructions after attempting first launch, describe the ad-hoc/no-notarization limitation, include checksum verification using the release .sha256 file and retain the local-build alternative. Do not recommend globally disabling Gatekeeper or stripping quarantine recursively. Remove any release-note promise not actually fulfilled by the README.

**Verify:** `git diff --check` → exit 0; manually follow every added instruction with a downloaded artifact when an isolated test environment is available. If the clean-download path is unavailable, report that manual gap; a local build does not prove it.

### 3. Validate simultaneous real and Sample instances

With an already-running real dashboard, run the documented fixture launcher. A distinct process/window must show Sample and synthetic inventory, with all runtime writes disabled. The real process must remain live, unchanged and independently identifiable. Close only the synthetic process afterward. Record synthetic screenshots only if requested for publication; do not include private runtime logs or paths.

**Verify:** observable process/window identities and Sample title/disabled controls match the expected result. No runtime action was invoked. `git diff --name-only` → scoped files only.

## Test plan

No source-text assertions for this shell flag. The meaningful regression check is simultaneous native instances: correct mode/title, sample inventory and disabled mutation controls despite a preexisting real instance. Existing package tests protect fixture summaries; document the native manual check rather than add a tautological test that asserts -n appears in a script.

## Done criteria

- [ ] Existing checks/build/package validation pass.
- [ ] Fixture preview starts a distinct Sample instance while the real app is already running.
- [ ] Real runtime/process state remains unchanged.
- [ ] First-open instructions exist and release-note link lands on them.
- [ ] Gatekeeper remains enabled; limitations/manual gaps recorded.
- [ ] Scope/index status reviewed.

## STOP conditions

Stop if LaunchServices still reuses the real process, two mode identities cannot be distinguished, verifying a download would require changing global security settings, or verification fails twice. Signing/notarization services, certificates and release publication are outside scope.

## Maintenance notes

Native first-open alert wording changes across macOS versions. Cite Apple and describe the per-app flow rather than promising an exact alert string. Future UI smoke tooling should always label fixture mode and identify its process explicitly.

Reference: [Apple: Safely open apps on your Mac](https://support.apple.com/en-us/102445).
