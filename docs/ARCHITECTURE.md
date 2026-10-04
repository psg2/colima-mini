# Architecture

```mermaid
flowchart LR
    Views[SwiftUI views and menu bar] --> State[Dashboard state]
    State --> Core[ColimaCore]
    Core --> CLIs[Installed Docker and Colima CLIs]
    Core --> Config[Local resource configuration]
    Tests[Core tests with temporary configs and local runtimes] --> Core
```

The Swift package has three targets. Each depends only on the one below it.

```text
Sources/ColimaCore/        Runtime operations, process execution, models and config
Sources/ColimaAppState/    Navigation, refresh coordination and observable state
Sources/ColimaMini/        App entry point and SwiftUI views
Tests/ColimaCoreTests/     Parser, process, config and runtime integration tests
Tests/ColimaAppStateTests/ Navigation and state tests
Resources/                 Info.plist and the application icon source
Scripts/                   Build, bundle checks and packaging
.github/workflows/         CI and tag-based releases
```

`Scripts/build.sh` compiles the `ColimaMini` product with SwiftPM and assembles
the `.app` bundle. It copies `Resources/Info.plist` and stamps the version from
`VERSION` into it, builds the icon set and signs the bundle ad hoc.

Every Docker command passes `--context colima`. The unused-container scan reads
`docker inspect`, `docker stats`, `docker logs` and `lsof`, and changes nothing.
Subprocess output goes to private temporary files that the app deletes when the
command finishes.
Logs never leave the Mac.
