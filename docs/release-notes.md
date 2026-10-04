Colima Mini is an unofficial native macOS dashboard for the default Colima profile.

- Direct Expand all / Collapse all controls and aligned sidebar navigation.
- Container pages with Overview, Logs, Ports and Mounts, plus Back navigation.
- Bounded log refresh with pause, follow, search and copy controls.
- Read-only volume inventory with references from running and stopped containers.
- Storage measurements for configured capacity, VM filesystem, Docker objects
  and identified VM image allocation on the Mac. Unsupported data is explicit.
- CPU and memory settings with deferred save or confirmed VM restart.
- Matching llama menu bar icon and compact status panel.
- Read-only scan for unused containers, built into the app. Python is no longer
  required.
- Universal Apple Silicon and Intel app, macOS 14 or later.

Install Colima and the Docker CLI separately. Releases are ad-hoc signed;
Apple Developer ID signing and notarization are not configured. See
[first-open instructions](https://github.com/psg2/colima-mini#open-a-downloaded-release-for-the-first-time)
for checksum verification and Apple's app-specific opening procedure.

The app preserves Docker volumes and doesn't apply cleanup, prune objects, resize
VM disks or compact disk images. Docker reclaimable bytes are estimates and don't
promise an equal reduction in the Mac disk footprint.
