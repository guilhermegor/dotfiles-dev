#!/bin/bash
#
# distro_config/install_lib/sharing.sh
#
# File-sharing, remote-desktop, sync, antivirus. Sourced by install_programs.sh.
# Depends on: print_status, command_exists, install_package, $PACKAGE_MANAGER,
#             $INSTALL_CMD, $DOWNLOADS_DIR, $DISTRO, $UBUNTU_VERSION, $UBUNTU_CODENAME,
#             $LOG_FILE

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "sharing.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# ============================================================================
# LOCALSEND
# ============================================================================

install_localsend() {
    print_status "section" "LOCALSEND"

    if command_exists localsend || flatpak list 2>/dev/null | grep -q "org.localsend.localsend_app"; then
        print_status "info" "LocalSend already installed"
        return 0
    fi

    cd "$DOWNLOADS_DIR" || return 1

    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Detecting system architecture..."
            local arch
            arch=$(dpkg --print-architecture)
            local download_arch=""

            case "$arch" in
                amd64)  download_arch="x86-64"; print_status "info" "Architecture: x86-64 (amd64)" ;;
                arm64)  download_arch="arm-64"; print_status "info" "Architecture: ARM 64-bit" ;;
                armhf)  download_arch="arm-32"; print_status "info" "Architecture: ARM 32-bit" ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    run_or_echo flatpak install -y flathub org.localsend.localsend_app
                    cd - > /dev/null || return 1
                    return 0
                    ;;
            esac

            print_status "info" "Fetching latest LocalSend release..."
            local latest_url
            latest_url=$(curl -s https://api.github.com/repos/localsend/localsend/releases/latest | \
                grep "browser_download_url.*linux-${download_arch}.deb" | head -n 1 | cut -d '"' -f 4)

            if [ -n "$latest_url" ] && [ "$latest_url" != "null" ]; then
                print_status "info" "Downloading LocalSend from GitHub..."
                print_status "config" "URL: $latest_url"

                if wget -O localsend.deb "$latest_url"; then
                    print_status "info" "Installing LocalSend..."
                    run_or_echo sudo dpkg -i localsend.deb
                    run_or_echo sudo apt-get install -f -y
                    print_status "success" "LocalSend installed via .deb package"
                else
                    print_status "warning" "Download failed. Installing via Flatpak..."
                    run_or_echo flatpak install -y flathub org.localsend.localsend_app
                    print_status "success" "LocalSend installed via Flatpak"
                fi
            else
                print_status "warning" "Could not fetch latest release. Installing via Flatpak..."
                run_or_echo flatpak install -y flathub org.localsend.localsend_app
                print_status "success" "LocalSend installed via Flatpak"
            fi
            ;;
        dnf|yum|zypper)
            print_status "info" "Detecting system architecture..."
            local arch
            arch=$(uname -m)
            local download_arch=""

            case "$arch" in
                x86_64)   download_arch="x86-64"; print_status "info" "Architecture: x86-64" ;;
                aarch64)  download_arch="arm-64"; print_status "info" "Architecture: ARM 64-bit" ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    run_or_echo flatpak install -y flathub org.localsend.localsend_app
                    cd - > /dev/null || return 1
                    return 0
                    ;;
            esac

            print_status "info" "Fetching latest LocalSend release..."
            local latest_url
            latest_url=$(curl -s https://api.github.com/repos/localsend/localsend/releases/latest | \
                grep "browser_download_url.*linux-${download_arch}.rpm" | head -n 1 | cut -d '"' -f 4)

            if [ -n "$latest_url" ] && [ "$latest_url" != "null" ]; then
                print_status "info" "Downloading LocalSend from GitHub..."
                print_status "config" "URL: $latest_url"

                if wget -O localsend.rpm "$latest_url"; then
                    print_status "info" "Installing LocalSend..."
                    if [ "$PACKAGE_MANAGER" = "zypper" ]; then
                        $INSTALL_CMD localsend.rpm
                    else
                        sudo $PACKAGE_MANAGER install -y localsend.rpm
                    fi
                    print_status "success" "LocalSend installed via .rpm package"
                else
                    print_status "warning" "Download failed. Installing via Flatpak..."
                    run_or_echo flatpak install -y flathub org.localsend.localsend_app
                    print_status "success" "LocalSend installed via Flatpak"
                fi
            else
                print_status "warning" "Could not fetch latest release. Installing via Flatpak..."
                run_or_echo flatpak install -y flathub org.localsend.localsend_app
                print_status "success" "LocalSend installed via Flatpak"
            fi
            ;;
        pacman)
            if command_exists yay; then
                print_status "info" "Installing LocalSend from AUR..."
                run_or_echo yay -S --noconfirm localsend-bin
                print_status "success" "LocalSend installed from AUR"
            else
                print_status "info" "yay not found. Installing LocalSend via Flatpak..."
                run_or_echo flatpak install -y flathub org.localsend.localsend_app
                print_status "success" "LocalSend installed via Flatpak"
            fi
            ;;
    esac

    print_status "info" "Configuring firewall for LocalSend..."
    case "$PACKAGE_MANAGER" in
        apt|pacman)
            if command_exists ufw; then
                run_or_echo sudo ufw allow 53317/tcp comment "LocalSend" 2>/dev/null
                run_or_echo sudo ufw allow 53317/udp comment "LocalSend" 2>/dev/null
                run_or_echo sudo ufw reload 2>/dev/null
                print_status "success" "Firewall configured for LocalSend (port 53317)"
            else
                print_status "info" "UFW not installed. Skipping firewall configuration."
            fi
            ;;
        dnf|yum|zypper)
            if command_exists firewall-cmd; then
                run_or_echo sudo firewall-cmd --permanent --add-port=53317/tcp 2>/dev/null
                run_or_echo sudo firewall-cmd --permanent --add-port=53317/udp 2>/dev/null
                run_or_echo sudo firewall-cmd --reload 2>/dev/null
                print_status "success" "Firewall configured for LocalSend (port 53317)"
            else
                print_status "info" "firewalld not installed. Skipping firewall configuration."
            fi
            ;;
    esac

    print_status "info" "LocalSend: Secure file sharing on your local network"
    print_status "config" "Available on Android, iOS, Windows, macOS, and Linux"

    cd - > /dev/null || return 1
}

# ============================================================================
# RUSTDESK
# ============================================================================

install_rustdesk() {
    print_status "section" "RUSTDESK REMOTE DESKTOP"

    if command_exists rustdesk || flatpak list 2>/dev/null | grep -q "com.rustdesk.RustDesk" || dpkg -l 2>/dev/null | grep -q "^ii  rustdesk "; then
        print_status "info" "RustDesk already installed"
        return 0
    fi

    cd "$DOWNLOADS_DIR" || return 1

    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Detecting system architecture..."
            local arch
            arch=$(dpkg --print-architecture)
            local download_arch=""

            case "$arch" in
                amd64)  download_arch="x86_64"; print_status "info" "Architecture: x86-64 (amd64)" ;;
                arm64)  download_arch="aarch64"; print_status "info" "Architecture: ARM 64-bit" ;;
                armhf)  download_arch="armv7"; print_status "info" "Architecture: ARM 32-bit" ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    run_or_echo flatpak install -y flathub com.rustdesk.RustDesk
                    cd - > /dev/null || return 1
                    return 0
                    ;;
            esac

            print_status "info" "Fetching latest RustDesk release..."
            local latest_info
            latest_info=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest)
            local latest_version
            latest_version=$(echo "$latest_info" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

            if [ -z "$latest_version" ]; then
                print_status "warning" "Could not fetch latest version, using fallback"
                latest_version="1.4.4"
            fi

            print_status "info" "Latest RustDesk version: $latest_version"

            local deb_filename="rustdesk-${latest_version}-${download_arch}.deb"
            local latest_url="https://github.com/rustdesk/rustdesk/releases/download/${latest_version}/${deb_filename}"

            print_status "info" "Downloading RustDesk from GitHub..."
            print_status "config" "URL: $latest_url"

            if wget -O rustdesk.deb "$latest_url"; then
                print_status "success" "RustDesk downloaded successfully"

                print_status "info" "Checking for existing dependency issues..."
                run_or_echo sudo apt-get install -f -y || true

                print_status "info" "Installing RustDesk dependencies..."
                sudo apt-get update

                local essential_deps=(
                    "libxdo3"
                    "libgtk-3-0"
                    "libxtst6"
                    "libxcb-randr0"
                    "libxcb-shape0"
                    "libxcb-xfixes0"
                    "libxcb-keysyms1"
                    "libxcb-image0"
                    "libxcb-xtest0"
                )

                local dep
                for dep in "${essential_deps[@]}"; do
                    print_status "info" "Installing $dep..."
                    run_or_echo sudo apt-get install -y "$dep" || print_status "warning" "Failed to install $dep, continuing..."
                done

                if run_or_echo sudo apt-get install -y libayatana-appindicator3-1 2>/dev/null; then
                    print_status "info" "Installed libayatana-appindicator3-1"
                elif run_or_echo sudo apt-get install -y libappindicator3-1 2>/dev/null; then
                    print_status "info" "Installed libappindicator3-1"
                else
                    print_status "warning" "Could not install appindicator library, continuing..."
                fi

                print_status "info" "Installing RustDesk..."
                if run_or_echo sudo dpkg -i rustdesk.deb; then
                    print_status "success" "RustDesk installed via .deb package"
                else
                    print_status "warning" "dpkg installation had issues, fixing dependencies..."
                    run_or_echo sudo apt-get install -f -y

                    if dpkg -l | grep -q "^ii  rustdesk "; then
                        print_status "success" "RustDesk installed after fixing dependencies"
                    else
                        print_status "error" "Failed to install RustDesk via .deb package"
                        print_status "info" "Trying Flatpak installation..."
                        if run_or_echo flatpak install -y flathub com.rustdesk.RustDesk; then
                            print_status "success" "RustDesk installed via Flatpak"
                        else
                            print_status "error" "All installation methods failed"
                            print_status "info" "You can install RustDesk manually from:"
                            print_status "config" "https://github.com/rustdesk/rustdesk/releases"
                        fi
                    fi
                fi
            else
                print_status "warning" "Download failed. Installing via Flatpak..."
                if run_or_echo flatpak install -y flathub com.rustdesk.RustDesk; then
                    print_status "success" "RustDesk installed via Flatpak"
                else
                    print_status "error" "Flatpak installation also failed"
                fi
            fi
            ;;
        dnf|yum|zypper)
            print_status "info" "Detecting system architecture..."
            local arch
            arch=$(uname -m)
            local download_arch=""

            case "$arch" in
                x86_64)   download_arch="x86_64"; print_status "info" "Architecture: x86-64" ;;
                aarch64)  download_arch="aarch64"; print_status "info" "Architecture: ARM 64-bit" ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    run_or_echo flatpak install -y flathub com.rustdesk.RustDesk
                    cd - > /dev/null || return 1
                    return 0
                    ;;
            esac

            print_status "info" "Fetching latest RustDesk release..."
            local latest_info
            latest_info=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest)
            local latest_version
            latest_version=$(echo "$latest_info" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

            if [ -z "$latest_version" ]; then
                print_status "warning" "Could not fetch latest version, using fallback"
                latest_version="1.4.4"
            fi

            print_status "info" "Latest RustDesk version: $latest_version"

            local rpm_filename="rustdesk-${latest_version}-${download_arch}.rpm"
            local latest_url="https://github.com/rustdesk/rustdesk/releases/download/${latest_version}/${rpm_filename}"

            print_status "info" "Downloading RustDesk from GitHub..."
            print_status "config" "URL: $latest_url"

            if wget -O rustdesk.rpm "$latest_url"; then
                print_status "info" "Installing RustDesk..."
                if [ "$PACKAGE_MANAGER" = "zypper" ]; then
                    $INSTALL_CMD rustdesk.rpm
                else
                    sudo $PACKAGE_MANAGER install -y rustdesk.rpm
                fi
                print_status "success" "RustDesk installed via .rpm package"
            else
                print_status "warning" "Download failed. Installing via Flatpak..."
                run_or_echo flatpak install -y flathub com.rustdesk.RustDesk
                print_status "success" "RustDesk installed via Flatpak"
            fi
            ;;
        pacman)
            if command_exists yay; then
                print_status "info" "Installing RustDesk from AUR..."
                run_or_echo yay -S --noconfirm rustdesk-bin
                print_status "success" "RustDesk installed from AUR"
            else
                print_status "info" "yay not found. Installing RustDesk via Flatpak..."
                run_or_echo flatpak install -y flathub com.rustdesk.RustDesk
                print_status "success" "RustDesk installed via Flatpak"
            fi
            ;;
    esac

    print_status "info" "Configuring firewall for RustDesk..."
    case "$PACKAGE_MANAGER" in
        apt|pacman)
            if command_exists ufw; then
                run_or_echo sudo ufw allow 21115:21119/tcp comment "RustDesk" 2>/dev/null
                run_or_echo sudo ufw allow 21115:21119/udp comment "RustDesk" 2>/dev/null
                run_or_echo sudo ufw reload 2>/dev/null
                print_status "success" "Firewall configured for RustDesk (ports 21115-21119)"
            else
                print_status "info" "UFW not installed. Skipping firewall configuration."
            fi
            ;;
        dnf|yum|zypper)
            if command_exists firewall-cmd; then
                run_or_echo sudo firewall-cmd --permanent --add-port=21115-21119/tcp 2>/dev/null
                run_or_echo sudo firewall-cmd --permanent --add-port=21115-21119/udp 2>/dev/null
                run_or_echo sudo firewall-cmd --reload 2>/dev/null
                print_status "success" "Firewall configured for RustDesk (ports 21115-21119)"
            else
                print_status "info" "firewalld not installed. Skipping firewall configuration."
            fi
            ;;
    esac

    if command_exists rustdesk || dpkg -l 2>/dev/null | grep -q "^ii  rustdesk " || flatpak list 2>/dev/null | grep -q "com.rustdesk.RustDesk"; then
        print_status "success" "RustDesk is ready to use"
        print_status "info" "RustDesk: Open-source remote desktop software"
        print_status "config" "Alternative to TeamViewer and AnyDesk"
        print_status "config" "Launch with: rustdesk"
        print_status "config" "You can set up your own relay server for better performance"

        if command_exists rustdesk; then
            rustdesk --version 2>&1 | head -n1 >> "$LOG_FILE" || true
        fi
    else
        print_status "warning" "RustDesk installation could not be verified"
        print_status "info" "You can install RustDesk manually from:"
        print_status "config" "https://github.com/rustdesk/rustdesk/releases"
        print_status "config" "Or via Flatpak: flatpak install flathub com.rustdesk.RustDesk"
    fi

    cd - > /dev/null || return 1
}

# ============================================================================
# INSYNC (Google Drive client)
# ============================================================================

install_insync() {
    print_status "section" "INSYNC DOWNLOAD AND INSTALLATION"

    if command_exists insync || dpkg -l 2>/dev/null | grep -q insync; then
        print_status "info" "Insync already installed"
        return 0
    fi

    if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]]; then
        print_status "warning" "Insync installation currently only supported on Ubuntu/Debian"
        print_status "info" "Please install Insync manually for your distribution"
        return 1
    fi

    cd "$DOWNLOADS_DIR" || return 1

    local insync_codename=""
    case "$UBUNTU_CODENAME" in
        noble)      insync_codename="noble" ;;
        jammy)      insync_codename="jammy" ;;
        focal)      insync_codename="focal" ;;
        bionic)     insync_codename="bionic" ;;
        *)
            print_status "warning" "Unknown Ubuntu codename: $UBUNTU_CODENAME, using noble as fallback"
            insync_codename="noble"
            ;;
    esac

    local insync_version="3.9.6.60027"
    local insync_deb_url="https://cdn.insynchq.com/builds/linux/${insync_version}/insync_${insync_version}-${insync_codename}_amd64.deb"
    local insync_deb_file="insync_${insync_version}-${insync_codename}_amd64.deb"

    print_status "info" "Detected Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"
    print_status "info" "Downloading Insync for $insync_codename..."
    print_status "config" "Download URL: $insync_deb_url"

    if wget -O "$insync_deb_file" "$insync_deb_url" 2>&1 | tee -a "$LOG_FILE"; then
        if [ -f "$insync_deb_file" ] && [ -s "$insync_deb_file" ]; then
            print_status "success" "Insync downloaded successfully"

            if file "$insync_deb_file" | grep -q "Debian"; then
                print_status "info" "Installing Insync..."

                if run_or_echo sudo dpkg -i "$insync_deb_file"; then
                    print_status "success" "Insync installed successfully"
                    run_or_echo sudo apt-get install -f -y

                    if command_exists insync || dpkg -l | grep -q insync; then
                        print_status "success" "Insync installation verified"
                        print_status "info" "Insync version: $insync_version"
                        print_status "info" "Starting Insync..."
                        insync start &>> "$LOG_FILE" &
                        print_status "success" "Insync started"
                    else
                        print_status "warning" "Insync installed but command not found"
                    fi
                else
                    print_status "error" "Failed to install Insync package"
                    print_status "info" "Attempting to fix dependencies..."
                    run_or_echo sudo apt-get install -f -y

                    if run_or_echo sudo dpkg -i "$insync_deb_file"; then
                        print_status "success" "Insync installed after fixing dependencies"
                    else
                        print_status "error" "Failed to install Insync even after fixing dependencies"
                        return 1
                    fi
                fi
            else
                print_status "error" "Downloaded file is not a valid .deb package"
                rm -f "$insync_deb_file"
                return 1
            fi
        else
            print_status "error" "Downloaded file is empty or missing"
            return 1
        fi
    else
        print_status "error" "Failed to download Insync"
        print_status "info" "Please check your internet connection and try again"
        print_status "info" "Or download manually from: https://www.insynchq.com/downloads"
        return 1
    fi

    if [ ! -f "$insync_deb_file" ] || [ ! -s "$insync_deb_file" ]; then
        print_status "warning" "Primary download method failed, trying alternative..."

        local alt_url="https://cdn.insynchq.com/builds/linux/3.9.6.60027/insync_3.9.6.60027-noble_amd64.deb"
        print_status "info" "Trying alternative URL: $alt_url"

        if curl -L -o "insync_alternative.deb" "$alt_url" 2>&1 | tee -a "$LOG_FILE"; then
            if [ -f "insync_alternative.deb" ] && [ -s "insync_alternative.deb" ]; then
                print_status "info" "Installing Insync from alternative download..."
                run_or_echo sudo dpkg -i "insync_alternative.deb"
                run_or_echo sudo apt-get install -f -y
                print_status "success" "Insync installed from alternative download"
            else
                print_status "error" "Alternative download also failed"
                return 1
            fi
        else
            print_status "error" "All download methods failed"
            return 1
        fi
    fi

    print_status "info" "Insync: Google Drive sync client for Linux"
    print_status "config" "Launch with: insync start"
    print_status "config" "Configure with: insync show"

    cd - > /dev/null || return 1
}

# ============================================================================
# CLAMAV ANTIVIRUS
# ============================================================================

install_clamav() {
    print_status "section" "ANTIVIRUS (CLAMAV)"

    print_status "info" "Installing ClamAV..."
    run_or_echo sudo apt-get install -y clamav clamav-daemon clamtk

    print_status "info" "Updating virus definitions..."
    run_or_echo sudo systemctl stop clamav-freshclam
    sudo freshclam
    run_or_echo sudo systemctl start clamav-freshclam

    print_status "success" "ClamAV installed and configured"
}

# ============================================================================
# REGISTRY
# ============================================================================

INSTALL_REGISTRY+=(
    "install_localsend:LocalSend File Sharing:Sharing:org.localsend.localsend_app.desktop"
    "install_rustdesk:RustDesk Remote Desktop:Sharing:rustdesk.desktop"
    "install_insync:Insync (Google Drive):Sharing:insync.desktop"
    "install_clamav:ClamAV Antivirus:Seguranca:clamtk.desktop"
)
