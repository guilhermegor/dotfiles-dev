# storage/CLAUDE.md

## Purpose

Storage analysis and capacity reporting scripts.

## Scripts

| File | What it does |
|------|-------------|
| `storage_hiato.sh` | Detect SSDs, SATA/NVMe slots, and report theoretical max capacity |

## Conventions

- Scripts in this folder are **read-only / diagnostic** — they must never modify storage.
- Require root: `[ "$(id -u)" -ne 0 ]` guard at the top.
- Use `lsblk -d -o NAME,MODEL,SIZE,ROTA,TRAN` for device enumeration.
- Use `lspci`, `dmidecode`, and `/proc` for hardware introspection.
- Human-readable sizes: implement a `human_readable <bytes>` function using `bc`.
- Output is structured in numbered sections (`[1]`, `[2]`, …) for easy scanning.

## Adding a new analysis script

1. Create `storage/<topic>.sh`.
2. Add a root guard and section-numbered output.
3. Never write to `/dev/*` or modify partition tables.
