---
date: 2026-04-21
topic: 4K Video Downloader Plus install + Media GNOME folder
---

# Design: 4K Video Downloader Plus + Media Folder

## Summary

Two coordinated changes:
1. Add `install_4k_video_downloader()` to `distro_config/install_programs.sh`
2. Create a `Media` GNOME app folder in `distro_config/ubuntu_workspace.sh`, seeded with VLC (moved from Utilitários)

## install_programs.sh

- New function `install_4k_video_downloader()` using **scrape + hardcoded fallback**:
  - No official apt repo exists — only direct `.deb` from `https://www.4kdownload.com/downloads`
  - Product name: **4K Video Downloader Plus** (`4kvideodownloaderplus`)
  - Guard: `command_exists 4kvideodownloaderplus` — skip if already installed
  - `apt` distros only:
    1. Scrape `https://www.4kdownload.com/downloads` with `curl -fsSL | grep -oP` for the `4kvideodownloaderplus_*_amd64.deb` URL (page is server-rendered, confirmed scrapable)
    2. Fall back to `https://dl.4kdownload.com/app/4kvideodownloaderplus_26.1.0-1_amd64.deb` if scrape returns empty
    3. Download to `mktemp` dir, `sudo apt-get install -y <file>.deb`, clean up
  - Non-apt distros: `print_status "warning"` with the manual download URL
  - Function defined just before `install_utilities()`; called inside `install_utilities()` after the utilities loop (after line 2640)
- Desktop file: `4kvideodownloaderplus.desktop`

## ubuntu_workspace.sh

### New Media folder

- New `# MEDIA FOLDER` section inside `organize_app_folders()` after the Utilitários block
- Initial `media_app_names`: `vlc.desktop`, `org.videolan.VLC.desktop`, `4kvideodownloaderplus.desktop`, `rhythmbox.desktop`, `org.gnome.Rhythmbox3.desktop`, `cheese.desktop`, `org.gnome.Cheese.desktop`, `org.gnome.Music.desktop`, `totem.desktop`, `org.gnome.Totem.desktop`
- Pattern glob: `*vlc*.desktop`, `*4kdownload*.desktop`, `*4kvideo*.desktop`
- Registers `'Media'` in `folder_ids` and `ordered_folder_ids` (after `'Office'`, before `'OrgPessoal'`)

### VLC removal from Utilitários

- Remove `'vlc.desktop'` and `'org.videolan.VLC.desktop'` from `utility_app_names` (lines 549)

## Constraints

- `ordered_folder_ids` at line 1079 must include `'Media'` — order: after `'Office'`, before `'OrgPessoal'`
- The guard pattern stays consistent with all other folders (deduplicate array, skip if no apps found)
