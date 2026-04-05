# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Bash-based Linux dotfiles and system-setup toolkit. Everything is orchestrated through `make`. Scripts are organised by concern under `distro_config/`, `drivers/`, `drives/`, `os/`, `storage/`, `code_editors/`, `espanso/`, and `ai_clients/`.

## Common commands

```bash
make help                  # Show all targets
make init                  # Full first-time setup (recommended entry point)
make permissions           # chmod +x all *.sh scripts
make ai_clients            # Interactive AI clients menu (Claude Code, ...)
make install_espanso_packages  # Copy espanso/ packages to ~/.config/espanso/packages/
make editors_setup         # VS Code + AI clients
make check_status          # Show distribution info and executable scripts
make clean                 # Remove *.log, *.tmp, *~ files
```

No build step, no test suite — scripts are run directly.

## ai_clients architecture

Two-level menu system:

```
ai_clients/main.sh              ← top-level router; auto-discovers ai_clients/*/main.sh
ai_clients/lib/utils.sh         ← shared print_status(), colour vars, LOG_FILE
ai_clients/claude/main.sh       ← Claude Code orchestrator with STEPS registry
ai_clients/claude/lib/          ← one file per step:
    prerequisites.sh            ← checks for claude CLI, jq, python3, node
    settings.sh                 ← merges settings.json into ~/.claude/settings.json
    marketplaces.sh             ← register_marketplace()
    plugins.sh                  ← promote_plugin_to_user_scope()
    slash_commands.sh           ← installs custom slash commands
    claude_md.sh                ← installs global CLAUDE.md to ~/.claude/
    rules.sh                    ← installs language rules (python.md, …)
    mcp_servers.sh              ← installs MCP servers
    integrations.sh             ← runs /terminal-setup, /install-github-app, /install-slack-app
```

`STEPS` array in `ai_clients/claude/main.sh` uses `"key|label"` pairs. `dispatch_step "$key"` routes each key to its lib function. To add a new step: add an entry to `STEPS`, add a `case` branch in `dispatch_step`, and create the lib function.

`ai_clients/main.sh` discovers client subdirectories at runtime — adding a new AI client only requires creating `ai_clients/<name>/main.sh`.

## Espanso packages

Each package lives under `espanso/<name>/` and must contain `package.yml`. The optional `setup.sh` inside each package runs after the copy step in `make install_espanso_packages`. Packages are copied verbatim to `~/.config/espanso/packages/<name>/`.

## Claude Code settings

`ai_clients/claude/settings.json` is the base config merged into `~/.claude/settings.json`. Merge strategy: `current * base_settings` (base takes priority). The `statusLine` key is injected conditionally only when the claude-hud plugin cache exists.

Plugins are promoted from project scope to user scope by writing entries directly into `~/.claude/plugins/installed_plugins.json`. Plugins must already be installed inside Claude Code (`/plugin install <name>`) before `promote_plugin_to_user_scope` can find their cache.
