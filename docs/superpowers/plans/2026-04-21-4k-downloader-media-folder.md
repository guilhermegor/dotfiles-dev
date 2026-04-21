# 4K Video Downloader Plus + Media Folder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `install_4k_video_downloader()` installer function and a new `Media` GNOME folder containing VLC (moved from Utilitários).

**Architecture:** Two independent file edits — `install_programs.sh` gets a new installer function that scrapes the 4KDownload page for the latest `.deb` URL; `ubuntu_workspace.sh` gets a new `Media` folder section plus VLC removed from `Utilitarios`. Both files follow the existing patterns exactly.

**Tech Stack:** Bash, `curl`, `apt-get`, `gsettings`, `grep -oP` (GNU grep with Perl regex)

---

### Task 1: Add `install_4k_video_downloader()` to `install_programs.sh`

**Files:**
- Modify: `distro_config/install_programs.sh` — add function before `install_utilities()` (~line 2612) and add call inside `install_utilities()` after the utilities loop (~line 2641)

- [ ] **Step 1: Verify baseline syntax**

```bash
bash -n distro_config/install_programs.sh
```
Expected: no output (clean syntax).

- [ ] **Step 2: Add the installer function**

Insert the following block immediately before the `install_utilities()` function definition (before line 2613):

```bash
install_4k_video_downloader() {
    if command_exists 4kvideodownloaderplus; then
        print_status "info" "4K Video Downloader Plus already installed"
        return 0
    fi

    if [ "$PACKAGE_MANAGER" != "apt" ]; then
        print_status "warning" "4K Video Downloader Plus: manual install required for non-apt distros"
        print_status "config" "  Download from: https://www.4kdownload.com/downloads"
        return 1
    fi

    print_status "info" "Installing 4K Video Downloader Plus..."

    local fallback_url="https://dl.4kdownload.com/app/4kvideodownloaderplus_26.1.0-1_amd64.deb"
    local deb_url

    deb_url=$(curl -fsSL --max-time 10 "https://www.4kdownload.com/downloads" 2>/dev/null \
        | grep -oP 'https://dl\.4kdownload\.com/app/4kvideodownloaderplus_[\d.]+-1_amd64\.deb' \
        | head -1)

    if [ -z "$deb_url" ]; then
        print_status "warning" "Could not scrape latest version, using fallback: $fallback_url"
        deb_url="$fallback_url"
    else
        print_status "info" "Latest version URL: $deb_url"
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)

    if wget -O "$tmp_dir/4kvideodownloaderplus.deb" "$deb_url" 2>>"$LOG_FILE" || \
       curl -L -o "$tmp_dir/4kvideodownloaderplus.deb" "$deb_url" 2>>"$LOG_FILE"; then
        if sudo apt-get install -y "$tmp_dir/4kvideodownloaderplus.deb"; then
            print_status "success" "4K Video Downloader Plus installed"
        else
            print_status "error" "4K Video Downloader Plus installation failed"
        fi
    else
        print_status "error" "Failed to download 4K Video Downloader Plus from: $deb_url"
    fi

    rm -rf "$tmp_dir"
}
```

- [ ] **Step 3: Add the call inside `install_utilities()`**

In `install_utilities()`, after the closing `done` of the utilities loop (after line 2640, before the `# Piper for gaming peripherals` comment), add:

```bash
    install_4k_video_downloader
```

The context around the insertion point looks like:
```bash
    done        # ← end of utilities loop (line 2640)

    install_4k_video_downloader   # ← add this line

    # Piper for gaming peripherals
    print_status "info" "Installing Piper..."
```

- [ ] **Step 4: Verify syntax after changes**

```bash
bash -n distro_config/install_programs.sh
```
Expected: no output (clean syntax).

- [ ] **Step 5: Commit**

```bash
git add distro_config/install_programs.sh
git commit -m "feat(distro_config): add 4K Video Downloader Plus installer"
```

---

### Task 2: Remove VLC from Utilitários and create Media folder in `ubuntu_workspace.sh`

**Files:**
- Modify: `distro_config/ubuntu_workspace.sh` — three locations:
  1. `utility_app_names` array (~line 549): remove VLC entries
  2. `organize_app_folders()` body (~line 623): add Media folder section after Utilitários block
  3. `ordered_folder_ids` loop (~line 1079): add `'Media'`

- [ ] **Step 1: Verify baseline syntax**

```bash
bash -n distro_config/ubuntu_workspace.sh
```
Expected: no output (clean syntax).

- [ ] **Step 2: Remove VLC from `utility_app_names`**

In `utility_app_names` (~line 549), remove the two VLC entries:

```bash
        'vlc.desktop' 'org.videolan.VLC.desktop'
```

The surrounding lines for context:
```bash
        'org.freedesktop.Piper.desktop' 'piper.desktop'
        # ← remove the vlc.desktop line here
        'org.gnome.Logs.desktop' 'gnome-logs.desktop' 'gnome-system-log.desktop'
```

- [ ] **Step 3: Add Media folder section after the Utilitários block**

Insert the following block immediately after the closing `fi` of the Utilitários section (~line 623), before the `# ==================== SHARING FOLDER ====================` comment:

```bash
    # ==================== MEDIA FOLDER ====================
    print_status "info" "Creating Media folder..."
    local media_apps=()

    local media_app_names=(
        'vlc.desktop' 'org.videolan.VLC.desktop'
        '4kvideodownloaderplus.desktop'
        'rhythmbox.desktop' 'org.gnome.Rhythmbox3.desktop'
        'cheese.desktop' 'org.gnome.Cheese.desktop'
        'org.gnome.Music.desktop'
        'totem.desktop' 'org.gnome.Totem.desktop'
        'org.gnome.SoundRecorder.desktop' 'gnome-sound-recorder.desktop'
        'celluloid.desktop' 'io.github.celluloid_mpv.Celluloid.desktop'
        'mpv.desktop' 'io.mpv.Mpv.desktop'
        'handbrake.desktop' 'fr.handbrake.ghb.desktop'
        'kdenlive.desktop' 'org.kde.kdenlive.desktop'
        'pitivi.desktop' 'org.pitivi.Pitivi.desktop'
    )

    for app in "${media_app_names[@]}"; do
        if result=$(find_app_desktop_file "$app"); then
            media_apps+=("'$result'")
        fi
    done

    shopt -s nullglob
    for desktop_file in /usr/share/applications/*vlc*.desktop \
                        /usr/share/applications/*4kdownload*.desktop \
                        /usr/share/applications/*4kvideo*.desktop \
                        /var/lib/snapd/desktop/applications/*vlc*.desktop \
                        /var/lib/flatpak/exports/share/applications/*vlc*.desktop \
                        /var/lib/flatpak/exports/share/applications/*4kdownload*.desktop \
                        "$HOME/.local/share/applications"/*vlc*.desktop \
                        "$HOME/.local/share/applications"/*4kdownload*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            if [[ ! " ${media_apps[@]} " =~ " '$basename' " ]]; then
                media_apps+=("'$basename'")
            fi
        fi
    done
    shopt -u nullglob

    media_apps=($(echo "${media_apps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    if [ ${#media_apps[@]} -gt 0 ]; then
        local media_apps_str=$(IFS=,; echo "${media_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Media/ name 'Media'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Media/ apps "[${media_apps_str}]"
        folder_ids+=("'Media'")
        print_status "success" "Media folder created with ${#media_apps[@]} apps"
        print_status "config" "  Apps: ${media_apps_str}"
    else
        print_status "warning" "No Media apps found"
    fi
```

- [ ] **Step 4: Add `'Media'` to `ordered_folder_ids`**

In the `ordered_folder_ids` loop (~line 1079), add `"'Media'"` after `"'Office'"`:

Change:
```bash
    for folder in "'Sistema'" "'Seguranca'" "'Utilitarios'" "'Sharing'" "'IRPF'" "'DEV'" "'Ereader'" "'Office'" "'OrgPessoal'" "'AmbienteVirtual'" "'Browsers'"; do
```

To:
```bash
    for folder in "'Sistema'" "'Seguranca'" "'Utilitarios'" "'Sharing'" "'IRPF'" "'DEV'" "'Ereader'" "'Office'" "'Media'" "'OrgPessoal'" "'AmbienteVirtual'" "'Browsers'"; do
```

- [ ] **Step 5: Verify syntax after all changes**

```bash
bash -n distro_config/ubuntu_workspace.sh
```
Expected: no output (clean syntax).

- [ ] **Step 6: Commit**

```bash
git add distro_config/ubuntu_workspace.sh
git commit -m "feat(distro_config): add Media folder, move VLC from Utilitários"
```

---

### Task 3: Update CLAUDE.md folder table

**Files:**
- Already done: `distro_config/CLAUDE.md` — `Media` row was added to the folder table during design phase.

- [ ] **Step 1: Verify the entry exists**

```bash
grep -n "Media" distro_config/CLAUDE.md
```
Expected output includes:
```
| `Media` | Media | Video players, audio players, media tools |
```

- [ ] **Step 2: Commit CLAUDE.md and spec/plan docs together**

```bash
git add distro_config/CLAUDE.md \
        docs/superpowers/specs/2026-04-21-4k-downloader-media-folder-design.md \
        docs/superpowers/plans/2026-04-21-4k-downloader-media-folder.md
git commit -m "docs: add Media folder spec, plan, and CLAUDE.md update"
```
