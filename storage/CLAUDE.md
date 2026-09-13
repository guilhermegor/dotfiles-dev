# storage/CLAUDE.md

## Purpose

All storage concerns in one place: mounting, encryption, formatting, recovery,
backup, and capacity analysis.

## Scripts

| File | What it does |
|------|-------------|
| `mount_disks.sh` | Auto-mount external drives to `/mnt/auto/` |
| `vault.sh` | Encrypt a device with VeraCrypt (AES-256 + SHA-512) |
| `format_hard.sh` | Full (slow) format with `shred` before filesystem creation |
| `format_neat.sh` | Quick format — partition table + filesystem only |
| `data_recovery.sh` | Attempt file recovery with `testdisk` / `photorec` |
| `check_legitimity.sh` | Verify drive health via SMART data |
| `backup_external_ssd.sh` | GUI-driven `.zip` backup of a mounted SSD to a cloud folder |
| `storage_hiato.sh` | Detect SSDs, SATA/NVMe slots, report theoretical max capacity |

## Conventions

- **`print_status <level> <msg>`** with the standard color vars (`RED` `GREEN` `YELLOW` `BLUE` `CYAN` `MAGENTA` `NC`).
- Destructive operations (format, encrypt) must print a `RED` warning and prompt for
  explicit confirmation before proceeding.
- Always unmount before formatting or encrypting: `sudo umount /dev/$device*`.
- Use `lsblk -o NAME,SIZE,TYPE,MOUNTPOINT` to list devices before prompting.
- Mounted media lives under `/media/$USER/<drive-name>/`.
- **Diagnostic / read-only scripts** (`storage_hiato.sh`) must never write to `/dev/*`
  or modify partition tables. Require root with `[ "$(id -u)" -ne 0 ]` guard.

## Backup script (`backup_external_ssd.sh`)

- Uses `zenity` GUI dialogs — works from the GNOME Super+B keybinding without a terminal.
- Prompts for the source drive (from mounted drives), the cloud destination path, and
  the zip compression level, in that order.
- Destination path and compression level are saved to
  `~/.config/backup-external-ssd.conf` (`LAST_DEST=`, `LAST_ZIP_LEVEL=`) between runs.
- Destination structure: `<cloud_path>/<source_drive_name>/<yyyymmdd_hhmmss>.zip`
- Archives the drive into a single compressed `.zip` (`zip -r -y -q -N`, excluding
  `lost+found`) streamed directly from the source — no uncompressed mirror is staged,
  so each run leaves one compact file instead of a full duplicate of the drive.
- Compression level is chosen on a `zenity --list --radiolist` of zip's own 0-9
  levels (0 = store/fastest, 6 = balanced/default, 9 = maximum/slowest) — never a
  slider or a percentage. `DEFAULT_ZIP_LEVEL=6` is the fallback used when the saved
  value is missing or not a single digit 0-9; every level is lossless, higher only
  trades CPU time for a smaller archive. Cancelling the list aborts the backup
  cleanly, same as cancelling the destination prompt.
- Requires `zip` (`sudo apt install zip`); the script aborts with a dialog if missing.

## Adding a new script

1. Create `storage/<action>.sh`.
2. Use the standard color vars and `print_status`.
3. Guard destructive operations with confirmation prompts.
4. Wire into `make` if it should be part of the setup flow.
