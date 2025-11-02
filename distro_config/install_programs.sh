#!/bin/bash

# Multi-Distribution Development Environment Setup Script
# Supports: Ubuntu/Debian, Fedora/RHEL/CentOS, Arch Linux

set -e  # Exit on error

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Global variables
LOG_FILE="$HOME/setup_$(date +%Y%m%d_%H%M%S).log"
DOWNLOADS_DIR="$HOME/Downloads"
DISTRO=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""
UPGRADE_CMD=""

# ============================================================================
# DISTRO DETECTION
# ============================================================================

detect_distro() {
    print_status "info" "Detecting Linux distribution..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        
        case "$DISTRO" in
            ubuntu|debian|pop|linuxmint)
                PACKAGE_MANAGER="apt"
                INSTALL_CMD="sudo apt-get install -y"
                UPDATE_CMD="sudo apt update"
                UPGRADE_CMD="sudo apt upgrade -y"
                print_status "success" "Detected Debian-based system: $PRETTY_NAME"
                ;;
            fedora|rhel|centos|rocky|almalinux)
                PACKAGE_MANAGER="dnf"
                INSTALL_CMD="sudo dnf install -y"
                UPDATE_CMD="sudo dnf check-update || true"
                UPGRADE_CMD="sudo dnf upgrade -y"
                print_status "success" "Detected Red Hat-based system: $PRETTY_NAME"
                ;;
            arch|manjaro|endeavouros)
                PACKAGE_MANAGER="pacman"
                INSTALL_CMD="sudo pacman -S --noconfirm"
                UPDATE_CMD="sudo pacman -Sy"
                UPGRADE_CMD="sudo pacman -Syu --noconfirm"
                print_status "success" "Detected Arch-based system: $PRETTY_NAME"
                ;;
            opensuse*|sles)
                PACKAGE_MANAGER="zypper"
                INSTALL_CMD="sudo zypper install -y"
                UPDATE_CMD="sudo zypper refresh"
                UPGRADE_CMD="sudo zypper update -y"
                print_status "success" "Detected openSUSE/SLES system: $PRETTY_NAME"
                ;;
            *)
                print_status "warning" "Unknown distribution: $DISTRO"
                print_status "warning" "Attempting to detect package manager..."
                detect_package_manager_fallback
                ;;
        esac
    else
        print_status "warning" "/etc/os-release not found"
        detect_package_manager_fallback
    fi
    
    echo "DISTRO=$DISTRO" >> "$LOG_FILE"
    echo "PACKAGE_MANAGER=$PACKAGE_MANAGER" >> "$LOG_FILE"
}

detect_package_manager_fallback() {
    if command_exists apt-get; then
        PACKAGE_MANAGER="apt"
        INSTALL_CMD="sudo apt-get install -y"
        UPDATE_CMD="sudo apt update"
        UPGRADE_CMD="sudo apt upgrade -y"
        print_status "info" "Using apt package manager"
    elif command_exists dnf; then
        PACKAGE_MANAGER="dnf"
        INSTALL_CMD="sudo dnf install -y"
        UPDATE_CMD="sudo dnf check-update || true"
        UPGRADE_CMD="sudo dnf upgrade -y"
        print_status "info" "Using dnf package manager"
    elif command_exists yum; then
        PACKAGE_MANAGER="yum"
        INSTALL_CMD="sudo yum install -y"
        UPDATE_CMD="sudo yum check-update || true"
        UPGRADE_CMD="sudo yum upgrade -y"
        print_status "info" "Using yum package manager"
    elif command_exists pacman; then
        PACKAGE_MANAGER="pacman"
        INSTALL_CMD="sudo pacman -S --noconfirm"
        UPDATE_CMD="sudo pacman -Sy"
        UPGRADE_CMD="sudo pacman -Syu --noconfirm"
        print_status "info" "Using pacman package manager"
    elif command_exists zypper; then
        PACKAGE_MANAGER="zypper"
        INSTALL_CMD="sudo zypper install -y"
        UPDATE_CMD="sudo zypper refresh"
        UPGRADE_CMD="sudo zypper update -y"
        print_status "info" "Using zypper package manager"
    else
        print_status "error" "No supported package manager found!"
        print_status "error" "Supported: apt, dnf, yum, pacman, zypper"
        exit 1
    fi
}

# Helper function to install packages with distro-specific names
install_package() {
    local package_name="$1"
    local debian_name="${2:-$package_name}"
    local fedora_name="${3:-$package_name}"
    local arch_name="${4:-$package_name}"
    
    case "$PACKAGE_MANAGER" in
        apt)
            $INSTALL_CMD "$debian_name"
            ;;
        dnf|yum)
            $INSTALL_CMD "$fedora_name"
            ;;
        pacman)
            $INSTALL_CMD "$arch_name"
            ;;
        zypper)
            $INSTALL_CMD "$debian_name"  # openSUSE typically uses similar names to Debian
            ;;
    esac
}

# Helper function to download and install .deb or .rpm packages
install_from_url() {
    local url="$1"
    local package_name="$2"
    
    cd "$DOWNLOADS_DIR"
    
    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Downloading ${package_name}.deb..."
            wget -O "${package_name}.deb" "$url"
            print_status "info" "Installing ${package_name}..."
            sudo dpkg -i "${package_name}.deb"
            sudo apt-get install -f -y  # Fix dependencies
            ;;
        dnf|yum)
            # For RPM-based systems, we need to find the RPM URL
            local rpm_url="${url//.deb/.rpm}"
            rpm_url="${rpm_url//amd64/x86_64}"
            print_status "info" "Downloading ${package_name}.rpm..."
            wget -O "${package_name}.rpm" "$rpm_url" || {
                print_status "warning" "RPM package not available from this URL"
                print_status "info" "Please install $package_name manually or from your distro's repos"
                return 1
            }
            print_status "info" "Installing ${package_name}..."
            sudo $PACKAGE_MANAGER install -y "${package_name}.rpm"
            ;;
        pacman)
            print_status "warning" "Package $package_name may need to be installed from AUR"
            print_status "info" "Try: yay -S $package_name"
            return 1
            ;;
    esac
    
    cd - > /dev/null
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success")
            echo -e "${GREEN}[✓]${NC} ${message}"
            ;;
        "error")
            echo -e "${RED}[✗]${NC} ${message}" >&2
            ;;
        "warning")
            echo -e "${YELLOW}[!]${NC} ${message}"
            ;;
        "info")
            echo -e "${BLUE}[i]${NC} ${message}"
            ;;
        "config")
            echo -e "${CYAN}[→]${NC} ${message}"
            ;;
        "section")
            echo -e "\n${MAGENTA}========================================${NC}"
            echo -e "${MAGENTA} $message${NC}"
            echo -e "${MAGENTA}========================================${NC}\n"
            ;;
        *)
            echo -e "[ ] ${message}"
            ;;
    esac
    
    # Log to file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$status] $message" >> "$LOG_FILE"
}

check_internet() {
    print_status "info" "Checking internet connectivity..."
    if ping -c 1 google.com &> /dev/null; then
        print_status "success" "Internet connection verified"
        return 0
    else
        print_status "error" "No internet connection detected"
        return 1
    fi
}

command_exists() {
    command -v "$1" &> /dev/null
}

install_if_missing() {
    local package="$1"
    if ! dpkg -l | grep -q "^ii  $package "; then
        print_status "info" "Installing $package..."
        sudo apt install -y "$package"
        print_status "success" "$package installed"
    else
        print_status "info" "$package already installed"
    fi
}

# ============================================================================
# SYSTEM UPDATE
# ============================================================================

update_system() {
    print_status "section" "SYSTEM UPDATE"
    
    print_status "info" "Updating package lists..."
    $UPDATE_CMD || { print_status "error" "Failed to update package lists"; return 1; }
    
    print_status "info" "Upgrading installed packages..."
    $UPGRADE_CMD || { print_status "warning" "Some packages failed to upgrade"; }
    
    print_status "success" "System updated successfully"
}

# ============================================================================
# CORE DEPENDENCIES
# ============================================================================

install_core_dependencies() {
    print_status "section" "CORE DEPENDENCIES"
    
    print_status "info" "Installing curl and SSL libraries..."
    case "$PACKAGE_MANAGER" in
        apt)
            $INSTALL_CMD libcurl4-openssl-dev libssl-dev
            ;;
        dnf|yum)
            $INSTALL_CMD libcurl-devel openssl-devel
            ;;
        pacman)
            $INSTALL_CMD curl openssl
            ;;
        zypper)
            $INSTALL_CMD libcurl-devel libopenssl-devel
            ;;
    esac
    
    print_status "info" "Installing geomview..."
    install_package "geomview" "geomview" "geomview" "geomview" || print_status "warning" "geomview not available for this distro"
    
    print_status "info" "Installing media codecs..."
    case "$PACKAGE_MANAGER" in
        apt)
            $INSTALL_CMD ubuntu-restricted-extras || print_status "warning" "Restricted extras not available"
            ;;
        dnf|yum)
            # Enable RPM Fusion for multimedia codecs
            print_status "info" "Installing RPM Fusion repositories..."
            sudo $PACKAGE_MANAGER install -y \
                https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true
            $INSTALL_CMD ffmpeg gstreamer1-plugins-{bad-\*,good-\*,base} gstreamer1-plugin-openh264 \
                gstreamer1-libav --exclude=gstreamer1-plugins-bad-free-devel || print_status "warning" "Some codecs failed"
            ;;
        pacman)
            $INSTALL_CMD ffmpeg gst-plugins-{base,good,bad,ugly} gst-libav
            ;;
    esac
    
    print_status "info" "Installing DKMS and Git..."
    install_package "dkms" "dkms" "dkms" "dkms"
    install_package "git" "git" "git" "git"
    
    if command_exists dkms; then
        dkms --version >> "$LOG_FILE"
    fi
    if command_exists git; then
        git --version >> "$LOG_FILE"
    fi
    
    print_status "success" "Core dependencies installed"
}

# ============================================================================
# PACKAGE MANAGERS
# ============================================================================

setup_flatpak() {
    print_status "section" "FLATPAK SETUP"
    
    if ! command_exists flatpak; then
        print_status "info" "Installing Flatpak..."
        install_package "flatpak" "flatpak" "flatpak" "flatpak"
        
        # Install GNOME Software plugin if on GNOME
        case "$PACKAGE_MANAGER" in
            apt)
                $INSTALL_CMD gnome-software-plugin-flatpak || print_status "info" "GNOME Software plugin not available"
                ;;
            dnf|yum)
                # Usually included by default on Fedora
                ;;
            pacman)
                # Usually don't need plugin on Arch
                ;;
        esac
    else
        print_status "info" "Flatpak already installed"
    fi
    
    print_status "info" "Adding Flathub repository..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    print_status "info" "Installing Flatseal (Flatpak permissions manager)..."
    flatpak install -y flathub com.github.tchx84.Flatseal
    
    print_status "success" "Flatpak configured"
}

install_homebrew() {
    print_status "section" "HOMEBREW PACKAGE MANAGER"
    
    # Check if brew is already installed
    if command_exists brew; then
        print_status "info" "Homebrew already installed"
        brew --version >> "$LOG_FILE"
        return 0
    fi
    
    print_status "info" "Installing Homebrew dependencies..."
    case "$PACKAGE_MANAGER" in
        apt)
            $INSTALL_CMD build-essential procps curl file git
            ;;
        dnf|yum)
            sudo $PACKAGE_MANAGER groupinstall -y 'Development Tools' || \
            sudo $PACKAGE_MANAGER group install -y 'Development Tools'
            $INSTALL_CMD procps-ng curl file git
            ;;
        pacman)
            $INSTALL_CMD base-devel procps-ng curl file git
            ;;
        zypper)
            sudo zypper install -y -t pattern devel_basis
            $INSTALL_CMD procps curl file git
            ;;
    esac
    
    print_status "info" "Downloading and installing Homebrew..."
    print_status "warning" "This may take several minutes..."
    
    # Install Homebrew (non-interactive)
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Configure Homebrew in shell
    print_status "config" "Configuring Homebrew environment..."
    
    # Detect Homebrew installation location
    local brew_path=""
    if [ -d "$HOME/.linuxbrew" ]; then
        brew_path="$HOME/.linuxbrew/bin/brew"
    elif [ -d "/home/linuxbrew/.linuxbrew" ]; then
        brew_path="/home/linuxbrew/.linuxbrew/bin/brew"
    fi
    
    if [ -z "$brew_path" ]; then
        print_status "error" "Homebrew installation path not found"
        return 1
    fi
    
    # Add to current session
    eval "$($brew_path shellenv)"
    
    # Add to .bashrc if not already present
    if ! grep -q "brew shellenv" ~/.bashrc; then
        echo "" >> ~/.bashrc
        echo "# Homebrew configuration" >> ~/.bashrc
        echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
        print_status "success" "Homebrew added to ~/.bashrc"
    fi
    
    # Add to .profile if not already present
    if ! grep -q "brew shellenv" ~/.profile; then
        echo "" >> ~/.profile
        echo "# Homebrew configuration" >> ~/.profile
        echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.profile
        print_status "success" "Homebrew added to ~/.profile"
    fi
    
    # Verify installation
    if command_exists brew; then
        print_status "info" "Testing Homebrew installation..."
        if brew install hello &>> "$LOG_FILE"; then
            print_status "success" "Homebrew installed and tested successfully"
            brew uninstall hello &>> "$LOG_FILE"  # Clean up test package
        else
            print_status "warning" "Homebrew installed but test failed"
        fi
    else
        print_status "error" "Homebrew installation failed"
        return 1
    fi
    
    print_status "success" "Homebrew configured successfully"
    print_status "info" "Homebrew version: $(brew --version | head -n1)"
}

install_asdf() {
    print_status "section" "ASDF VERSION MANAGER"
    
    # Check if asdf is already installed
    if command_exists asdf; then
        print_status "info" "asdf already installed"
        asdf --version >> "$LOG_FILE"
        return 0
    fi
    
    # Check if Homebrew is installed
    if ! command_exists brew; then
        print_status "warning" "Homebrew not found. Installing Homebrew first..."
        install_homebrew
    fi
    
    print_status "info" "Installing asdf via Homebrew..."
    brew install asdf
    
    # Configure asdf in shell
    print_status "config" "Configuring asdf environment..."
    
    # Add to .bashrc if not already present
    if ! grep -q "asdf.sh" ~/.bashrc; then
        echo "" >> ~/.bashrc
        echo "# asdf version manager" >> ~/.bashrc
        echo '. $(brew --prefix asdf)/libexec/asdf.sh' >> ~/.bashrc
        print_status "success" "asdf added to ~/.bashrc"
    fi
    
    # Add to .profile if not already present
    if ! grep -q "asdf.sh" ~/.profile; then
        echo "" >> ~/.profile
        echo "# asdf version manager" >> ~/.profile
        echo '. $(brew --prefix asdf)/libexec/asdf.sh' >> ~/.profile
        print_status "success" "asdf added to ~/.profile"
    fi
    
    # Source asdf for current session
    if [ -f "$(brew --prefix asdf)/libexec/asdf.sh" ]; then
        . "$(brew --prefix asdf)/libexec/asdf.sh"
    fi
    
    # Verify installation
    if command_exists asdf; then
        print_status "success" "asdf installed successfully"
        print_status "info" "asdf version: $(asdf --version)"
        print_status "info" "Available commands: asdf plugin list all, asdf plugin add <name>, asdf install <name> <version>"
    else
        print_status "warning" "asdf installed but not available in current session"
        print_status "info" "Please run: source ~/.bashrc"
    fi
    
    print_status "success" "asdf configured successfully"
}

# ============================================================================
# SECURITY
# ============================================================================

setup_firewall() {
    print_status "section" "FIREWALL SETUP"
    
    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Enabling UFW firewall..."
            if ! command_exists ufw; then
                $INSTALL_CMD ufw
            fi
            sudo ufw --force enable
            ;;
        dnf|yum)
            print_status "info" "Enabling firewalld..."
            if ! command_exists firewall-cmd; then
                $INSTALL_CMD firewalld
            fi
            sudo systemctl enable --now firewalld
            ;;
        pacman)
            print_status "info" "Installing UFW..."
            if ! command_exists ufw; then
                $INSTALL_CMD ufw
            fi
            sudo systemctl enable --now ufw
            sudo ufw --force enable
            ;;
        zypper)
            print_status "info" "Enabling firewalld..."
            if ! command_exists firewall-cmd; then
                $INSTALL_CMD firewalld
            fi
            sudo systemctl enable --now firewalld
            ;;
    esac
    
    print_status "info" "Configuring KDE Connect ports..."
    case "$PACKAGE_MANAGER" in
        apt|pacman)
            sudo ufw allow 1714:1764/udp
            sudo ufw allow 1714:1764/tcp
            sudo ufw reload
            ;;
        dnf|yum|zypper)
            sudo firewall-cmd --permanent --add-port=1714-1764/tcp
            sudo firewall-cmd --permanent --add-port=1714-1764/udp
            sudo firewall-cmd --reload
            ;;
    esac
    
    print_status "success" "Firewall configured and enabled"
}

install_clamav() {
    print_status "section" "ANTIVIRUS (CLAMAV)"
    
    print_status "info" "Installing ClamAV..."
    sudo apt-get install -y clamav clamav-daemon clamtk
    
    print_status "info" "Updating virus definitions..."
    sudo systemctl stop clamav-freshclam
    sudo freshclam
    sudo systemctl start clamav-freshclam
    
    print_status "success" "ClamAV installed and configured"
}

# ============================================================================
# DOCKER
# ============================================================================

install_docker() {
    print_status "section" "DOCKER INSTALLATION"
    
    if command_exists docker; then
        print_status "info" "Docker already installed"
        return 0
    fi
    
    print_status "info" "Adding Docker's GPG key..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    print_status "info" "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update
    
    print_status "info" "Installing Docker Engine..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    print_status "info" "Testing Docker installation..."
    if sudo docker run hello-world &>> "$LOG_FILE"; then
        print_status "success" "Docker installed and working"
    else
        print_status "warning" "Docker installed but test failed"
    fi
    
    print_status "info" "Disabling Docker autostart..."
    sudo systemctl disable docker.service
    sudo systemctl disable docker.socket
    
    print_status "success" "Docker configured"
}

install_docker_desktop() {
    print_status "section" "DOCKER DESKTOP"
    
    if command_exists docker-desktop; then
        print_status "info" "Docker Desktop already installed"
        return 0
    fi
    
    cd "$DOWNLOADS_DIR"
    print_status "info" "Downloading Docker Desktop..."
    wget -O docker-desktop-amd64.deb "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb?utm_source=docker&utm_medium=webreferral&utm_campaign=docs-driven-download-linux-amd64"
    
    print_status "info" "Installing Docker Desktop..."
    sudo apt-get install -y ./docker-desktop-amd64.deb
    
    print_status "success" "Docker Desktop installed"
    cd - > /dev/null
}

# ============================================================================
# DEVELOPMENT TOOLS
# ============================================================================

install_vscode() {
    print_status "section" "VISUAL STUDIO CODE"
    
    if command_exists code; then
        print_status "info" "VS Code already installed"
        return 0
    fi
    
    case "$PACKAGE_MANAGER" in
        apt)
            cd "$DOWNLOADS_DIR"
            print_status "info" "Downloading VS Code..."
            wget -O code_amd64.deb "https://go.microsoft.com/fwlink/?LinkID=760868"
            
            print_status "info" "Installing VS Code..."
            sudo dpkg -i code_amd64.deb
            sudo apt-get install -f -y  # Fix any dependency issues
            cd - > /dev/null
            ;;
        dnf|yum)
            print_status "info" "Adding VS Code repository..."
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
            $UPDATE_CMD
            $INSTALL_CMD code
            ;;
        pacman)
            print_status "info" "Installing VS Code from AUR..."
            if command_exists yay; then
                yay -S --noconfirm visual-studio-code-bin
            else
                print_status "warning" "Please install VS Code manually from AUR: visual-studio-code-bin"
                print_status "info" "Or install yay first: sudo pacman -S --needed git base-devel && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si"
            fi
            ;;
        zypper)
            print_status "info" "Adding VS Code repository..."
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/zypp/repos.d/vscode.repo'
            $UPDATE_CMD
            $INSTALL_CMD code
            ;;
    esac
    
    print_status "success" "VS Code installed"
}

install_cursor() {
    print_status "section" "CURSOR IDE"
    
    if command_exists cursor; then
        print_status "info" "Cursor IDE already installed"
        return 0
    fi
    
    cd "$DOWNLOADS_DIR"
    print_status "info" "Downloading Cursor IDE..."
    print_status "warning" "This may take a few minutes (large file ~150MB)..."
    
    case "$PACKAGE_MANAGER" in
        apt)
            wget -O cursor.deb "https://downloader.cursor.sh/linux/appImage/x64"
            
            if [ ! -f "cursor.deb" ] || [ ! -s "cursor.deb" ]; then
                print_status "warning" "Download may have failed. Trying alternative URL..."
                wget -O cursor.deb "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/1.7"
            fi
            
            print_status "info" "Installing Cursor IDE..."
            sudo dpkg -i cursor.deb
            sudo apt-get install -f -y  # Fix any dependency issues
            ;;
        dnf|yum)
            print_status "info" "Cursor IDE .rpm package not officially available"
            print_status "info" "Installing AppImage instead..."
            wget -O cursor.AppImage "https://downloader.cursor.sh/linux/appImage/x64"
            chmod +x cursor.AppImage
            mkdir -p ~/.local/bin
            mv cursor.AppImage ~/.local/bin/cursor
            print_status "success" "Cursor installed as AppImage in ~/.local/bin/cursor"
            ;;
        pacman)
            print_status "info" "Installing Cursor from AUR..."
            if command_exists yay; then
                yay -S --noconfirm cursor-bin || yay -S --noconfirm cursor-appimage
            else
                print_status "warning" "Please install yay first or download Cursor AppImage manually"
            fi
            ;;
        zypper)
            print_status "info" "Installing Cursor AppImage..."
            wget -O cursor.AppImage "https://downloader.cursor.sh/linux/appImage/x64"
            chmod +x cursor.AppImage
            mkdir -p ~/.local/bin
            mv cursor.AppImage ~/.local/bin/cursor
            print_status "success" "Cursor installed as AppImage in ~/.local/bin/cursor"
            ;;
    esac
    
    # Verify installation
    if command_exists cursor; then
        print_status "success" "Cursor IDE installed successfully"
        print_status "info" "Launch with: cursor"
    else
        print_status "warning" "Cursor IDE installed but command not found in PATH"
        print_status "info" "Try launching from applications menu or add ~/.local/bin to PATH"
    fi
    
    cd - > /dev/null
}

install_github_cli() {
    print_status "section" "GITHUB CLI"
    
    if command_exists gh; then
        print_status "info" "GitHub CLI already installed"
        return 0
    fi
    
    print_status "info" "Adding GitHub CLI repository..."
    (type -p wget >/dev/null || (sudo apt update && sudo apt-get install -y wget)) \
        && sudo mkdir -p -m 755 /etc/apt/keyrings \
        && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
        && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt update \
        && sudo apt install -y gh
    
    gh --version >> "$LOG_FILE"
    print_status "success" "GitHub CLI installed"
}

install_pyenv() {
    print_status "section" "PYENV (PYTHON VERSION MANAGER)"
    
    if command_exists pyenv; then
        print_status "info" "pyenv already installed"
        return 0
    fi
    
    print_status "info" "Installing pyenv dependencies..."
    sudo apt install -y make build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
    
    print_status "info" "Installing pyenv..."
    curl -fsSL https://pyenv.run | bash
    
    print_status "config" "Adding pyenv to shell configuration..."
    {
        echo 'export PYENV_ROOT="$HOME/.pyenv"'
        echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
        echo 'eval "$(pyenv init - bash)"'
    } >> ~/.bashrc
    
    {
        echo 'export PYENV_ROOT="$HOME/.pyenv"'
        echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
        echo 'eval "$(pyenv init - bash)"'
    } >> ~/.profile
    
    # Load pyenv for this session
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init - bash)"
    
    print_status "info" "Installing Python 3.12.8..."
    pyenv install 3.12.8
    
    print_status "success" "pyenv installed with Python 3.12.8"
}

# ============================================================================
# DATABASES
# ============================================================================

install_postgresql() {
    print_status "section" "POSTGRESQL"
    
    if command_exists psql; then
        print_status "info" "PostgreSQL already installed"
        return 0
    fi
    
    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Adding PostgreSQL repository..."
            sudo apt install -y curl ca-certificates
            sudo install -d /usr/share/postgresql-common/pgdg
            sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
            
            . /etc/os-release
            sudo sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main' > /etc/apt/sources.list.d/pgdg.list"
            
            print_status "info" "Installing PostgreSQL..."
            sudo apt update
            $INSTALL_CMD postgresql postgresql-contrib
            ;;
        dnf|yum)
            print_status "info" "Installing PostgreSQL..."
            $INSTALL_CMD postgresql-server postgresql-contrib
            
            # Initialize database
            if [ ! -d "/var/lib/pgsql/data/base" ]; then
                print_status "info" "Initializing PostgreSQL database..."
                sudo postgresql-setup --initdb
            fi
            
            # Enable and start PostgreSQL
            sudo systemctl enable postgresql
            sudo systemctl start postgresql
            ;;
        pacman)
            print_status "info" "Installing PostgreSQL..."
            $INSTALL_CMD postgresql
            
            # Initialize database
            if [ ! -d "/var/lib/postgres/data" ]; then
                print_status "info" "Initializing PostgreSQL database..."
                sudo -u postgres initdb -D /var/lib/postgres/data
            fi
            
            # Enable and start PostgreSQL
            sudo systemctl enable postgresql
            sudo systemctl start postgresql
            ;;
        zypper)
            print_status "info" "Installing PostgreSQL..."
            $INSTALL_CMD postgresql-server postgresql-contrib
            
            # Initialize and start
            sudo systemctl enable postgresql
            sudo systemctl start postgresql
            ;;
    esac
    
    # Install adminpack extension
    print_status "info" "Installing adminpack extension..."
    if sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS adminpack;" &>> "$LOG_FILE"; then
        print_status "success" "adminpack extension installed"
    else
        print_status "warning" "Could not install adminpack extension (may need manual setup)"
    fi
    
    print_status "warning" "PostgreSQL installed. You should set a password for the postgres user:"
    print_status "config" "Run: sudo -u postgres psql"
    print_status "config" "Then: ALTER USER postgres WITH PASSWORD 'your_password';"
    print_status "config" "Then: \\q to exit"
    
    print_status "success" "PostgreSQL installed"
}

install_pgadmin() {
    print_status "section" "PGADMIN4"
    
    print_status "info" "Adding pgAdmin repository..."
    curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg
    
    sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list'
    
    sudo apt update
    
    print_status "info" "Installing pgAdmin4..."
    sudo apt install -y pgadmin4
    
    print_status "warning" "To configure pgAdmin4 web mode, run:"
    print_status "config" "sudo /usr/pgadmin4/bin/setup-web.sh"
    
    print_status "success" "pgAdmin4 installed"
}

install_dbeaver() {
    print_status "section" "DBEAVER"
    
    if snap list | grep -q dbeaver-ce; then
        print_status "info" "DBeaver already installed"
        return 0
    fi
    
    print_status "info" "Installing DBeaver Community Edition..."
    sudo snap install dbeaver-ce
    
    print_status "success" "DBeaver installed"
}

# ============================================================================
# APPLICATIONS
# ============================================================================

install_chrome() {
    print_status "section" "GOOGLE CHROME"
    
    if command_exists google-chrome; then
        print_status "info" "Chrome already installed"
        return 0
    fi
    
    cd "$DOWNLOADS_DIR"
    
    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Downloading Google Chrome..."
            wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
            
            print_status "info" "Installing Google Chrome..."
            sudo dpkg -i google-chrome-stable_current_amd64.deb
            sudo apt-get install -f -y
            ;;
        dnf|yum)
            print_status "info" "Adding Google Chrome repository..."
            sudo dnf install -y fedora-workstation-repositories
            sudo dnf config-manager --set-enabled google-chrome
            $INSTALL_CMD google-chrome-stable
            ;;
        pacman)
            print_status "info" "Installing Google Chrome from AUR..."
            if command_exists yay; then
                yay -S --noconfirm google-chrome
            else
                print_status "warning" "Please install google-chrome from AUR manually or install yay first"
            fi
            ;;
        zypper)
            print_status "info" "Downloading Google Chrome..."
            wget https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
            $INSTALL_CMD google-chrome-stable_current_x86_64.rpm
            ;;
    esac
    
    print_status "success" "Google Chrome installed"
    cd - > /dev/null
}

install_snap_apps() {
    print_status "section" "SNAP APPLICATIONS"
    
    local apps=(
        "notion-snap-reborn:Notion"
        "postman:Postman"
        "spotify:Spotify"
    )
    
    for app_info in "${apps[@]}"; do
        IFS=':' read -r snap_name display_name <<< "$app_info"
        
        if snap list | grep -q "$snap_name"; then
            print_status "info" "$display_name already installed"
        else
            print_status "info" "Installing $display_name..."
            sudo snap install "$snap_name"
            print_status "success" "$display_name installed"
        fi
    done
}

install_flatpak_apps() {
    print_status "section" "FLATPAK APPLICATIONS"
    
    local apps=(
        "me.iepure.devtoolbox:Dev Toolbox"
        "com.github.ADBeveridge.Raider:Raider (File Shredder)"
        "io.missioncenter.MissionCenter:Mission Center"
        "io.github.thetumultuousunicornofdarkness.cpu-x:CPU-X"
        "org.gnome.NetworkDisplays:Network Displays"
        "org.freedesktop.Piper:Piper"
        "com.notepadqq.Notepadqq:Notepadqq"
    )
    
    for app_info in "${apps[@]}"; do
        IFS=':' read -r app_id display_name <<< "$app_info"
        
        if flatpak list | grep -q "$app_id"; then
            print_status "info" "$display_name already installed"
        else
            print_status "info" "Installing $display_name..."
            flatpak install -y flathub "$app_id"
            print_status "success" "$display_name installed"
        fi
    done
}

install_utilities() {
    print_status "section" "SYSTEM UTILITIES"
    
    local utilities=(
        "vim:vim:vim:vim"
        "vlc:vlc:vlc:vlc"
        "p7zip-full:p7zip:p7zip-full:p7zip"
        "timeshift:timeshift:timeshift:timeshift"
        "kdeconnect:kdeconnect:kdeconnect:kdeconnect"
        "solaar:solaar:solaar:solaar"
    )
    
    for util_info in "${utilities[@]}"; do
        IFS=':' read -r display debian fedora arch <<< "$util_info"
        
        # Check if already installed
        local check_cmd="${debian%% *}"  # Get first word
        if command_exists "$check_cmd" || dpkg -l 2>/dev/null | grep -q "^ii  $debian " || rpm -q "$fedora" &>/dev/null || pacman -Q "$arch" &>/dev/null; then
            print_status "info" "$display already installed"
        else
            print_status "info" "Installing $display..."
            install_package "$display" "$debian" "$fedora" "$arch" || print_status "warning" "$display installation failed"
        fi
    done
    
    # Piper for gaming peripherals
    print_status "info" "Installing Piper (gaming device configuration)..."
    case "$PACKAGE_MANAGER" in
        apt)
            install_package "Piper" "piper" "piper" "piper" || {
                print_status "info" "Installing Piper via Flatpak..."
                flatpak install -y flathub org.freedesktop.Piper 2>/dev/null || print_status "warning" "Piper installation failed"
            }
            ;;
        dnf|yum|pacman)
            install_package "Piper" "piper" "piper" "piper" || print_status "warning" "Piper not available, try: flatpak install flathub org.freedesktop.Piper"
            ;;
    esac
    
    # Distro-specific utilities
    case "$PACKAGE_MANAGER" in
        apt)
            # Clipboard manager
            install_package "CopyQ" "copyq" "copyq" "copyq" || true
            # Photo manager
            install_package "Shotwell" "shotwell" "shotwell" "shotwell" || true
            # Encryption
            install_package "VeraCrypt" "veracrypt" "veracrypt" "veracrypt" || true
            # Office suite
            install_package "LibreOffice" "libreoffice" "libreoffice" "libreoffice" || true
            # App preloader
            install_package "Preload" "preload" "preload" "preload" || true
            # Drive tester
            install_package "F3" "f3" "f3" "f3" || true
            # Calibre eReader
            if ! command_exists calibre; then
                print_status "info" "Installing Calibre..."
                $INSTALL_CMD libxcb-cursor0
                sudo -v && wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sudo sh /dev/stdin || true
            fi
            ;;
        dnf|yum)
            $INSTALL_CMD copyq shotwell libreoffice calibre f3 || true
            ;;
        pacman)
            $INSTALL_CMD copyq shotwell libreoffice calibre f3 || true
            ;;
    esac
    
    print_status "success" "System utilities installed"
    print_status "info" "Solaar: Logitech device manager - launch with 'solaar' command"
    print_status "info" "Piper: Gaming device configuration tool"
}

install_warp_terminal() {
    print_status "section" "WARP TERMINAL"
    
    if command_exists warp-terminal; then
        print_status "info" "Warp Terminal already installed"
        return 0
    fi
    
    cd "$DOWNLOADS_DIR"
    print_status "info" "Downloading Warp Terminal..."
    wget -O warp-terminal.deb "https://app.warp.dev/download?package=deb"
    
    print_status "info" "Installing Warp Terminal..."
    sudo apt install -y ./warp-terminal.deb
    
    print_status "success" "Warp Terminal installed"
    cd - > /dev/null
}

install_veracrypt_appimage() {
    print_status "section" "VERACRYPT APPIMAGE"
    
    if [ -f "$HOME/Downloads/veracrypt.AppImage" ]; then
        print_status "info" "VeraCrypt AppImage already downloaded"
        return 0
    fi
    
    cd "$DOWNLOADS_DIR"
    print_status "info" "Downloading VeraCrypt AppImage..."
    wget -O veracrypt.AppImage "https://launchpad.net/veracrypt/trunk/1.26.24/+download/VeraCrypt-1.26.24-x86_64.AppImage"
    chmod +x veracrypt.AppImage
    
    print_status "success" "VeraCrypt AppImage downloaded to $DOWNLOADS_DIR"
    cd - > /dev/null
}

install_virtual_machine_manager() {
    print_status "section" "VIRTUAL MACHINE MANAGER"
    
    if command_exists virt-manager; then
        print_status "info" "Virtual Machine Manager already installed"
        return 0
    fi
    
    print_status "info" "Installing Virtual Machine Manager..."
    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager
    sudo systemctl enable --now libvirtd
    
    print_status "success" "Virtual Machine Manager installed"
}

configure_gsconnect() {
    print_status "section" "GSCONNECT CONFIGURATION"
    
    print_status "info" "Installing GNOME Shell extensions support..."
    sudo apt install -y gnome-shell-extensions chrome-gnome-shell
    
    if gnome-extensions list | grep -q gsconnect; then
        print_status "info" "Enabling GSConnect..."
        gnome-extensions enable gsconnect@andyholmes.github.io
        print_status "success" "GSConnect enabled"
    else
        print_status "warning" "GSConnect extension not found. Install it from extensions.gnome.org"
    fi
}

install_miro() {
    print_status "section" "MIRO"
    
    if snap list | grep -q miro; then
        print_status "info" "Miro already installed"
        return 0
    fi
    
    case "$PACKAGE_MANAGER" in
        apt|dnf|yum|zypper)
            # Miro is best installed via Snap on most distributions
            if command_exists snap; then
                print_status "info" "Installing Miro via Snap..."
                sudo snap install miro
                print_status "success" "Miro installed via Snap"
            else
                print_status "warning" "Snap not available. Installing Miro via Flatpak..."
                if command_exists flatpak; then
                    flatpak install -y flathub com.miro.Miro
                    print_status "success" "Miro installed via Flatpak"
                else
                    print_status "error" "Neither Snap nor Flatpak available. Please install one first."
                    return 1
                fi
            fi
            ;;
        pacman)
            # For Arch-based systems, try Flatpak first
            if command_exists flatpak; then
                print_status "info" "Installing Miro via Flatpak..."
                flatpak install -y flathub com.miro.Miro
                print_status "success" "Miro installed via Flatpak"
            elif command_exists yay; then
                print_status "info" "Installing Miro from AUR..."
                yay -S --noconfirm miro-bin || yay -S --noconfirm miro
                print_status "success" "Miro installed from AUR"
            else
                print_status "warning" "Please install Miro manually from AUR or via Flatpak"
                return 1
            fi
            ;;
    esac
}

install_localsend() {
    print_status "section" "LOCALSEND"
    
    # Check if LocalSend is already installed
    if command_exists localsend || flatpak list | grep -q "org.localsend.localsend_app"; then
        print_status "info" "LocalSend already installed"
        return 0
    fi
    
    cd "$DOWNLOADS_DIR"
    
    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Downloading LocalSend..."
            # Get latest release URL from GitHub
            local latest_url=$(curl -s https://api.github.com/repos/localsend/localsend/releases/latest | grep "browser_download_url.*deb" | cut -d '"' -f 4)
            
            if [ -n "$latest_url" ]; then
                wget -O localsend.deb "$latest_url"
                print_status "info" "Installing LocalSend..."
                sudo dpkg -i localsend.deb
                sudo apt-get install -f -y
                print_status "success" "LocalSend installed"
            else
                print_status "warning" "Could not fetch latest release. Installing via Flatpak..."
                flatpak install -y flathub org.localsend.localsend_app
            fi
            ;;
        dnf|yum)
            print_status "info" "Downloading LocalSend RPM..."
            local latest_url=$(curl -s https://api.github.com/repos/localsend/localsend/releases/latest | grep "browser_download_url.*rpm" | cut -d '"' -f 4)
            
            if [ -n "$latest_url" ]; then
                wget -O localsend.rpm "$latest_url"
                print_status "info" "Installing LocalSend..."
                sudo $PACKAGE_MANAGER install -y localsend.rpm
                print_status "success" "LocalSend installed"
            else
                print_status "warning" "Could not fetch latest release. Installing via Flatpak..."
                flatpak install -y flathub org.localsend.localsend_app
            fi
            ;;
        pacman)
            if command_exists yay; then
                print_status "info" "Installing LocalSend from AUR..."
                yay -S --noconfirm localsend-bin
                print_status "success" "LocalSend installed from AUR"
            else
                print_status "info" "Installing LocalSend via Flatpak..."
                flatpak install -y flathub org.localsend.localsend_app
                print_status "success" "LocalSend installed via Flatpak"
            fi
            ;;
        zypper)
            print_status "info" "Downloading LocalSend RPM..."
            local latest_url=$(curl -s https://api.github.com/repos/localsend/localsend/releases/latest | grep "browser_download_url.*rpm" | cut -d '"' -f 4)
            
            if [ -n "$latest_url" ]; then
                wget -O localsend.rpm "$latest_url"
                print_status "info" "Installing LocalSend..."
                $INSTALL_CMD localsend.rpm
                print_status "success" "LocalSend installed"
            else
                print_status "warning" "Could not fetch latest release. Installing via Flatpak..."
                flatpak install -y flathub org.localsend.localsend_app
            fi
            ;;
    esac
    
    # Configure firewall for LocalSend (uses port 53317)
    print_status "info" "Configuring firewall for LocalSend..."
    case "$PACKAGE_MANAGER" in
        apt|pacman)
            if command_exists ufw; then
                sudo ufw allow 53317/tcp comment "LocalSend"
                sudo ufw allow 53317/udp comment "LocalSend"
                sudo ufw reload
                print_status "success" "Firewall configured for LocalSend"
            fi
            ;;
        dnf|yum|zypper)
            if command_exists firewall-cmd; then
                sudo firewall-cmd --permanent --add-port=53317/tcp
                sudo firewall-cmd --permanent --add-port=53317/udp
                sudo firewall-cmd --reload
                print_status "success" "Firewall configured for LocalSend"
            fi
            ;;
    esac
    
    print_status "info" "LocalSend allows secure file sharing across devices on your local network"
    
    cd - > /dev/null
}

# ============================================================================
# SYSTEM OPTIMIZATION
# ============================================================================

cleanup_system() {
    print_status "section" "SYSTEM CLEANUP"
    
    print_status "info" "Listing upgradable packages..."
    case "$PACKAGE_MANAGER" in
        apt)
            sudo apt list --upgradable >> "$LOG_FILE" 2>&1 || true
            ;;
        dnf|yum)
            sudo $PACKAGE_MANAGER list upgrades >> "$LOG_FILE" 2>&1 || true
            ;;
        pacman)
            pacman -Qu >> "$LOG_FILE" 2>&1 || true
            ;;
    esac
    
    print_status "info" "Running full upgrade..."
    case "$PACKAGE_MANAGER" in
        apt)
            sudo apt full-upgrade -y
            ;;
        dnf|yum)
            sudo $PACKAGE_MANAGER upgrade -y
            ;;
        pacman)
            sudo pacman -Syu --noconfirm
            ;;
        zypper)
            sudo zypper update -y
            ;;
    esac
    
    print_status "info" "Removing unnecessary packages..."
    case "$PACKAGE_MANAGER" in
        apt)
            sudo apt autoremove -y
            sudo apt clean
            ;;
        dnf|yum)
            sudo $PACKAGE_MANAGER autoremove -y
            sudo $PACKAGE_MANAGER clean all
            ;;
        pacman)
            sudo pacman -Sc --noconfirm
            ;;
        zypper)
            sudo zypper clean -a
            ;;
    esac
    
    print_status "success" "System cleaned up"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

show_menu() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}   ${MAGENTA}Multi-Distribution Development Environment Setup${NC}   ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${GREEN}Detected System:${NC} $DISTRO"
    echo -e "${GREEN}Package Manager:${NC} $PACKAGE_MANAGER"
    echo -e ""
    echo -e "${YELLOW}Select installation mode:${NC}"
    echo -e "  ${GREEN}1)${NC} Full Installation (All components)"
    echo -e "  ${GREEN}2)${NC} Custom Installation (Select components)"
    echo -e "  ${GREEN}3)${NC} Exit"
    echo -e "\n${CYAN}Choice:${NC} "
}

run_full_installation() {
    print_status "section" "FULL INSTALLATION MODE"
    
    update_system
    install_core_dependencies
    setup_flatpak
    install_homebrew
    install_asdf
    setup_firewall
    install_docker
    install_docker_desktop
    install_vscode
    install_cursor
    install_github_cli
    install_pyenv
    install_postgresql
    install_pgadmin
    install_dbeaver
    install_chrome
    install_snap_apps
    install_flatpak_apps
    install_utilities
    install_warp_terminal
    install_virtual_machine_manager
    configure_gsconnect
    install_miro
    install_localsend
    install_clamav
    cleanup_system
    
    print_status "section" "INSTALLATION COMPLETE!"
    print_status "success" "All components installed successfully"
    print_status "info" "Log file: $LOG_FILE"
    print_status "warning" "Please reboot your system to complete the setup"
    print_status "info" "After reboot, verify installations:"
    print_status "config" "  - Homebrew: brew --version"
    print_status "config" "  - asdf: asdf --version"
    print_status "config" "  - Cursor: cursor --version"
}

run_custom_installation() {
    print_status "section" "CUSTOM INSTALLATION MODE"
    
    local components=(
        "update_system:System Update"
        "install_core_dependencies:Core Dependencies"
        "setup_flatpak:Flatpak Package Manager"
        "install_homebrew:Homebrew Package Manager"
        "install_asdf:asdf Version Manager"
        "setup_firewall:Firewall"
        "install_docker:Docker Engine"
        "install_docker_desktop:Docker Desktop"
        "install_vscode:VS Code"
        "install_cursor:Cursor IDE"
        "install_github_cli:GitHub CLI"
        "install_pyenv:Python (pyenv)"
        "install_postgresql:PostgreSQL"
        "install_pgadmin:pgAdmin4"
        "install_dbeaver:DBeaver"
        "install_chrome:Google Chrome"
        "install_snap_apps:Snap Applications"
        "install_flatpak_apps:Flatpak Applications"
        "install_utilities:System Utilities"
        "install_warp_terminal:Warp Terminal"
        "install_virtual_machine_manager:VM Manager"
        "configure_gsconnect:GSConnect"
        "install_miro:Miro Collaboration Tool"
        "install_localsend:LocalSend File Sharing"
        "install_clamav:ClamAV Antivirus"
        "cleanup_system:System Cleanup"
    )
    
    echo -e "\n${YELLOW}Select components to install (space-separated numbers, or 'all'):${NC}"
    for i in "${!components[@]}"; do
        IFS=':' read -r func_name display_name <<< "${components[$i]}"
        echo -e "  ${GREEN}$((i+1)))${NC} $display_name"
    done
    echo -e "\n${CYAN}Selection:${NC} "
    read -r selection
    
    if [[ "$selection" == "all" ]]; then
        run_full_installation
        return
    fi
    
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#components[@]}" ]; then
            IFS=':' read -r func_name display_name <<< "${components[$((num-1))]}"
            $func_name
        fi
    done
    
    print_status "section" "CUSTOM INSTALLATION COMPLETE!"
    print_status "info" "Log file: $LOG_FILE"
    
    # Check if Homebrew or asdf were installed and remind user to reload shell
    if command_exists brew || command_exists asdf; then
        print_status "info" "Version managers installed. Reload your shell:"
        print_status "config" "source ~/.bashrc"
    fi
}

main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then 
        print_status "error" "This script should NOT be run with sudo!"
        print_status "info" "Please run as: bash $0"
        exit 1
    fi
    
    # Detect distribution and package manager
    detect_distro
    
    # Check internet connection
    if ! check_internet; then
        print_status "error" "Internet connection required for installation"
        exit 1
    fi
    
    # Create downloads directory if it doesn't exist
    mkdir -p "$DOWNLOADS_DIR"
    
    # Show menu
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                run_full_installation
                break
                ;;
            2)
                run_custom_installation
                break
                ;;
            3)
                print_status "info" "Installation cancelled"
                exit 0
                ;;
            *)
                print_status "error" "Invalid option. Please select 1, 2, or 3."
                ;;
        esac
    done
}

# Execute main function
main "$@"