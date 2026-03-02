# Kill Port - Espanso Package

Quickly kill processes running on specific ports using Espanso triggers.

## Features

- **Interactive Port Selection**: Type `:killport` or `:kp` to get a prompt for the port number
- **Automatic Process Detection**: Uses `lsof` to find processes listening on the specified port
- **Safe Execution**: Validates port numbers and provides feedback
- **Process Information**: Shows the process name and PID before killing

## Usage

### Basic Usage

1. Type `:killport` in any text field
2. Enter the port number when prompted (e.g., `8080`)
3. The process will be killed and you'll see a confirmation message

### Quick Shorthand

1. Type `:kp` for a shorter trigger
2. Enter the port number
3. Process killed!

## Examples

```
:killport
Port to kill: 8080
✓ Killed process node (PID: 12345) on port 8080
```

```
:kp
Port: 3000
✓ Killed process python (PID: 54321) on port 3000
```

## Technical Details

The package uses the following command internally:
```bash
lsof -i :PORT | grep LISTEN | awk '{print $2}' | xargs kill -9
```

This command:
1. Lists open files/connections on the specified port
2. Filters for processes in LISTEN state
3. Extracts the process ID (PID)
4. Forcefully kills the process with `kill -9`

## Requirements

- `lsof` command (usually pre-installed on Linux)
- Permissions to kill processes (may require `sudo` for system processes)

## Installation

This package is automatically installed when you run:
```bash
make install_espanso_packages
```

Or manually:
```bash
cp -r espanso/kill_port ~/.config/espanso/packages/
espanso restart
```

## Troubleshooting

**"No process found listening on port X"**
- The port is not in use
- Check with `lsof -i :PORT` manually

**"Failed to kill process on port X (may require sudo)"**
- The process requires elevated privileges
- Run manually: `sudo lsof -i :PORT | grep LISTEN | awk '{print $2}' | xargs sudo kill -9`

## Safety Notes

⚠️ This package uses `kill -9` (SIGKILL) which forcefully terminates processes without allowing them to clean up. Use with caution on production systems.
