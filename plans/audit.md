# Colima Mini — deep audit and product direction

Audited 2026-10-02 at `ecf0266ff731f93f7cfa95c3d2f13f505b4d725c`. This is an advisory deliverable, not a shipped app update. Only `plans/` changed. No containers, volumes, profile settings, branches, releases or dependencies were changed.

## Recommendation

Replace the dashboard split pane with navigation between objects. A container opens a full page; its mounts link to volumes, and volumes link back to their attached containers. Storage explains three distinct measurements: Docker object sizes, usage inside the VM, and physical VM-image allocation on the Mac. Put frequent controls in the screen where they act.

The requested navigation, container page and storage work is selected by the user. The extra reliability and onboarding plans follow the recommended option offered during this audit; they remain recommendations, not authorization to implement under the read-only improve skill. Estimates include meaningful tests and are coarse: S is hours, M about a day, L several days.

## Vetted findings, in execution order

| ID | Finding | Impact | Effort | Fix risk | Confidence | Plan |
|---|---|---|---|---|---|---|
| BUG-01 | A failed cleanup scan reports success | Docker failure can become “No containers” and failed activity probes can become idle classifications | S | LOW | HIGH | 001 |
| BUG-02 | Restart restoration uses a stale dashboard snapshot | A container started or stopped in Terminal before Apply can be restored incorrectly | M | MED | HIGH | 001 |
| UX-01 | Groups hides two basic controls behind a menu | Every global expand/collapse requires opening an extra menu; search forces groups open without explaining why | S | LOW | HIGH | 002 |
| UX-02 | Footer actions have a different alignment and interaction from navigation | Settings and Unused containers float under a List instead of occupying consistent sidebar rows | S | LOW | HIGH | 002 |
| STATE-01 | An old refresh can publish after a mutation | The screen can return to stale state; a requested post-action refresh can be skipped | M | MED | HIGH | 002 |
| UX-03 | Container details consume space beneath every list | Logs have too little room, while list navigation remains visible at the expense of the selected task | M | MED | HIGH | 003 |
| BUG-03 | stdout and stderr logs are reordered | Errors can appear after newer messages, obscuring diagnosis | S/M | LOW/MED | HIGH | 003 |
| PERF-01 | Logs poll on Ports and while inactive | About 12 unnecessary Docker log subprocesses per minute at the default interval | S/M | LOW | HIGH | 003 |
| BUG-04 | Cancellation waits for the original process deadline | A canceled TERM-ignoring child can survive 15–45 seconds and overlap replacement requests | M | MED | HIGH | 003 |
| DIRECTION-01 | Persistent data and storage are absent | Users cannot trace their database to a volume or distinguish disk capacity from space occupied | L | MED | HIGH | 004 |
| DX-01 | Fixture launch can reuse the real app process | Preview commands can bring forward a live dashboard rather than start synthetic mode | S | LOW | HIGH | 005 |
| DOCS-01 | Release notes promise missing first-open instructions | Public release onboarding has no documented Gatekeeper flow | S | LOW | HIGH | 005 |

## Evidence and fix sketches

### BUG-01: Report failed probes as failed scans

`Sources/ColimaCore/Resources/docker-sweep.py:41–42` returns stdout and discards command status/stderr. `:137–140` treats empty stdout as “No containers.” Verification with Docker replaced by `/usr/bin/false`, `--sample 0`, exited 0 and reported no containers. No runtime was contacted. Mandatory Docker probe errors should fail the scan; optional unavailable traffic/client probes should be explicit unknowns, never evidence of idleness. Handle lsof's normal no-match exit separately. App remains report-only.

### BUG-02: Capture the running set immediately before stopping Colima

`Sources/ColimaMini/State/Dashboard.swift:58–68` passes the existing UI snapshot to `Backend.apply`. `Sources/ColimaCore/Backend.swift:42–57` uses its old running IDs after restarting. Read authoritative state at the mutation boundary and restore that set. Verify partial restoration and retain actionable errors; automatic rollback is not assumed safe.

### UX-01 / UX-02: Make controls visible and sidebar rows consistent

`Sources/ColimaMini/Views/DashboardView.swift:104–114` defines the Groups menu. `:58–72` places two independently padded buttons below the sidebar List. `Sources/ColimaMini/Views/ProjectSection.swift:11–17` forces expanded groups during search. Replace the menu with one visible Collapse all / Expand all button whose action reflects current visible groups. Keep individual chevrons. Search expands matching groups temporarily; explain and disable global collapse until search clears, without overwriting saved collapse preferences. Put Settings in an aligned footer navigation row; place the unused-container report within Storage.

### STATE-01 / test coverage: Protect the visible state during navigation changes

`Sources/ColimaMini/State/Dashboard.swift:87–104` checks busy only before awaiting a refresh. `:131–146` starts mutation and can skip its refresh if an earlier one is still running. `Package.swift:10–12` tests only ColimaCore, not application state. Add the smallest testable state boundary and generation/coordinator policy. Tests should observe displayed state, errors and routes under delayed completion, not private call sequences.

### UX-03 / BUG-03 / PERF-01 / BUG-04: Give diagnosis its own page and lifetime

`Sources/ColimaMini/Views/DashboardView.swift:127–130` reserves a minimum 210-pixel details pane; `:195–257` combines detail controls, Logs and Ports inside it. `:184–192` fetches logs whenever selectedID exists, including the Ports tab. `Sources/ColimaCore/Command.swift:97–105` returns all stdout then all stderr. Cancellation at `:9–14` sends TERM but escalation at `:70–76` begins only after the full timeout. Give the container route Overview, Logs, Ports and Mounts tabs; preserve a chronological log boundary, pause/follow/search controls and bounded cancellation. Fetch inspection data on entering a page, not per list row.

### DIRECTION-01: Model volumes and storage independently of the dashboard snapshot

`Sources/ColimaCore/Backend.swift:65–72` queries only Colima, containers and stats. `Sources/ColimaCore/Models/VM.swift:3–7` discards the disk field already returned by Colima. `Sources/ColimaMini/Views/ResourceOverview.swift:10–26` exposes CPU, memory and inferred web endpoints only. Read named volumes, container mounts and daemon disk data into separate typed models; use independent errors/cadence so slow storage does not block container controls.

### DX-01 / DOCS-01: Make preview and release onboarding predictable

`Scripts/run.sh:5` opens the bundle without `-n`, while fixture parsing happens only during `ColimaMiniApp.swift:24–26`. `README.md:79–85` promises a synthetic preview. The local open(1) manual confirms that -n starts a separate instance. `docs/release-notes.md:9–11` points to first-open instructions absent from `README.md:29–35`. Isolate fixture launches and document Apple's per-app opening flow.

## Fix-risk rationale

BUG-01 is LOW because checked results must preserve lsof's normal no-match result. BUG-02 is MED because restoration affects runtime continuity. UX-01/02 are LOW because they preserve underlying actions and preferences. STATE-01 and UX-03 are MED because shared state and task lifetimes change. BUG-03 is LOW/MED because ordinary command diagnostics and multiline records must remain intact. PERF-01 is LOW because resume must fetch fresh data. BUG-04 is MED because child completion, locking and termination interact. DIRECTION-01 is MED because incorrect storage accounting would mislead decisions. DX-01 and DOCS-01 are LOW because they alter preview launch/onboarding without runtime mutations.

## Live storage verification

Read-only measurements at audit time; they will change as workloads run. Colima had 10 CPUs and 20 GiB. `colima list --json` returned a 100 GiB disk limit. `colima ssh -- df -B1 / /var/lib/docker` identified separate OS and data filesystems: the data filesystem used 9,154,600,960 bytes (about 8.53 GiB), with 90,547,183,616 bytes (84.33 GiB) available. Its reported filesystem size was 105,087,164,416 bytes (97.87 GiB), below the configured image capacity.

`docker --context colima system df --format '{{json .}}'` reported 13 images / 7.08 GB, 8 containers / 6.738 MB, 29 volumes / 1.976 GB, and 27 build-cache records / 253 MB. These are decimal Docker units, not GiB. Docker called 1.09 GB of volume data reclaimable; that says nothing about whether the data matters to its owner. Stopped containers still count as volume references.

`du -k` reported 19,874,840 KiB allocated for the data image and 1,458,900 KiB for the OS image: about 20.35 GiB total physical blocks. `stat -f '%z'` reported logical image sizes of 100 GiB and 20 GiB respectively. Therefore 100 GiB is not space preallocated on the host, and 8.53 GiB of VM filesystem usage is not the Mac footprint. APFS compression/clones and shared allocation also limit what a physical-block estimate can promise. A future implementation must label the measurement and report unavailable when image discovery is unsupported.

The HTML preview uses synthetic examples, not a stored dump of this machine.

## Design direction

Subject: a small native macOS tool for a developer managing local Compose services and their persistent data. Main job: move from a project to the container that needs attention, then understand its logs or data without losing context.

Palette study: Harbor `#14272F`, Slate `#203740`, Fog `#DCE8EB`, Cyan `#58C6CA`, Amber `#F1BD6A`, Line `#36525C`. SwiftUI implementation should use semantic system colors for surfaces and text so light mode and contrast settings work; cyan is the identity accent, amber is attention. Use SF Rounded sparingly for object titles, SF Pro for controls, SF Mono for logs/IDs, and tabular digits for metrics. Reuse the existing llama assets; the preview's simple vector is only a layout marker, not a replacement logo.

Signature: a compact relationship strip, `project → service → persistent volume`, that also acts as navigation. It earns its space by answering where a database stores its data. Keep rows and separators quiet; remove decorative metric cards, repeated subtitle labels and nested rounded containers.

Compared layouts:

```text
Current:   Sidebar | list + overview
                   | tiny bottom logs / ports pane
Proposed:  Sidebar | Containers list → Container page
                   | Volumes list    → Volume page
                   | Storage         → report
                   | Settings
```

The native version should preserve list filter, collapse state and scroll position when returning from a container. Back must go to the originating project/list, not reset everything to All. Preview navigation is deliberately simplified and does not prove this state contract.

## Competitor references and grounded options

1. **Diagnosis first** — Docker Desktop documents object detail tabs, health-relevant stats and log search; lazydocker makes service logs, metrics and lifecycle actions quickly accessible. Colima Mini already has selectedID, needsAttention, Backend.logs and project labels, making this a natural extension. Build Overview/Logs/Ports/Mounts first; add exit code, OOM reason and a short CPU/RAM history afterward. Tradeoff: inspection/history need new data models and bounded retention. [Docker container UI](https://docs.docker.com/desktop/use-desktop/container/), [lazydocker](https://github.com/jesseduffield/lazydocker).

2. **Data and storage visibility** — Docker Desktop lists volume size/use and links to attached containers. OrbStack provides accessible volume files and export/clone tools. Here the immediate gain is mount relationships, unattached filters and disk accounting. Tradeoff: Finder access, consistent database backups and copy-on-write cloning require runtime capabilities; a SwiftUI layer cannot reproduce them alone. Defer editing volume files, cloning and backup/restore to separate designs. [Docker volumes UI](https://docs.docker.com/desktop/use-desktop/volumes/), [OrbStack volumes](https://docs.orbstack.dev/docker/file-sharing), [Docker disk accounting](https://docs.docker.com/reference/cli/docker/system/df/).

3. **Fast local navigation** — Oriel documents a command palette, streaming logs and container inspection; lazydocker emphasizes keyboard access. Colima Mini already shares state between menu bar and window, so Command+K object search, recent/pinned projects and explicit terminal launch are grounded follow-ups. Tradeoff: an embedded terminal and engine event stream bring substantial lifecycle complexity; begin with keyboard navigation and an external-terminal action. [Oriel](https://github.com/ParadoxInfinite/oriel).

4. **Resource diagnosis** — The resource-settings flow and needsAttention flag already exist. A runtime page can show active versus saved CPU/RAM, disk pressure, and a concise last-action result. Tradeoff: history needs clear CPU denominators and stale/missing states. Keep 10 CPU / 20 GiB; changing resource settings still requires the existing explicit restart confirmation.

## Coverage and rejected findings

All nine improve categories were examined: correctness, security, performance, tests, architecture, dependencies, DX, docs and direction. Core subprocess boundaries and CPU/RAM tests are meaningful; no tautological tests or supported credential/security defect was found. No third-party Swift dependency migration is needed. Swift 5 language mode with Swift 6 tools is an intentional compatibility choice. CI has working ARM and Intel checks; universal release is present. No fresh build was needed for a plans-only change; audit uses source and targeted read-only probes, not a claim of newly tested app behavior.

Rejected: fixed default profile / explicit Colima context, report-only cleanup, configurable local executables and ad-hoc signing are documented choices. Automatic restart rollback is not intrinsically safer; recovery should be explicit. Quadratic filtering and metric lookup deserve measurement at larger inventories, not a speculative rewrite for today's small inventory. Generic pre-commit hooks, caches, Electron conversion, AI chat, Kubernetes, automatic prune and copying OrbStack's DNS/HTTPS backend do not address the immediate task. Architecture already has Core/UI separation; deepen state and storage boundaries as needed, without multiplying files solely for appearance.

## Validation and limitations

Source evidence was independently checked after three read-only category audits. The cleanup failure reproducer touched no Docker daemon. Runtime and disk probes were reads only. The preview was checked for direct collapse/expand, container navigation, tabs and object relationships; it is a design artifact, not SwiftUI feature validation. Plans require synthetic public-boundary tests, then manual native checks with synthetic data before any live resource mutation.

First-open documentation reference: [Apple: Safely open apps on your Mac](https://support.apple.com/en-us/102445). No Gatekeeper setting changed during this audit.
