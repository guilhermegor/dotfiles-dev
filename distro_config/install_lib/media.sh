#!/bin/bash
#
# distro_config/install_lib/media.sh
#
# Media tools: video downloaders, CD/DVD ripping. Sourced by install_programs.sh.
# Depends on: print_status, command_exists, install_package, $PACKAGE_MANAGER,
#             $INSTALL_CMD, $LOG_FILE

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "media.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# ============================================================================
# INSTALL FUNCTIONS
# ============================================================================

install_4k_video_downloader() {
    if dpkg -l 4kvideodownloaderplus 2>/dev/null | grep -q '^ii'; then
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
       run_or_echo curl -L -o "$tmp_dir/4kvideodownloaderplus.deb" "$deb_url" 2>>"$LOG_FILE"; then
        if run_or_echo sudo apt-get install -y "$tmp_dir/4kvideodownloaderplus.deb"; then
            rm -rf "$tmp_dir"
            if dpkg -l 4kvideodownloaderplus 2>/dev/null | grep -q '^ii'; then
                print_status "success" "4K Video Downloader Plus is ready"
            else
                print_status "warning" "4K Video Downloader Plus installed but could not be verified"
            fi
        else
            rm -rf "$tmp_dir"
            print_status "error" "4K Video Downloader Plus installation failed"
            return 1
        fi
    else
        rm -rf "$tmp_dir"
        print_status "error" "Failed to download 4K Video Downloader Plus from: $deb_url"
        return 1
    fi
}

install_asunder() {
    print_status "section" "ASUNDER CD RIPPER"

    if command_exists asunder || dpkg -l 2>/dev/null | grep -q "^ii  asunder "; then
        print_status "info" "Asunder already installed"
        return 0
    fi

    print_status "info" "Installing Asunder CD ripper..."

    if install_package "asunder" "asunder" "asunder" "asunder"; then
        print_status "success" "Asunder installed"
    else
        print_status "error" "Could not install Asunder. Please install manually."
        return 1
    fi

    if command_exists asunder; then
        print_status "success" "Asunder is ready to use"
        print_status "info" "Asunder: CD ripper and encoder"
    else
        print_status "warning" "Asunder installation could not be verified"
    fi
}

install_handbrake() {
    print_status "section" "HANDBRAKE DVD RIPPER"

    if command_exists handbrake-gtk || command_exists ghb || \
       flatpak list 2>/dev/null | grep -q "fr.handbrake.ghb" || \
       dpkg -l 2>/dev/null | grep -q "^ii  handbrake "; then
        print_status "info" "HandBrake already installed"
        return 0
    fi

    print_status "info" "Installing HandBrake..."

    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Installing DVD decryption support (libdvd-pkg)..."
            if run_or_echo sudo apt-get install -y libdvd-pkg 2>>"$LOG_FILE"; then
                sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure libdvd-pkg 2>>"$LOG_FILE" || true
                print_status "success" "DVD decryption support installed"
            else
                print_status "warning" "libdvd-pkg not available; encrypted DVDs may not play"
            fi

            if command_exists flatpak; then
                run_or_echo flatpak install -y flathub fr.handbrake.ghb 2>>"$LOG_FILE" && \
                    print_status "success" "HandBrake installed via Flatpak" && return 0
            fi

            install_package "HandBrake" "handbrake" "handbrake" "handbrake" || {
                print_status "error" "Could not install HandBrake. Please install manually."
                return 1
            }
            ;;
        dnf|yum|pacman|zypper)
            if command_exists flatpak; then
                run_or_echo flatpak install -y flathub fr.handbrake.ghb 2>>"$LOG_FILE" && \
                    print_status "success" "HandBrake installed via Flatpak" && return 0
            fi
            install_package "HandBrake" "handbrake" "handbrake" "handbrake" || \
                print_status "warning" "HandBrake not available; try: flatpak install flathub fr.handbrake.ghb"
            ;;
    esac

    if command_exists handbrake-gtk || command_exists ghb || \
       flatpak list 2>/dev/null | grep -q "fr.handbrake.ghb"; then
        print_status "success" "HandBrake is ready to use"
        print_status "info" "HandBrake: DVD and video transcoder"
        print_status "config" "Supports MP4/MKV output, subtitle and audio track selection"
    else
        print_status "warning" "HandBrake installation could not be verified"
    fi
}

# ============================================================================
# REGISTRY
# ============================================================================

INSTALL_REGISTRY+=(
    "install_4k_video_downloader:4K Video Downloader Plus:Media:com.4kdownload.4kvideodownloaderplus.desktop"
    "install_asunder:Asunder CD Ripper:Media:asunder.desktop"
    "install_handbrake:HandBrake DVD Ripper:Media:fr.handbrake.ghb.desktop"
)
