Colima Mini is an unofficial native macOS app and menu bar panel for Docker on
the default Colima profile. This release adds most of what the README describes.

- **Containers.** Compose projects show where they ran (a folder, or a Claude,
  Codex, Conductor or Orca worktree). Act on several containers at once, and run
  Compose Up, Pull and Down on a project.
- **Container pages.** Overview, live Logs with search, wrap and pause, Ports,
  Mounts, and Env with secrets masked. Shell and Open use the terminal and editor
  you pick. Follow a whole project's logs in one view.
- **Images, volumes and networks.** New Images, Volumes and Networks pages with
  sizes and the containers that use each item. Remove unused ones singly or in bulk.
- **Disk.** Storage shows the VM disk, Docker's usage and the space taken on the
  Mac, with a low-disk warning. Reclaim space previews build cache, unused images,
  networks, stopped containers and anonymous volumes before removing what you
  pick. Named volumes are never part of it.
- **Unused containers.** Review unused containers finds stacks whose folder was
  deleted, stopped for over a day, or idle. It now runs inside the app, so Python
  is no longer required.
- **VM.** Settings is one tabbed window: change CPU, memory and disk, then save
  for the next start or restart now.
- **Menu bar.** Usage, containers that need attention, project actions and
  notifications when a container crashes, fails its health check or keeps
  restarting. Opening at login starts in the menu bar only.
- **Keyboard.** Go and Container menus, ⌘K search and actions, and shortcuts for
  every page and container tab.
- Universal Apple Silicon and Intel app, macOS 14 or later.

Install Colima and the Docker CLI separately. Releases are ad hoc signed, not
notarized. See the
[first-open instructions](https://github.com/psg2/colima-mini#open-a-downloaded-release-for-the-first-time)
to check the checksum and open the app.

Every removal asks first and runs without `--force`, so Docker refuses anything a
container still uses. The app never compacts disk images or shrinks the VM disk.
