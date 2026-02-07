ssh_generate espanso helper

This folder contains an interactive script to generate SSH keys and an example Espanso snippet to call it.

Files:
- `ssh_generate.sh`: Interactive generator. Uses zenity/yad for GUI prompts when available, otherwise falls back to terminal prompts. Copies the public key to clipboard when possible (wl-copy, xclip, xsel).
- `package.yml`: Espanso package configuration with `:sshgen` trigger (works in GUI text fields).
- `setup.sh`: Configures terminal command wrapper for `:sshgen` in shell.

Quick Setup (Terminal Command)
==============================

To enable `:sshgen` as a terminal command, run:

```bash
bash espanso/ssh_generate/setup.sh
```

Then activate in your current session:

```bash
source ~/.profile
```

After that, you can run `:sshgen` directly in any terminal.

Example Espanso match (Espanso GUI Trigger)
===========================================

The package includes a match for the `:sshgen` trigger in Espanso GUI text fields (editors, chat, etc.):

matches:
  - trigger: ":sshgen"
    replace: false
    action:
      type: shell
      cmd: "bash -lc \"~/.config/espanso/packages/ssh_generate/ssh_generate.sh\""

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

3. (Optional) Set up the terminal command:
   ```bash
   bash espanso/ssh_generate/setup.sh
   source ~/.profile
   ```

Notes:
- The script supports CLI args: `ssh_generate.sh [email] [passphrase] [path] [type]`.
- After generation, the public key is copied to clipboard when a clipboard utility is available.
- To register/start the espanso service (if installed via package):

  espanso service register
  espanso start

