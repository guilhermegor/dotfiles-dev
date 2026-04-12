# drivers/CLAUDE.md

## Purpose

Per-device hardware driver and configuration scripts.

## Scripts

| File | What it does |
|------|-------------|
| `mouse.sh` | MX Master — natural scrolling, xbindkeys workspace buttons |
| `setup_keyboard.sh` | Keyboard layout and repeat rate |
| `bluetooth_adapter.sh` | Bluetooth adapter setup |
| `tplink_wifi_adapter.sh` | TP-Link USB Wi-Fi adapter driver install |

## Conventions

- Each script targets **one device** — keep them small and focused.
- **`print_status <level> <msg>`** with the standard color vars.
- Guard every `command -v` before installing dependencies; use `sudo apt-get install -y`.
- Backup config files before overwriting: `backup_file()` pattern from `mouse.sh`.
- Scripts that modify system services must verify the service started:
  `pgrep <service>` or `systemctl is-active <service>`.
- Autostart entries go in `$HOME/.config/autostart/<name>.desktop`.

## Adding a new device script

1. Create `drivers/<device>.sh`.
2. Source the standard color vars at the top.
3. Implement `install_dependencies`, `configure_<device>`, `verify_installation`, and `main`.
4. `chmod +x` is handled by `make permissions`.
