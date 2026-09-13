# Replacing Insync with an on-demand rclone mount (issue #360)

## Why

Insync mirrors every remote file to disk, forever, whether or not it is ever opened. Measured on
this machine, 2026-09-13:

| what | size |
|---|---|
| `~/Insync/guirodrigues.gor@gmail.com/OneDrive/` (one **OneDrive** account) | **1.3 T** |
| `~/.config/Insync/` (metadata/db) | **17 G** |
| root filesystem | 1.8 T total, **1.6 T used, 188 G free (90 %)** |

`rclone mount` with a VFS cache serves the directory listing instantly and downloads a file only
when something opens it, with a hard ceiling on the cache (`--vfs-cache-max-size 10G`). A 10 G
cache ceiling replaces a 1.3 T mirror.

## What this repo automates

- `install_rclone` (`distro_config/install_lib/sharing.sh`) — installs the `rclone` package via
  the distro's package manager. Never runs `rclone config`, never writes anything under
  `~/.config/rclone/` — that step is interactive and account-bound, so it stays manual.
- `install_rclone_mount_unit <remote> <mountpoint>` (same file) — writes
  `~/.config/systemd/user/rclone-<remote>.service` from the repo-tracked template at
  `distro_config/dotfiles/rclone/rclone-mount.service.template`. Never enables or starts the
  unit; refuses if `<mountpoint>` is `~/Insync`.
- `uninstall_insync <remote> [account-dir]` (same file) — the 5-step ordered removal below, as a
  single function. Not registered in `INSTALL_REGISTRY` (a registry entry runs during Full
  Installation too, which would fight `install_insync` — see #342), so it is invoked directly:

  ```bash
  bash -c 'source distro_config/install_lib/sharing.sh; uninstall_insync <remote> <account-dir>'
  ```

## Operator runbook — the 5 mandatory ordered steps

⚠️ Deleting `~/Insync/` while Insync is running propagates the deletion to OneDrive. The
order below is mandatory; `uninstall_insync` enforces it by refusing to continue when a
precondition fails.

1. **Quit Insync and disable it from starting.** `uninstall_insync` calls `insync quit`, then
   requires `pgrep -a insync` to print nothing, and removes `~/.config/autostart/insync.desktop`
   if present. Refuses (exit 1) if any insync process survives.
2. **Verify remote-side integrity while the local copy still exists.** With the daemon stopped,
   `uninstall_insync` runs `rclone check <remote>: <account-dir> --one-way --dry-run` and logs the
   result. Refuses if this check fails — resolve the discrepancy before re-running.
3. **Uninstall the package.** `sudo apt remove --purge insync`, verified against
   `dpkg -l | grep insync` being empty. Touches only the local machine — OneDrive keeps
   everything regardless of which client is installed.
4. **Delete `~/Insync/` and `~/.config/Insync/`.** Gated behind the explicit
   `INSYNC_CONFIRM_DELETE=1` environment variable — it is the one step that destroys local data,
   and it never runs just because steps 1-3 passed. Without it, `uninstall_insync` reports what it
   would delete and exits 0 without touching anything.
5. **Re-check the remote after deletion.** `rclone lsjson <remote>: --stat`, logged for a
   before/after comparison.

## Steps that remain manual (cannot be automated safely)

- **`rclone config`** — interactive, account-bound; adding an OAuth-authenticated remote requires
  a browser flow this repo has no business scripting, and no token may ever be committed.
- **Choosing and creating the mount point** — must not be `~/Insync` until step 4 above has run;
  the operator decides where the mount lives.
- **`systemctl --user daemon-reload` and `systemctl --user enable --now rclone-<remote>.service`**
  — `install_rclone_mount_unit` only writes the unit file and prints these two commands; the
  operator runs them after reviewing the generated unit.
- **The actual `INSYNC_CONFIRM_DELETE=1` run** — deleting 1.3 T of the owner's data is a
  human decision, not a default.
- **Verifying the cache ceiling holds** — read a file larger than 10 G through the mount, then
  confirm `du -sh ~/.cache/rclone/` stays under the cap. This needs the mount to actually be
  live.

## Machine state that points into `~/Insync` — migrate it before step 4

The tree is not only data; other things hold paths into it. Found on this machine:

- **Super+B (Backup External SSDs)** — `~/.config/backup-external-ssd.conf` holds
  `LAST_DEST=/home/guilhermegor/Insync/guirodrigues.gor@gmail.com/OneDrive/Workspace/!BACKUP/External Storage`.
  After step 4 that path is gone, and the backup script's `mkdir -p` would happily re-create it on
  the local disk and write the archive there — a backup that looks cloud-bound and is not.
  `storage/backup_external_ssd.sh` now refuses to pre-fill a destination whose parent no longer
  exists and says so in the prompt, so the migration surfaces as a question instead of a silent
  local write. Point it at the new mount path on the first run after migrating.
- ⚠️ **Do not write large archives through the mount.** `--vfs-cache-max-size 10G` bounds the
  cache, and a write larger than the ceiling has nowhere to land. For the SSD backup, write the
  zip to local scratch and `rclone move` it to the remote, rather than zipping straight into the
  mount point.

Before running step 4, grep for other holders:

```bash
grep -rIl "$HOME/Insync" ~/.config ~/.local/share ~/.local/bin 2>/dev/null
```

## Trade-offs to keep in mind

- **Offline access changes.** Insync always had every file on disk; the mount only has what is in
  the cache. Pin any folder that must be available offline with a scheduled `rclone sync` into a
  real local directory, or accept the loss explicitly.
- Applications that scan whole trees (indexers, backup tools, some editors) pull files through
  the mount and can fill the cache — check which of those are running before relying on the
  ceiling.
- `--vfs-cache-mode full` needs writable space in `~/.cache/rclone`, which sits on the same
  90 %-full root filesystem the 10 G cap is meant to protect.

## Alternatives considered

- **OneDriver** — OneDrive-only, so it *is* applicable here, but it offers no cache ceiling: it
  caches whatever is opened with no `--vfs-cache-max-size` equivalent. The 10 G cap is the point
  of this migration, so `rclone` wins on the one axis that motivated it.
- **Celeste** — GUI, on-demand, but fewer knobs than rclone's VFS cache; worth revisiting only if
  the mount proves awkward to live with.
- **Keeping Insync with selective sync** — solves disk usage but keeps a per-seat paid client for
  something a mount does for free, and still mirrors whatever is selected.
