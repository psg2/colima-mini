# Contributing

Keep runtime behavior in ColimaCore and presentation in the app target.
Reproduce issues using sample data or temporary local executables before
testing against a real VM. Do not include real logs, credentials or local
profile files in fixtures or screenshots.

Run these checks before submitting a ready-for-review pull request:

```sh
./Scripts/check.sh
./Scripts/build-app.sh
./Scripts/test-app.sh
```

For source formatting, run:

```sh
swift format format --in-place --recursive Sources Tests Package.swift
```

Describe the observable problem, resulting behavior, checks and any manual
validation gap. Use tests that can catch realistic regressions through module
interfaces. Avoid assertions about private call order or source structure.
