# Releasing

1. Update `VERSION` and `docs/release-notes.md`, then merge.
2. Tag the merge commit and push the tag:

   ```sh
   git tag "v$(cat VERSION)"
   git push origin "v$(cat VERSION)"
   ```

The release workflow checks that the tag matches `VERSION`, runs `mise run ci`,
builds a universal app with `mise run package-release`, checks it again and
publishes the ZIP and its SHA-256 checksum with the release notes. You can also
dispatch it by hand for an existing tag.

`mise run package-release` builds the same archive in `build/` without publishing.

Releases are ad hoc signed. Developer ID signing and notarization aren't set up,
so the README explains how to open the app the first time.
