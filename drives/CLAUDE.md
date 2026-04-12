# drives/CLAUDE.md

## Purpose

External storage management: mounting, encryption, formatting, recovery, and backup.

## Scripts

| File | What it does |
|------|-------------|
| `mount_disks.sh` | Auto-mount external drives to `/mnt/auto/` |
| `vault.sh` | Encrypt a device with VeraCrypt (AES-256 + SHA-512) |
| `format_hard.sh` | Full (slow) format with `shred` before filesystem creation |
| `format_neat.sh` | Quick format — partition table + filesystem only |
| `data_recovery.sh` | Attempt file recovery with `testdisk` / `photorec` |
| `check_legitimity.sh` | Verify drive health via SMART data |
| `backup_external_ssd.sh` | Rsync external SSDs to the BKP cloud-sync drive |

## Conventions

- **`print_status <level> <msg>`** with the standard color vars (`RED` `GREEN` `YELLOW` `BLUE` `CYAN` `MAGENTA` `NC`).
- Destructive operations (format, encrypt) must print a `RED` warning and prompt for
  explicit confirmation before proceeding.
- Always unmount before formatting or encrypting: `sudo umount /dev/$device*`.
- Use `lsblk -o NAME,SIZE,TYPE,MOUNTPOINT` to list devices before prompting.
- Mounted media lives under `/media/$USER/<drive-name>/`.

## Backup drive convention (`backup_external_ssd.sh`)

- **BKP drive**: any drive under `/media/$USER/` whose name starts with `BKP` or contains
  `backup` (case-insensitive). This drive is cloud-synced (e.g. via Insync).
- **Source drives**: all other mounted drives under `/media/$USER/`.
- Backup structure: `<bkp_drive>/<source_drive_name>/<yyyymmdd_hhmmss>/`
- Uses `rsync -a` (archive mode) to preserve permissions, timestamps, and symlinks.
- Non-interactive: uses `notify-send` for feedback (designed to be called from a keybinding).

## Adding a new script

1. Create `drives/<action>.sh`.
2. Use the standard color vars and `print_status`.
3. Guard destructive operations with confirmation prompts.
4. Wire into `make` if it should be part of the setup flow.
