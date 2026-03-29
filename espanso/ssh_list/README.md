ssh_list espanso helper

Lists all SSH public keys found in `~/.ssh/`, prompts the user to pick one,
and copies the selected key's contents to the clipboard.

Files:
- `ssh_list.sh`: Core script. Uses zenity/yad for GUI selection when available,
  fzf for interactive terminal selection, or a built-in `select` menu as a
  fallback. Copies the public key via wl-copy, xclip, or xsel.
- `package.yml`: Espanso package configuration with `:sshlist` trigger (works
  in GUI text fields).
- `setup.sh`: Configures a terminal command wrapper for `:sshlist` in shell.
- `README.md`: This file.

Quick Setup (Terminal Command)
==============================

To enable `:sshlist` as a terminal command, run:

```bash
bash espanso/ssh_list/setup.sh
```

Then activate in your current session:

```bash
source ~/.profile
```

After that, you can run `:sshlist` directly in any terminal.

Example Espanso match (Espanso GUI Trigger)
===========================================

The package includes a match for the `:sshlist` trigger in Espanso GUI text
fields (editors, chat, etc.):

matches:
  - trigger: ":sshlist"
    replace: false
    action:
      type: shell
      cmd: "bash -lc \"~/.config/espanso/packages/ssh_list/ssh_list.sh\""

Installation
============

1. Install espanso (if not already installed):
   ```bash
   make install_programs  # select "Espanso (Text Expander)"
   ```

2. Copy the package to your Espanso packages folder:
   ```bash
   make install_espanso_packages
   ```

Dependencies (optional, for best experience)
============================================

| Tool    | Purpose                        | Install                          |
|---------|--------------------------------|----------------------------------|
| zenity  | GUI list dialog                | `sudo apt install zenity`        |
| yad     | GUI list dialog (alternative)  | `sudo apt install yad`           |
| fzf     | Fuzzy-find terminal selection  | `sudo apt install fzf`           |
| wl-copy | Clipboard copy (Wayland)       | `sudo apt install wl-clipboard`  |
| xclip   | Clipboard copy (X11)           | `sudo apt install xclip`         |
| xsel    | Clipboard copy (X11 fallback)  | `sudo apt install xsel`          |

If none of the GUI/selection tools are present, a plain `select` menu is used.
If no clipboard tool is found, the key is printed to stdout instead.
