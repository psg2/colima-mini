# Development

## Setup

You need Swift 6 or later from Xcode or the Command Line Tools, and
[mise](https://mise.jdx.dev). There's no Xcode project and no external Swift
package dependency.

```sh
mise install     # pinned shellcheck, actionlint, gitleaks and lefthook
mise run hooks   # pre-push hook that runs `mise run check`
```

## Tasks

`mise tasks` lists every task. The ones you'll use most:

| Task | What it does |
| --- | --- |
| `mise run build` | Builds and ad hoc signs `build/Colima Mini.app` |
| `mise run install` | Builds and copies the app to `~/Applications` |
| `mise run uninstall` | Removes the installed app and keeps its preferences |
| `mise run run` | Builds and opens the app; add `--fixture PATH` for sample data |
| `mise run format` | Rewrites Swift sources with swift-format |
| `mise run lint` | Formatting, ShellCheck, actionlint and Info.plist |
| `mise run test:unit` | `swift test` |
| `mise run test:app` | Builds, then checks the bundle and a relocated copy |
| `mise run test` | `test:unit`, then `test:app` |
| `mise run ci` | `lint` and `test`, as CI runs them |
| `mise run check` | `ci` plus a Gitleaks scan of the tree and history |

### Sample data

```sh
mise run run --fixture "$PWD/Tests/ColimaCoreTests/Fixtures/sample.json"
```

This opens a separate instance titled **Sample data**, even when the real
dashboard is running. Sample mode turns off every change to the runtime,
containers and resources.

### Command-line checks

The app binary has read-only modes that print and exit without opening a window:

```sh
APP="build/Colima Mini.app/Contents/MacOS/ColimaMini"
"$APP" --check         # runtime summary as JSON
"$APP" --scan          # unused-container report
"$APP" --reclaim-plan  # what Reclaim space would offer
```

The app finds `docker`, `colima` and `lsof` through `PATH` and the usual
Homebrew and system locations. `COLIMA_MINI_DOCKER`, `COLIMA_MINI_COLIMA` and
`COLIMA_MINI_LSOF` override them with absolute paths. `COLIMA_HOME` picks the
profile directory.

## Tests

CI runs `mise run ci` on macOS 26, `mise run test` on macOS 14 (Apple Silicon)
and macOS 15 (Intel), and a Gitleaks scan on Linux. All targets compile with
warnings treated as errors. Hosted runners can't run a nested Colima VM, so runtime
tests use fake `docker` and `colima` executables. Restarting a real VM, clicking
through the UI and networking still need a manual check on a Mac with Colima. The
automated checks never stop your local VM.
