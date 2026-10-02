# Working agreements

- Keep the app native in SwiftUI and the runtime logic in ColimaCore.
- Preserve the default Colima profile and explicit Docker context selection.
- Sample mode must never run runtime or container mutations.
- Cleanup removes only items listed in a preview, after confirmation, one ID
  at a time and never with force. Cleanup never removes named volumes; a named
  volume is deleted only by an explicit, confirmed action on that volume or its
  Compose project (Down and delete volumes).
- Write code, comments, documentation and PRs in English.
- Open pull requests ready for review and explain the problem, changes,
  validation and limitations. Monitor checks and bot review comments.
- Test observable behavior through module interfaces. Do not assert internal
  call order or source text. Use temporary configs and local fake executables
  for runtime tests; never stop the developer's VM during automated checks.
- Run `./Scripts/check.sh`, `./Scripts/build-app.sh` and
  `./Scripts/test-app.sh` before publishing code changes.
- Use standard GitHub-hosted runners. Keep write permissions limited to the
  release job, pin actions by full commit SHA, and never publish local credentials.
