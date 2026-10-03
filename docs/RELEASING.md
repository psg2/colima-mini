# Releasing

1. Update `VERSION` and `docs/release-notes.md`, then merge.
2. Tag the merge commit and push the tag:

   ```sh
   git tag "v$(cat VERSION)"
   git push origin "v$(cat VERSION)"
   ```

The release workflow checks that the tag matches `VERSION`, runs `mise run ci`,
builds a universal app with `mise run package-release` in ad hoc mode, extracts the
archive and checks the app inside it (checksum, signature, version, minimum macOS
and both architectures), and
publishes the ZIP and its SHA-256 checksum with the release notes. You can also
dispatch it by hand for an existing tag.

To build the same archive in `build/release/` without publishing:

```sh
COLIMA_MINI_RELEASE_SIGNING=adhoc mise run package-release
```

The script refuses to run without that variable, so an unnotarized archive is
always a deliberate choice.

Releases are ad hoc signed. Developer ID signing and notarization aren't set up,
so the README explains how to open the app the first time.
