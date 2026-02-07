git_reset espanso package

Trigger:
- :gitreset -> runs: git reset --hard HEAD && git clean -fd && code . --reuse-window

Install:
- make install_espanso_packages

Warning:
This will permanently discard uncommitted changes and remove untracked files.
