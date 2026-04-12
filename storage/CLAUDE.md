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
| `backup_external_ssd.sh` | GUI-driven rsync backup of a mounted SSD to a cloud folder |
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
- Prompts for the source drive (from mounted drives) and the cloud destination path.
- Destination path is saved to `~/.config/backup-external-ssd.conf` between runs.
- Destination structure: `<cloud_path>/<source_drive_name>/<yyyymmdd_hhmmss>/`
- Uses `rsync -a --exclude='lost+found'` (archive mode, skips unreadable root dirs).

## Adding a new script

1. Create `storage/<action>.sh`.
2. Use the standard color vars and `print_status`.
3. Guard destructive operations with confirmation prompts.
4. Wire into `make` if it should be part of the setup flow.
