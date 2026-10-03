# Contributing

Keep runtime behavior in ColimaCore and presentation in the app target.
Reproduce issues using sample data or temporary local executables before
testing against a real VM. Do not include real logs, credentials or local
profile files in fixtures or screenshots.

Install the pinned tools and the pre-push hook once:

```sh
mise install
mise run hooks
```

Before opening a ready-for-review pull request, run `mise run check`. It runs
the same gates as CI plus a Gitleaks scan. `mise run format` fixes formatting.

Describe the observable problem, resulting behavior, checks and any manual
validation gap. Use tests that can catch realistic regressions through module
interfaces. Avoid assertions about private call order or source structure.
