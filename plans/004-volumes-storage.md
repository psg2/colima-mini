# Plan 004: Expose volume relationships and honest disk measurements

> **Executor instructions:** Read the entire plan before editing. Follow the steps and verification gates. Stop and report on a STOP condition. Update this plan's row in `plans/README.md` when done.
>
> **Drift check (run first):** `git diff --stat ecf0266ff731f93f7cfa95c3d2f13f505b4d725c..HEAD -- Sources/ColimaCore/Backend.swift Sources/ColimaCore/Models/ Sources/ColimaCore/Fixture.swift Sources/ColimaAppState/ Sources/ColimaMini/Views/ Tests/ColimaCoreTests/ Tests/ColimaAppStateTests/ README.md`. Compare changed files against the current-state excerpts. Changes explicitly required by dependency plans are expected; verify their listed postconditions. Unexplained drift or conflicting behavior is a STOP condition.

## Status

- Priority: P1
- Effort: L
- Risk: MED
- Depends on: 002-navigation.md, 003-container-page.md
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

Database data currently has no visible volume relationship, and the app omits disk usage. A 100 GiB virtual disk limit is different from used VM space or host file allocation. Build Storage as an independently refreshed data surface, with definitions clear enough to guide real decisions.

## Current state and verified schema

Backend.snapshot:65–72 has no volume/storage queries. VM.swift:3–7 decodes name/status/cpus/memory only; live `colima list --json` also supplies `disk` as bytes. ResourceOverview.swift:10–26 currently shows CPU/memory/ports. Plan 002 supplies sidebar routes, and 003 supplies typed container mounts.

Verified read-only commands on this machine:

```sh
colima list --json
docker --context colima system df --format '{{json .}}'
docker --context colima system df --verbose --format '{{json .}}'
colima ssh -- df -B1 / /var/lib/docker
```

Summary is JSON lines with Type/Size/Reclaimable/TotalCount/Active strings. Verbose is one JSON object with Images/Containers/Volumes/BuildCache arrays. Volume entries include Name/Driver/Links/Size/Labels/Mountpoint as strings. Image entries include Size/SharedSize/UniqueSize/Containers. This format is verified for the installed CLI, not a cross-version promise: unknown schemas should produce a section error, not zeros. For exact volume creation/options, use scoped volume inspect reads and decode only needed metadata.

Audit measurements: configured data disk 100 GiB; filesystem size ~97.87 GiB, used ~8.53 GiB, available ~84.33 GiB; host data+OS image allocated blocks ~20.35 GiB. The OS image logical capacity is another 20 GiB. Current default paths observed: `~/.colima/_lima/colima/disk` and `~/.colima/_lima/_disks/colima/datadisk`. These are evidence for discovery, not paths to hard-code as universal. Respect COLIMA_HOME and treat unsupported runtime layouts as unavailable.

## Data and design contract

Volumes list: name, type/driver, project association when available, measured size or Unknown, references including stopped containers, search/sort, attached/unattached filter. Volume page: metadata and attached containers with mount destinations, linking back to container pages. Bind mounts are distinct from named volumes; Linux Mountpoint is not a Mac folder. Unattached does not mean safe to delete. Start with read-only volume inspection, no volume remove/edit/clone/backup.

Storage separates: (1) configured image capacity from Colima; (2) VM data filesystem size/used/available with reserved/metadata distinction; (3) daemon image/container/volume/cache sizes and reclaimable estimates; (4) physical image-block footprint on the Mac, independently labeled. Use byte values internally and explicit units. Do not add image layer virtual sizes and call it physical total, double-count shared layers, or promise reclaimable Docker bytes will immediately shrink sparse host files. Finder/backup/clone in OrbStack depend on its runtime, not just UI design.

## Steps

### 1. Spike the read-only providers and settle their contracts

Confirm the summary/verbose JSON schema with commands above, filtering output to required fields and avoiding container Command/environment details in evidence. Test a stopped VM and daemon failure using fakes, not a real stop. Confirm disk path discovery for default COLIMA_HOME and configured overrides. For unknown Lima/VZ/disk layouts, design an Unavailable host-footprint value. Derive filesystem bytes with locale-stable output and identify the Docker data mount, not root alone. Record assumptions in README. Do not start a VM just to read storage.

**Verify:** scoped fake providers decode synthetic summary/verbose/df output and unsupported layouts return Unavailable. `swift test` → pass. If schema/path compatibility cannot be resolved, STOP with the spike result before building misleading charts.

### 2. Add typed volume/storage models and independent backend reads

Add optional disk capacity to VM without breaking old fixtures. Store independently timed StorageSnapshot and Volume inventory, with section-level errors/staleness. Byte parsing must support decimal Docker units and binary display; reuse/extend Usage conversion only if its public meaning fits. Batch reads rather than one inspect per row every poll. Correlate volumes with all existing containers' structured mounts, including stopped containers. Distinguish no references from missing reference data. Host footprint should use allocated block metadata for discovered image files, not logical file size; sum only clearly identified non-overlapping images and document shared-allocation limits.

**Verify:** `swift test` → old fixtures still pass plus decimal/binary sizes, shared layers, unknown size, stopped-container references, malformed output, separate data/root mounts and sparse-size tests.

### 3. Implement volume pages and cross-navigation

Create VolumesView/VolumeDetailView with aligned native list rows and a relationship strip (`volume → mount destination → container`). Support no volumes, daemon unavailable, unknown driver size and stale inventory. Keep selection valid when volume disappears; show useful Back state. Link named mounts from container page and attached containers from volume page. No delete/prune button in this phase.

**Verify:** build and direct Sample launch → filter Attached/Unattached, open demo_db, follow postgres, return to the original volume context; a stopped attached container must never become Unattached. `swift test` → navigation/state cases pass.

### 4. Implement Storage and move the cleanup report into it

Use one capacity meter with clearly labeled configured limit and filesystem used/available; follow with a quiet table of Docker categories and reclaimable estimates. Show host footprint separately. Fetch expensive daemon accounting on entering the page and on explicit Refresh, or a slow cadence such as 60 seconds only while visible. Container actions remain responsive if storage fails or times out. Integrate Review unused containers using the report-only scanner, explicit errors from 001 and uncertainty explanations. Store no persistent private inventory dump.

**Verify:** `./Scripts/check.sh && ./Scripts/build-app.sh && ./Scripts/test-app.sh` → exit 0. Synthetic scenarios: slow storage does not freeze container navigation; partial disk failure leaves volume data usable; unknown footprint displays Unavailable; sample cleanup has no runtime writes. Read-only live comparison may use the verified commands, without writing real data into screenshots.

## Test plan

Test parsing/correlation through public model/backend boundaries. Include Docker decimal 1.976GB vs GiB conversion, malformed/unsupported JSON, volume used by a stopped container, missing mount metadata, a plugin volume without measured size, absent disk in an old fixture, data filesystem separate from root, configured capacity greater than filesystem size, sparse logical bytes greater than allocated bytes and unsupported image discovery. UI state should retain last-good data with timestamps and section errors rather than reset to a false zero. No tests merely inspect mock commands or repeat formulas from production code.

## Done criteria

- [ ] Provider spike assumptions documented; unsupported data is explicit.
- [ ] Checks/build/package checks pass with old and expanded fixtures.
- [ ] Volume use includes stopped containers; named/bind mounts are separate.
- [ ] Container ↔ volume navigation preserves origin context.
- [ ] Configured capacity, filesystem use and Mac footprint have different labels and providers.
- [ ] Docker reclaimable numbers are estimates, without volume-safety claims or shared-layer double counts.
- [ ] Storage failure cannot prevent normal container controls.
- [ ] No automatic prune, volume mutation, VM resize or restart was performed.
- [ ] Scope/index status reviewed.

## STOP conditions

Stop on unsupported storage schema without a truthful fallback, inability to identify data vs root filesystem, a need for sudo or privileged helpers, unavailable disk-image discovery being treated as zero, or two failed gates. Disk shrinking/resizing/compaction, file browsing, consistent database backup, images CRUD, network CRUD and multi-profile support are outside scope.

## Maintenance notes

Disk-file allocation is an estimate under APFS sharing/compression; do not market it as guaranteed exclusive host bytes. Plugin volumes may not expose size. Docker version/schema differences must be isolated in providers. A later cleanup design must preview exact objects and protect persistent volume data separately.

References: [Docker disk accounting](https://docs.docker.com/reference/cli/docker/system/df/), [Docker volumes UI](https://docs.docker.com/desktop/use-desktop/volumes/), [OrbStack volume capabilities](https://docs.orbstack.dev/docker/file-sharing).
