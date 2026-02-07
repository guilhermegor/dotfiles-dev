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
UBUNTU_VERSION=""
UBUNTU_CODENAME=""

# ============================================================================
# DISTRO DETECTION
# ============================================================================

detect_distro() {
    print_status "info" "Detecting Linux distribution..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        UBUNTU_VERSION="$VERSION_ID"
        UBUNTU_CODENAME="$VERSION_CODENAME"
        
        case "$DISTRO" in
            ubuntu|debian|pop|linuxmint)
                PACKAGE_MANAGER="apt"
                INSTALL_CMD="sudo apt-get install -y"
                UPDATE_CMD="sudo apt update"
                UPGRADE_CMD="sudo apt upgrade -y"
                print_status "success" "Detected Debian-based system: $PRETTY_NAME"
                print_status "info" "Ubuntu Version: $UBUNTU_VERSION, Codename: $UBUNTU_CODENAME"
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
    echo "UBUNTU_VERSION=$UBUNTU_VERSION" >> "$LOG_FILE"
    echo "UBUNTU_CODENAME=$UBUNTU_CODENAME" >> "$LOG_FILE"
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

# ============================================================================
# VITALS INSTALLATION
# ============================================================================

install_vitals() {
    print_status "section" "VITALS SYSTEM MONITOR"
    
    # Check if Vitals is already installed and enabled
    if gnome-extensions list 2>/dev/null | grep -q "Vitals@CoreCoding.com"; then
        print_status "info" "Vitals extension already installed"
        
        # Check if it's enabled
        if gnome-extensions info "Vitals@CoreCoding.com" 2>/dev/null | grep -q "ENABLED"; then
            print_status "success" "Vitals extension is already enabled"
        else
            print_status "info" "Enabling Vitals extension..."
            if gnome-extensions enable "Vitals@CoreCoding.com" 2>&1 | tee -a "$LOG_FILE"; then
                print_status "success" "Vitals extension enabled"
            else
                print_status "warning" "Could not enable Vitals extension"
                print_status "info" "You may need to log out and log back in"
            fi
        fi
        return 0
    fi
    
    print_status "info" "Installing Vitals system monitor extension..."
    
    # Only support GNOME-based systems
    if ! command_exists gnome-shell; then
        print_status "warning" "GNOME Shell not detected. Vitals requires GNOME desktop environment."
        print_status "info" "Skipping Vitals installation for non-GNOME systems."
        return 1
    fi
    
    case "$PACKAGE_MANAGER" in
        apt)
            install_vitals_debian
            ;;
        dnf|yum)
            install_vitals_rpm
            ;;
        pacman)
            install_vitals_arch
            ;;
        zypper)
            install_vitals_opensuse
            ;;
        *)
            print_status "warning" "Unsupported package manager, trying manual installation"
            install_vitals_manual
            ;;
    esac
    
    # NEW: Enhanced verification with retry logic
    verify_vitals_installation
}

# NEW FUNCTION: Enhanced verification with retry logic
verify_vitals_installation() {
    print_status "info" "Verifying Vitals installation..."
    
    local max_attempts=3
    local attempt=1
    local vitals_installed=false
    
    # Wait for GNOME to detect the extension
    while [ $attempt -le $max_attempts ]; do
        print_status "info" "Verification attempt $attempt/$max_attempts..."
        
        # Check if extension is detected
        if gnome-extensions list 2>/dev/null | grep -q "Vitals@CoreCoding.com"; then
            vitals_installed=true
            print_status "success" "Vitals detected in extension list"
            break
        fi
        
        # Try to force GNOME to rescan extensions
        print_status "info" "Refreshing extension list..."
        
        # Method 1: Send D-Bus signal to rescan extensions
        if command_exists dbus-send; then
            dbus-send --session --type=method_call \
                --dest=org.gnome.Shell \
                /org/gnome/Shell \
                org.gnome.Shell.Extensions.ReloadExtensionInfo \
                string:"Vitals@CoreCoding.com" 2>/dev/null || true
        fi
        
        # Method 2: Restart GNOME Shell extension service
        if command_exists gdbus; then
            gdbus call --session --dest org.gnome.Shell \
                --object-path /org/gnome/Shell \
                --method org.gnome.Shell.Extensions.ReloadExtensionInfo \
                "Vitals@CoreCoding.com" 2>/dev/null || true
        fi
        
        sleep 3
        attempt=$((attempt + 1))
    done
    
    if [ "$vitals_installed" = true ]; then
        # Try to enable the extension
        print_status "info" "Enabling Vitals extension..."
        
        if gnome-extensions enable "Vitals@CoreCoding.com" 2>&1 | tee -a "$LOG_FILE"; then
            print_status "success" "Vitals extension enabled successfully"
            
            # Verify it's actually enabled
            sleep 2
            if gnome-extensions info "Vitals@CoreCoding.com" 2>/dev/null | grep -q "ENABLED"; then
                print_status "success" "Vitals extension is active and running"
            else
                print_status "warning" "Vitals enabled but may not be active"
            fi
        else
            print_status "warning" "Could not enable Vitals extension automatically"
            print_status "info" "You may need to enable it manually"
        fi
    else
        print_status "warning" "Vitals installation could not be verified automatically"
        
        # Check if files exist even if not detected
        local extensions_dir="$HOME/.local/share/gnome-shell/extensions"
        local vitals_dir="$extensions_dir/Vitals@CoreCoding.com"
        
        if [ -d "$vitals_dir" ]; then
            print_status "info" "Vitals files are present at: $vitals_dir"
            print_status "info" "The extension will be available after you:"
            print_status "config" "1. Log out and log back in, OR"
            print_status "config" "2. Restart GNOME Shell: Alt+F2, type 'r', press Enter"
        else
            print_status "error" "Vitals files not found"
            print_status "info" "You may need to install it manually from extensions.gnome.org"
        fi
    fi
}

install_vitals_debian() {
    print_status "info" "Installing Vitals on Debian-based system..."
    
    # Install required dependencies
    print_status "info" "Installing GNOME Shell extension dependencies..."
    $INSTALL_CMD gnome-shell-extensions gnome-shell-extension-prefs chrome-gnome-shell
    
    # Check if Vitals is available in repositories (Ubuntu 24.04+)
    if [[ "$DISTRO" == "ubuntu" ]] && [[ "$UBUNTU_VERSION" == "24.04" ]]; then
        print_status "info" "Ubuntu 24.04 detected, checking for Vitals in repositories..."
        if apt-cache search gnome-shell-extension-vitals 2>/dev/null | grep -q vitals; then
            print_status "info" "Installing Vitals from Ubuntu repository..."
            if $INSTALL_CMD gnome-shell-extension-vitals; then
                print_status "success" "Vitals installed from repository"
                return 0
            else
                print_status "warning" "Repository installation failed, trying manual..."
            fi
        fi
    fi
    
    # Fallback to manual installation
    install_vitals_manual
}

install_vitals_rpm() {
    print_status "info" "Installing Vitals on RPM-based system..."
    
    # Install required dependencies
    print_status "info" "Installing GNOME Shell extension dependencies..."
    $INSTALL_CMD gnome-shell-extension-tool gnome-tweaks
    
    # Try to find Vitals in repositories
    print_status "info" "Checking for Vitals in repositories..."
    if $PACKAGE_MANAGER search gnome-shell-extension-vitals 2>/dev/null | grep -q vitals; then
        print_status "info" "Installing Vitals from repository..."
        if $INSTALL_CMD gnome-shell-extension-vitals; then
            print_status "success" "Vitals installed from repository"
            return 0
        else
            print_status "warning" "Repository installation failed, trying manual..."
        fi
    fi
    
    # Fallback to manual installation
    install_vitals_manual
}

install_vitals_arch() {
    print_status "info" "Installing Vitals on Arch Linux..."
    
    # Try installing from AUR
    if command_exists yay; then
        print_status "info" "Installing Vitals from AUR..."
        if yay -S --noconfirm gnome-shell-extension-vitals 2>&1 | tee -a "$LOG_FILE"; then
            print_status "success" "Vitals installed from AUR"
            return 0
        fi
    fi
    
    # Fallback to manual installation
    install_vitals_manual
}

install_vitals_opensuse() {
    print_status "info" "Installing Vitals on openSUSE..."
    
    # Install required dependencies
    print_status "info" "Installing GNOME Shell extension dependencies..."
    $INSTALL_CMD gnome-shell-extension-common gnome-tweaks
    
    # Check for Vitals in repositories
    print_status "info" "Checking for Vitals in repositories..."
    if zypper search -s gnome-shell-extension-vitals 2>/dev/null | grep -q vitals; then
        print_status "info" "Installing Vitals from repository..."
        if $INSTALL_CMD gnome-shell-extension-vitals; then
            print_status "success" "Vitals installed from repository"
            return 0
        else
            print_status "warning" "Repository installation failed, trying manual..."
        fi
    fi
    
    # Fallback to manual installation
    install_vitals_manual
}

install_vitals_manual() {
    print_status "info" "Installing Vitals manually from GitHub..."
    
    local extensions_dir="$HOME/.local/share/gnome-shell/extensions"
    local vitals_dir="$extensions_dir/Vitals@CoreCoding.com"
    
    # Create extensions directory if it doesn't exist
    mkdir -p "$extensions_dir"
    
    # Check if Vitals is already cloned
    if [ -d "$vitals_dir" ]; then
        print_status "info" "Vitals directory already exists, updating..."
        cd "$vitals_dir"
        if git pull 2>&1 | tee -a "$LOG_FILE"; then
            print_status "success" "Vitals updated from GitHub"
        else
            print_status "warning" "Could not update Vitals, using existing version"
        fi
        cd - > /dev/null
    else
        print_status "info" "Cloning Vitals from GitHub repository..."
        cd "$extensions_dir"
        if git clone https://github.com/corecoding/Vitals.git "Vitals@CoreCoding.com" 2>&1 | tee -a "$LOG_FILE"; then
            print_status "success" "Vitals cloned from GitHub"
        else
            print_status "error" "Failed to clone Vitals from GitHub"
            print_status "info" "You can download it manually from: https://extensions.gnome.org/extension/1460/vitals/"
            return 1
        fi
        cd - > /dev/null
    fi
    
    # Verify metadata.json exists
    if [ ! -f "$vitals_dir/metadata.json" ]; then
        print_status "error" "Vitals installation incomplete - metadata.json not found"
        print_status "info" "Please check the extension directory: $vitals_dir"
        return 1
    fi
    
    # Compile schemas if they exist
    if [ -d "$vitals_dir/schemas" ]; then
        print_status "info" "Compiling Vitals schemas..."
        if [ -f "$vitals_dir/schemas/gschemas.compiled" ]; then
            rm -f "$vitals_dir/schemas/gschemas.compiled"
        fi
        if command_exists glib-compile-schemas; then
            glib-compile-schemas "$vitals_dir/schemas" 2>&1 | tee -a "$LOG_FILE"
            print_status "success" "Vitals schemas compiled"
        fi
    fi
    
    # NEW: Set correct permissions
    print_status "info" "Setting correct permissions..."
    chmod -R 755 "$vitals_dir"
    
    # NEW: Create a desktop file to help GNOME discover the extension
    print_status "info" "Creating desktop file for better integration..."
    local desktop_file="$HOME/.local/share/applications/gnome-shell-extension-vitals.desktop"
    cat > "$desktop_file" << EOF
[Desktop Entry]
Type=Application
Name=Vitals System Monitor
Comment=System monitor for GNOME Shell
Exec=/usr/bin/true
Terminal=false
Categories=Utility;
OnlyShowIn=GNOME;
EOF
    
    # NEW: Try to install to system directory as well (optional)
    if [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null; then
        print_status "info" "Also installing to system directory for better compatibility..."
        sudo mkdir -p /usr/share/gnome-shell/extensions/
        sudo cp -r "$vitals_dir" /usr/share/gnome-shell/extensions/ 2>/dev/null || true
        sudo chown -R root:root /usr/share/gnome-shell/extensions/Vitals@CoreCoding.com 2>/dev/null || true
    fi
    
    print_status "info" "Vitals manual installation complete"
}

# ============================================================================
# OLLAMA INSTALLATION
# ============================================================================

install_ollama() {
    print_status "section" "OLLAMA AI PLATFORM"
    
    # Check if Ollama is already installed
    if command_exists ollama; then
        local current_version=$(ollama --version 2>/dev/null || echo "unknown")
        print_status "info" "Ollama already installed (version: $current_version)"
        return 0
    fi
    
    print_status "info" "Installing Ollama - Local AI platform..."
    
    case "$PACKAGE_MANAGER" in
        apt)
            install_ollama_debian
            ;;
        dnf|yum)
            install_ollama_rpm
            ;;
        pacman)
            install_ollama_arch
            ;;
        zypper)
            install_ollama_opensuse
            ;;
        *)
            print_status "warning" "Unsupported package manager, using curl installation method"
            install_ollama_curl
            ;;
    esac
    
    # Verify installation
    if command_exists ollama; then
        local version=$(ollama --version 2>/dev/null || echo "unknown")
        print_status "success" "Ollama installed successfully (version: $version)"
        
        # Configure Ollama service
        configure_ollama_service
        
        # Show usage information
        show_ollama_info
    else
        print_status "error" "Ollama installation failed"
        return 1
    fi
}

install_ollama_debian() {
    print_status "info" "Installing Ollama on Debian-based system..."
    
    # Install dependencies
    print_status "info" "Installing dependencies..."
    $INSTALL_CMD curl
    
    # Download and install Ollama
    cd "$DOWNLOADS_DIR"
    print_status "info" "Downloading Ollama installer..."
    
    if curl -fsSL https://ollama.ai/install.sh | sh 2>&1 | tee -a "$LOG_FILE"; then
        print_status "success" "Ollama installed via official script"
    else
        print_status "warning" "Official installer failed, trying alternative method..."
        install_ollama_curl
    fi
    
    cd - > /dev/null
}

install_ollama_rpm() {
    print_status "info" "Installing Ollama on RPM-based system..."
    
    # Install dependencies
    print_status "info" "Installing dependencies..."
    $INSTALL_CMD curl
    
    # Download and install Ollama
    cd "$DOWNLOADS_DIR"
    print_status "info" "Downloading Ollama installer..."
    
    if curl -fsSL https://ollama.ai/install.sh | sh 2>&1 | tee -a "$LOG_FILE"; then
        print_status "success" "Ollama installed via official script"
    else
        print_status "warning" "Official installer failed, trying alternative method..."
        install_ollama_curl
    fi
    
    cd - > /dev/null
}

install_ollama_arch() {
    print_status "info" "Installing Ollama on Arch Linux..."
    
    # Try installing from AUR
    if command_exists yay; then
        print_status "info" "Installing Ollama from AUR..."
        if yay -S --noconfirm ollama 2>&1 | tee -a "$LOG_FILE"; then
            print_status "success" "Ollama installed from AUR"
            return 0
        else
            print_status "warning" "AUR installation failed, trying official installer..."
        fi
    fi
    
    # Fall back to official installer
    $INSTALL_CMD curl
    cd "$DOWNLOADS_DIR"
    
    if curl -fsSL https://ollama.ai/install.sh | sh 2>&1 | tee -a "$LOG_FILE"; then
        print_status "success" "Ollama installed via official script"
    else
        print_status "error" "All installation methods failed"
        return 1
    fi
    
    cd - > /dev/null
}

install_ollama_opensuse() {
    print_status "info" "Installing Ollama on openSUSE..."
    
    # Install dependencies
    print_status "info" "Installing dependencies..."
    $INSTALL_CMD curl
    
    # Use official installer
    cd "$DOWNLOADS_DIR"
    print_status "info" "Downloading Ollama installer..."
    
    if curl -fsSL https://ollama.ai/install.sh | sh 2>&1 | tee -a "$LOG_FILE"; then
        print_status "success" "Ollama installed via official script"
    else
        print_status "warning" "Official installer failed, trying binary installation..."
        install_ollama_curl
    fi
    
    cd - > /dev/null
}

install_ollama_curl() {
    print_status "info" "Installing Ollama using binary download..."
    
    cd "$DOWNLOADS_DIR"
    
    # Download the binary directly
    local ollama_url="https://ollama.ai/download/ollama-linux-amd64"
    local ollama_bin="$DOWNLOADS_DIR/ollama"
    
    print_status "info" "Downloading Ollama binary..."
    if curl -L -o "$ollama_bin" "$ollama_url" 2>&1 | tee -a "$LOG_FILE"; then
        chmod +x "$ollama_bin"
        
        # Install to system path
        sudo cp "$ollama_bin" /usr/local/bin/ollama
        print_status "success" "Ollama binary installed to /usr/local/bin/ollama"
    else
        print_status "error" "Failed to download Ollama binary"
        cd - > /dev/null
        return 1
    fi
    
    cd - > /dev/null
}

configure_ollama_service() {
    print_status "info" "Configuring Ollama service..."
    
    # Check if systemd is available
    if ! command_exists systemctl; then
        print_status "warning" "systemd not available, cannot configure service"
        return 0
    fi
    
    # Start and enable Ollama service
    if sudo systemctl enable ollama 2>/dev/null; then
        print_status "success" "Ollama service enabled"
    fi
    
    if sudo systemctl start ollama 2>/dev/null; then
        print_status "success" "Ollama service started"
    else
        print_status "warning" "Could not start Ollama service automatically"
        print_status "info" "You can start it manually with: ollama serve"
    fi
}

show_ollama_info() {
    print_status "info" "Ollama usage examples:"
    print_status "config" "  Start Ollama server: ollama serve"
    print_status "config" "  Pull a model: ollama pull llama2"
    print_status "config" "  Run a model: ollama run llama2"
    print_status "config" "  List models: ollama list"
    print_status "config" "  Available models: llama2, codellama, mistral, phi, etc."
    
    # Show service status if systemd is available
    if command_exists systemctl && systemctl is-active ollama &>/dev/null; then
        print_status "success" "Ollama service is running"
        print_status "info" "Ollama API available at: http://localhost:11434"
    fi
}

# ============================================================================
# NEOVIM INSTALLATION
# ============================================================================

install_neovim() {
    print_status "section" "NEOVIM INSTALLATION"
    
    # Check if Neovim is already installed
    if command_exists nvim; then
        local current_version=$(nvim --version | head -n1 | awk '{print $2}')
        print_status "info" "Neovim already installed (version: $current_version)"
        return 0
    fi
    
    print_status "info" "Installing Neovim..."
    
    case "$PACKAGE_MANAGER" in
        apt)
            # For Ubuntu/Debian, use the official PPA for latest version
            if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
                print_status "info" "Adding Neovim PPA for latest version..."
                sudo add-apt-repository -y ppa:neovim-ppa/unstable
                $UPDATE_CMD
            fi
            
            # Install Neovim
            if install_package "neovim" "neovim" "neovim" "neovim"; then
                print_status "success" "Neovim installed via system package manager"
            else
                print_status "warning" "System package installation failed, trying alternative methods..."
                install_neovim_alternative
            fi
            ;;
        dnf|yum)
            # For Fedora/RHEL/CentOS
            if install_package "neovim" "neovim" "neovim" "neovim"; then
                print_status "success" "Neovim installed via system package manager"
            else
                print_status "warning" "System package installation failed, trying alternative methods..."
                install_neovim_alternative
            fi
            ;;
        pacman)
            # For Arch Linux
            if install_package "neovim" "neovim" "neovim" "neovim"; then
                print_status "success" "Neovim installed via system package manager"
            else
                print_status "warning" "System package installation failed, trying alternative methods..."
                install_neovim_alternative
            fi
            ;;
        zypper)
            # For openSUSE
            if install_package "neovim" "neovim" "neovim" "neovim"; then
                print_status "success" "Neovim installed via system package manager"
            else
                print_status "warning" "System package installation failed, trying alternative methods..."
                install_neovim_alternative
            fi
            ;;
    esac
    
    # Verify installation
    if command_exists nvim; then
        local version=$(nvim --version | head -n1 | awk '{print $2}')
        print_status "success" "Neovim installed successfully (version: $version)"
        
        # Install vim-plug for plugin management
        install_vim_plug
        
        # Create basic configuration
        setup_neovim_config
        
    else
        print_status "error" "Neovim installation failed"
        return 1
    fi
}

install_neovim_alternative() {
    print_status "info" "Trying alternative Neovim installation methods..."
    
    # Method 1: Install via Homebrew if available
    if command_exists brew; then
        print_status "info" "Installing Neovim via Homebrew..."
        brew install neovim
        return $?
    fi
    
    # Method 2: Install via AppImage
    print_status "info" "Downloading Neovim AppImage..."
    cd "$DOWNLOADS_DIR"
    
    local nvim_appimage_url="https://github.com/neovim/neovim/releases/latest/download/nvim.appimage"
    
    if wget -O nvim.appimage "$nvim_appimage_url"; then
        chmod +x nvim.appimage
        sudo mv nvim.appimage /usr/local/bin/nvim
        print_status "success" "Neovim AppImage installed to /usr/local/bin/nvim"
        cd - > /dev/null
        return 0
    else
        print_status "error" "Failed to download Neovim AppImage"
        cd - > /dev/null
        return 1
    fi
}

install_vim_plug() {
    print_status "info" "Installing vim-plug plugin manager..."
    
    local plug_dir="$HOME/.local/share/nvim/site/autoload"
    local plug_file="$plug_dir/plug.vim"
    
    mkdir -p "$plug_dir"
    
    if curl -fLo "$plug_file" --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim; then
        print_status "success" "vim-plug installed successfully"
    else
        print_status "warning" "Failed to install vim-plug"
    fi
}

setup_neovim_config() {
    print_status "info" "Setting up basic Neovim configuration..."
    
    local nvim_dir="$HOME/.config/nvim"
    local init_file="$nvim_dir/init.vim"
    
    mkdir -p "$nvim_dir"
    
    # Create basic init.vim if it doesn't exist
    if [ ! -f "$init_file" ]; then
        cat > "$init_file" << 'EOF'
" Basic Neovim Configuration
set number
set relativenumber
set expandtab
set tabstop=4
set shiftwidth=4
set smartindent
set wrap
set smartcase
set noswapfile
set nobackup
set undodir=~/.vim/undodir
set undofile
set incsearch
set termguicolors
set scrolloff=8
set noshowmode
set completeopt=menuone,noinsert,noselect
set signcolumn=yes
set colorcolumn=80

" Plugin configuration
call plug#begin('~/.vim/plugged')

" Theme
Plug 'navarasu/onedark.nvim'

" File explorer
Plug 'preservim/nerdtree'

" Status line
Plug 'vim-airline/vim-airline'

" Git integration
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'

" Syntax highlighting and language support
Plug 'neoclide/coc.nvim', {'branch': 'release'}

" Fuzzy finder
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'

" Commenting
Plug 'tpope/vim-commentary'

" Auto pairs
Plug 'jiangmiao/auto-pairs'

" Which key
Plug 'folke/which-key.nvim'

call plug#end()

" Color scheme
colorscheme onedark

" Key mappings
let mapleader = " "

" NERDTree
nnoremap <leader>n :NERDTreeFocus<CR>
nnoremap <C-n> :NERDTree<CR>
nnoremap <C-t> :NERDTreeToggle<CR>
nnoremap <C-f> :NERDTreeFind<CR>

" Fuzzy finder
nnoremap <C-p> :Files<CR>
nnoremap <leader>fg :Rg<CR>
nnoremap <leader>fb :Buffers<CR>

" Navigation
nnoremap <leader>h :wincmd h<CR>
nnoremap <leader>j :wincmd j<CR>
nnoremap <leader>k :wincmd k<CR>
nnoremap <leader>l :wincmd l<CR>

" Tab management
nnoremap <leader>to :tabnew<CR>
nnoremap <leader>tc :tabclose<CR>
nnoremap <leader>tn :tabnext<CR>
nnoremap <leader>tp :tabprevious<CR>

" Save and quit
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>wq :wq<CR>

" Source current file
nnoremap <leader><CR> :so ~/.config/nvim/init.vim<CR>

" Auto commands
autocmd VimEnter * NERDTree | wincmd p

" COC configuration
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use tab for trigger completion with characters ahead and navigate
inoremap <silent><expr> <TAB>
      \ coc#pum#visible() ? coc#pum#next(1) :
      \ CheckBackspace() ? "\<Tab>" :
      \ coc#refresh()
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

function! CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Make <CR> to accept selected completion item or notify coc.nvim to format
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm() : "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
EOF
        
        print_status "success" "Basic Neovim configuration created at $init_file"
        print_status "info" "After first launch, run :PlugInstall to install plugins"
    else
        print_status "info" "Neovim configuration already exists at $init_file"
    fi
}

# ============================================================================
# INSYNC DOWNLOAD AND INSTALLATION
# ============================================================================

install_insync() {
    print_status "section" "INSYNC DOWNLOAD AND INSTALLATION"
    
    # Check if Insync is already installed
    if command_exists insync || dpkg -l 2>/dev/null | grep -q insync; then
        print_status "info" "Insync already installed"
        return 0
    fi
    
    # Only support Ubuntu/Debian for now as we have the specific .deb URL
    if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]]; then
        print_status "warning" "Insync installation currently only supported on Ubuntu/Debian"
        print_status "info" "Please install Insync manually for your distribution"
        return 1
    fi
    
    cd "$DOWNLOADS_DIR"
    
    # Map Ubuntu versions to Insync release names
    local insync_codename=""
    case "$UBUNTU_CODENAME" in
        "noble")
            insync_codename="noble"
            ;;
        "jammy")
            insync_codename="jammy"
            ;;
        "focal")
            insync_codename="focal"
            ;;
        "bionic")
            insync_codename="bionic"
            ;;
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
    
    # Download Insync
    if wget -O "$insync_deb_file" "$insync_deb_url" 2>&1 | tee -a "$LOG_FILE"; then
        if [ -f "$insync_deb_file" ] && [ -s "$insync_deb_file" ]; then
            print_status "success" "Insync downloaded successfully"
            
            # Verify it's a valid .deb file
            if file "$insync_deb_file" | grep -q "Debian"; then
                print_status "info" "Installing Insync..."
                
                # Install the .deb package
                if sudo dpkg -i "$insync_deb_file"; then
                    print_status "success" "Insync installed successfully"
                    
                    # Fix any dependency issues
                    sudo apt-get install -f -y
                    
                    # Verify installation
                    if command_exists insync || dpkg -l | grep -q insync; then
                        print_status "success" "Insync installation verified"
                        print_status "info" "Insync version: $insync_version"
                        
                        # Launch Insync
                        print_status "info" "Starting Insync..."
                        insync start &>> "$LOG_FILE" &
                        print_status "success" "Insync started"
                    else
                        print_status "warning" "Insync installed but command not found"
                    fi
                else
                    print_status "error" "Failed to install Insync package"
                    print_status "info" "Attempting to fix dependencies..."
                    sudo apt-get install -f -y
                    
                    # Try installing again
                    if sudo dpkg -i "$insync_deb_file"; then
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
    
    # Alternative installation method if the direct download fails
    if [ ! -f "$insync_deb_file" ] || [ ! -s "$insync_deb_file" ]; then
        print_status "warning" "Primary download method failed, trying alternative..."
        
        # Try to download using curl with the exact URL from your logs
        local alt_url="https://cdn.insynchq.com/builds/linux/3.9.6.60027/insync_3.9.6.60027-noble_amd64.deb"
        print_status "info" "Trying alternative URL: $alt_url"
        
        if curl -L -o "insync_alternative.deb" "$alt_url" 2>&1 | tee -a "$LOG_FILE"; then
            if [ -f "insync_alternative.deb" ] && [ -s "insync_alternative.deb" ]; then
                print_status "info" "Installing Insync from alternative download..."
                sudo dpkg -i "insync_alternative.deb"
                sudo apt-get install -f -y
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
    
    cd - > /dev/null
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
            $INSTALL_CMD curl wget libcurl4-openssl-dev libssl-dev
            ;;
        dnf|yum)
            $INSTALL_CMD curl wget libcurl-devel openssl-devel
            ;;
        pacman)
            $INSTALL_CMD curl wget openssl
            ;;
        zypper)
            $INSTALL_CMD curl wget libcurl-devel libopenssl-devel
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
    
    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Downloading Cursor IDE..."
            print_status "warning" "This may take a few minutes (large file ~150MB)..."
            
            # Official Cursor API download URL
            local cursor_deb_url="https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/2.2"
            
            print_status "info" "Downloading from official Cursor API..."
            
            if wget --timeout=120 --tries=3 \
                --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
                -O cursor_latest.deb "$cursor_deb_url" 2>&1 | tee -a "$LOG_FILE"; then
                
                if [ -f "cursor_latest.deb" ] && [ -s "cursor_latest.deb" ]; then
                    # Verify it's a valid .deb file
                    if file cursor_latest.deb | grep -q "Debian"; then
                        print_status "success" "Downloaded Cursor .deb package"
                        
                        print_status "info" "Installing Cursor IDE..."
                        if sudo dpkg -i cursor_latest.deb 2>&1 | tee -a "$LOG_FILE"; then
                            print_status "success" "Cursor installed successfully"
                        else
                            print_status "warning" "dpkg installation had issues, fixing dependencies..."
                            sudo apt-get install -f -y
                            
                            # Try installing again after fixing dependencies
                            if sudo dpkg -i cursor_latest.deb; then
                                print_status "success" "Cursor installed after fixing dependencies"
                            else
                                print_status "error" "Failed to install Cursor package"
                                cd - > /dev/null
                                return 1
                            fi
                        fi
                        
                        # Verify installation
                        if command_exists cursor || dpkg -l | grep -q cursor; then
                            print_status "success" "Cursor IDE installation verified"
                            
                            # Get installed version
                            if dpkg -l | grep -q cursor; then
                                local version=$(dpkg -l | grep cursor | awk '{print $3}')
                                print_status "info" "Installed version: $version"
                                echo "Cursor version: $version" >> "$LOG_FILE"
                            fi
                            
                            cd - > /dev/null
                            return 0
                        else
                            print_status "error" "Installation verification failed"
                            cd - > /dev/null
                            return 1
                        fi
                    else
                        print_status "error" "Downloaded file is not a valid .deb package"
                        rm -f cursor_latest.deb
                        cd - > /dev/null
                        return 1
                    fi
                else
                    print_status "error" "Download failed or file is empty"
                    cd - > /dev/null
                    return 1
                fi
            else
                print_status "error" "Failed to download Cursor"
                print_status "info" "Manual installation options:"
                print_status "config" "1. Visit https://cursor.com to download directly"
                print_status "config" "2. Or try: sudo snap install cursor"
                print_status "config" "3. Or download with: wget -O cursor.deb https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/2.2"
                cd - > /dev/null
                return 1
            fi
            ;;
            
        dnf|yum)
            print_status "info" "Installing Cursor for RPM-based system..."
            
            # Try AppImage for RPM systems
            local appimage_url="https://api2.cursor.sh/updates/download/golden/linux-x64-appimage/cursor/2.2"
            
            print_status "info" "Downloading Cursor AppImage..."
            
            if wget --timeout=120 --tries=3 \
                --user-agent="Mozilla/5.0" \
                -O cursor.AppImage "$appimage_url" 2>&1 | tee -a "$LOG_FILE"; then
                
                if [ -f "cursor.AppImage" ] && [ -s "cursor.AppImage" ]; then
                    chmod +x cursor.AppImage
                    mkdir -p ~/.local/bin
                    mv cursor.AppImage ~/.local/bin/cursor
                    
                    # Add to PATH if not already there
                    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
                        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
                        print_status "info" "Added ~/.local/bin to PATH in ~/.bashrc"
                    fi
                    
                    print_status "success" "Cursor AppImage installed in ~/.local/bin/cursor"
                    print_status "info" "Reload shell with: source ~/.bashrc"
                else
                    print_status "error" "Download failed or file is empty"
                    print_status "info" "Please visit https://cursor.com to download manually"
                fi
            else
                print_status "error" "Could not download Cursor AppImage"
                print_status "info" "Please visit https://cursor.com to download manually"
            fi
            ;;
            
        zypper)
            print_status "info" "Installing Cursor for openSUSE..."
            
            # Try AppImage for openSUSE
            local appimage_url="https://api2.cursor.sh/updates/download/golden/linux-x64-appimage/cursor/2.2"
            
            print_status "info" "Downloading Cursor AppImage..."
            
            if wget --timeout=120 --tries=3 \
                --user-agent="Mozilla/5.0" \
                -O cursor.AppImage "$appimage_url" 2>&1 | tee -a "$LOG_FILE"; then
                
                if [ -f "cursor.AppImage" ] && [ -s "cursor.AppImage" ]; then
                    chmod +x cursor.AppImage
                    mkdir -p ~/.local/bin
                    mv cursor.AppImage ~/.local/bin/cursor
                    
                    # Add to PATH if not already there
                    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
                        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
                        print_status "info" "Added ~/.local/bin to PATH in ~/.bashrc"
                    fi
                    
                    print_status "success" "Cursor AppImage installed in ~/.local/bin/cursor"
                    print_status "info" "Reload shell with: source ~/.bashrc"
                else
                    print_status "error" "Download failed or file is empty"
                    print_status "info" "Please visit https://cursor.com to download manually"
                fi
            else
                print_status "error" "Could not download Cursor AppImage"
                print_status "info" "Please visit https://cursor.com to download manually"
            fi
            ;;
            
        pacman)
            print_status "info" "Installing Cursor from AUR..."
            if command_exists yay; then
                if yay -S --noconfirm cursor-bin 2>&1 | tee -a "$LOG_FILE"; then
                    print_status "success" "Cursor installed from AUR"
                elif yay -S --noconfirm cursor-appimage 2>&1 | tee -a "$LOG_FILE"; then
                    print_status "success" "Cursor AppImage installed from AUR"
                else
                    print_status "error" "Failed to install Cursor from AUR"
                    print_status "info" "Trying direct AppImage download..."
                    
                    local appimage_url="https://api2.cursor.sh/updates/download/golden/linux-x64-appimage/cursor/2.2"
                    
                    if wget --timeout=120 -O cursor.AppImage "$appimage_url" 2>&1 | tee -a "$LOG_FILE"; then
                        if [ -f "cursor.AppImage" ] && [ -s "cursor.AppImage" ]; then
                            chmod +x cursor.AppImage
                            mkdir -p ~/.local/bin
                            mv cursor.AppImage ~/.local/bin/cursor
                            
                            if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
                                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
                                print_status "info" "Added ~/.local/bin to PATH in ~/.bashrc"
                            fi
                            
                            print_status "success" "Cursor AppImage installed in ~/.local/bin/cursor"
                        fi
                    fi
                fi
            else
                print_status "warning" "yay not found"
                print_status "info" "Install yay first or download Cursor manually from https://cursor.com"
            fi
            ;;
    esac
    
    # Final verification
    if command_exists cursor; then
        print_status "success" "Cursor IDE is ready to use"
        print_status "info" "Launch with: cursor"
        cursor --version 2>&1 | head -n1 >> "$LOG_FILE" || true
    elif [ -f ~/.local/bin/cursor ]; then
        print_status "success" "Cursor AppImage installed in ~/.local/bin/cursor"
        print_status "info" "Launch with: cursor (after reloading shell)"
        print_status "config" "Or run: export PATH=\"\$HOME/.local/bin:\$PATH\" && cursor"
    else
        print_status "warning" "Cursor installation could not be verified"
        print_status "info" "If you need to install manually:"
        print_status "config" "1. Visit https://cursor.com"
        print_status "config" "2. Or download with: wget -O cursor.deb https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/2.2"
        print_status "config" "3. Then install: sudo dpkg -i cursor.deb"
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
    
    # Check if .pyenv directory exists but pyenv command isn't available
    if [ -d "$HOME/.pyenv" ]; then
        print_status "warning" "Found existing ~/.pyenv directory but pyenv command not available"
        print_status "info" "Setting up existing pyenv installation..."
        
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        
        # Add to shell configuration if not already present
        if ! grep -q "PYENV_ROOT" ~/.bashrc; then
            {
                echo 'export PYENV_ROOT="$HOME/.pyenv"'
                echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
                echo 'eval "$(pyenv init - bash)"'
            } >> ~/.bashrc
            print_status "success" "pyenv configuration added to ~/.bashrc"
        fi
        
        if ! grep -q "PYENV_ROOT" ~/.profile; then
            {
                echo 'export PYENV_ROOT="$HOME/.pyenv"'
                echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
                echo 'eval "$(pyenv init - bash)"'
            } >> ~/.profile
            print_status "success" "pyenv configuration added to ~/.profile"
        fi
        
        # Source for current session
        eval "$(pyenv init - bash)"
        
        print_status "success" "Existing pyenv setup completed"
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
    sudo snap install dbeaver-ce --classic
    
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

install_slack() {
    print_status "section" "SLACK"
    
    # Check if Slack is already installed via different methods
    if command_exists slack || snap list 2>/dev/null | grep -q "^slack " || flatpak list 2>/dev/null | grep -q com.slack.Slack; then
        print_status "info" "Slack already installed"
        return 0
    fi
    
    cd "$DOWNLOADS_DIR"
    
    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Downloading Slack..."
            # Use the redirect URL which always points to the latest version
            if wget -O slack-desktop-latest-amd64.deb "https://downloads.slack-edge.com/desktop-releases/linux/x64/latest/slack-desktop-latest-amd64.deb" 2>&1 | tee -a "$LOG_FILE"; then
                if [ -f "slack-desktop-latest-amd64.deb" ] && [ -s "slack-desktop-latest-amd64.deb" ]; then
                    print_status "info" "Installing Slack..."
                    sudo dpkg -i slack-desktop-latest-amd64.deb || {
                        print_status "warning" "dpkg installation had issues, fixing dependencies..."
                        sudo apt-get install -f -y
                    }
                    
                    if command_exists slack || dpkg -l | grep -q slack; then
                        print_status "success" "Slack installed successfully"
                    else
                        print_status "warning" "Slack package installation failed, trying Snap..."
                        if command_exists snap; then
                            sudo snap install slack
                            print_status "success" "Slack installed via Snap"
                        fi
                    fi
                else
                    print_status "error" "Download failed, trying alternative method..."
                    if command_exists snap; then
                        sudo snap install slack
                        print_status "success" "Slack installed via Snap"
                    fi
                fi
            else
                print_status "error" "Download failed, trying Snap..."
                if command_exists snap; then
                    sudo snap install slack
                    print_status "success" "Slack installed via Snap"
                fi
            fi
            ;;
        dnf|yum)
            print_status "info" "Downloading Slack..."
            if wget -O slack-latest.rpm "https://downloads.slack-edge.com/desktop-releases/linux/x64/latest/slack-latest.x86_64.rpm" 2>&1 | tee -a "$LOG_FILE"; then
                print_status "info" "Installing Slack..."
                sudo $PACKAGE_MANAGER install -y slack-latest.rpm
                print_status "success" "Slack installed"
            else
                print_status "error" "Download failed, trying Flatpak..."
                if command_exists flatpak; then
                    flatpak install -y flathub com.slack.Slack
                    print_status "success" "Slack installed via Flatpak"
                fi
            fi
            ;;
        pacman)
            print_status "info" "Installing Slack..."
            if command_exists yay; then
                yay -S --noconfirm slack-desktop
                print_status "success" "Slack installed from AUR"
            else
                print_status "warning" "yay not found. Installing via Flatpak..."
                if command_exists flatpak; then
                    flatpak install -y flathub com.slack.Slack
                    print_status "success" "Slack installed via Flatpak"
                else
                    print_status "error" "Please install yay or Flatpak first"
                    return 1
                fi
            fi
            ;;
        zypper)
            print_status "info" "Downloading Slack..."
            if wget -O slack-latest.rpm "https://downloads.slack-edge.com/desktop-releases/linux/x64/latest/slack-latest.x86_64.rpm" 2>&1 | tee -a "$LOG_FILE"; then
                print_status "info" "Installing Slack..."
                $INSTALL_CMD slack-latest.rpm
                print_status "success" "Slack installed"
            else
                print_status "error" "Download failed, trying Flatpak..."
                if command_exists flatpak; then
                    flatpak install -y flathub com.slack.Slack
                    print_status "success" "Slack installed via Flatpak"
                fi
            fi
            ;;
    esac
    
    # Final verification
    if command_exists slack; then
        print_status "success" "Slack is ready to use"
        print_status "info" "Launch with: slack"
    elif snap list 2>/dev/null | grep -q "^slack "; then
        print_status "success" "Slack installed via Snap"
        print_status "info" "Launch with: slack"
    elif flatpak list 2>/dev/null | grep -q com.slack.Slack; then
        print_status "success" "Slack installed via Flatpak"
        print_status "info" "Launch with: flatpak run com.slack.Slack"
    else
        print_status "warning" "Slack installation could not be verified"
        print_status "info" "You can install Slack manually from https://slack.com/downloads/linux"
    fi
    
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
        "flameshot:flameshot:flameshot:flameshot"
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
    print_status "info" "Flameshot: Screenshot tool - launch with 'flameshot' command"
}

install_flameshot() {
    print_status "section" "FLAMESHOT SCREENSHOT TOOL"
    
    if command_exists flameshot; then
        print_status "info" "Flameshot already installed"
        return 0
    fi
    
    print_status "info" "Installing Flameshot..."
    install_package "flameshot" "flameshot" "flameshot" "flameshot"
    
    print_status "success" "Flameshot installed"
    print_status "info" "Usage: flameshot gui (for interactive screenshot tool)"
    print_status "info" "You can set up keyboard shortcuts for quick access"
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

install_linear() {
    print_status "section" "LINEAR"

    local desktop_dir="$HOME/.local/share/applications"
    local desktop_file="$desktop_dir/linear.desktop"

    if [ -f "$desktop_file" ]; then
        print_status "info" "Linear desktop entry already exists"
        return 0
    fi

    if ! command_exists google-chrome; then
        print_status "warning" "Google Chrome not found. Linear desktop entry will still be created, but may not launch."
        print_status "info" "Install Chrome and re-run this step if needed."
    fi

    print_status "info" "Creating Linear desktop entry..."
    mkdir -p "$desktop_dir"
    cat > "$desktop_file" << 'EOF'
[Desktop Entry]
Name=Linear
Exec=google-chrome --app=https://linear.app
Terminal=false
Type=Application
Icon=web-browser
Categories=Office;ProjectManagement;
EOF
    chmod +x "$desktop_file"

    if command_exists update-desktop-database; then
        update-desktop-database "$desktop_dir" 2>/dev/null || true
    fi

    print_status "success" "Linear desktop entry created"
}

install_localsend() {
    print_status "section" "LOCALSEND"
    
    # Check if LocalSend is already installed
    if command_exists localsend || flatpak list 2>/dev/null | grep -q "org.localsend.localsend_app"; then
        print_status "info" "LocalSend already installed"
        return 0
    fi
    
    cd "$DOWNLOADS_DIR"
    
    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Detecting system architecture..."
            
            # Detect architecture
            local arch=$(dpkg --print-architecture)
            local download_arch=""
            
            case "$arch" in
                amd64)
                    download_arch="x86-64"
                    print_status "info" "Architecture: x86-64 (amd64)"
                    ;;
                arm64)
                    download_arch="arm-64"
                    print_status "info" "Architecture: ARM 64-bit"
                    ;;
                armhf)
                    download_arch="arm-32"
                    print_status "info" "Architecture: ARM 32-bit"
                    ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    flatpak install -y flathub org.localsend.localsend_app
                    cd - > /dev/null
                    return 0
                    ;;
            esac
            
            print_status "info" "Fetching latest LocalSend release..."
            
            # Get latest release URL from GitHub for specific architecture
            local latest_url=$(curl -s https://api.github.com/repos/localsend/localsend/releases/latest | \
                grep "browser_download_url.*linux-${download_arch}.deb" | \
                head -n 1 | \
                cut -d '"' -f 4)
            
            if [ -n "$latest_url" ] && [ "$latest_url" != "null" ]; then
                print_status "info" "Downloading LocalSend from GitHub..."
                print_status "config" "URL: $latest_url"
                
                if wget -O localsend.deb "$latest_url"; then
                    print_status "info" "Installing LocalSend..."
                    sudo dpkg -i localsend.deb
                    sudo apt-get install -f -y
                    print_status "success" "LocalSend installed via .deb package"
                else
                    print_status "warning" "Download failed. Installing via Flatpak..."
                    flatpak install -y flathub org.localsend.localsend_app
                    print_status "success" "LocalSend installed via Flatpak"
                fi
            else
                print_status "warning" "Could not fetch latest release. Installing via Flatpak..."
                flatpak install -y flathub org.localsend.localsend_app
                print_status "success" "LocalSend installed via Flatpak"
            fi
            ;;
            
        dnf|yum)
            print_status "info" "Detecting system architecture..."
            
            # Detect architecture
            local arch=$(uname -m)
            local download_arch=""
            
            case "$arch" in
                x86_64)
                    download_arch="x86-64"
                    print_status "info" "Architecture: x86-64"
                    ;;
                aarch64)
                    download_arch="arm-64"
                    print_status "info" "Architecture: ARM 64-bit"
                    ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    flatpak install -y flathub org.localsend.localsend_app
                    cd - > /dev/null
                    return 0
                    ;;
            esac
            
            print_status "info" "Fetching latest LocalSend release..."
            
            local latest_url=$(curl -s https://api.github.com/repos/localsend/localsend/releases/latest | \
                grep "browser_download_url.*linux-${download_arch}.rpm" | \
                head -n 1 | \
                cut -d '"' -f 4)
            
            if [ -n "$latest_url" ] && [ "$latest_url" != "null" ]; then
                print_status "info" "Downloading LocalSend from GitHub..."
                print_status "config" "URL: $latest_url"
                
                if wget -O localsend.rpm "$latest_url"; then
                    print_status "info" "Installing LocalSend..."
                    sudo $PACKAGE_MANAGER install -y localsend.rpm
                    print_status "success" "LocalSend installed via .rpm package"
                else
                    print_status "warning" "Download failed. Installing via Flatpak..."
                    flatpak install -y flathub org.localsend.localsend_app
                    print_status "success" "LocalSend installed via Flatpak"
                fi
            else
                print_status "warning" "Could not fetch latest release. Installing via Flatpak..."
                flatpak install -y flathub org.localsend.localsend_app
                print_status "success" "LocalSend installed via Flatpak"
            fi
            ;;
            
        pacman)
            if command_exists yay; then
                print_status "info" "Installing LocalSend from AUR..."
                yay -S --noconfirm localsend-bin
                print_status "success" "LocalSend installed from AUR"
            else
                print_status "info" "yay not found. Installing LocalSend via Flatpak..."
                flatpak install -y flathub org.localsend.localsend_app
                print_status "success" "LocalSend installed via Flatpak"
            fi
            ;;
            
        zypper)
            print_status "info" "Detecting system architecture..."
            
            # Detect architecture
            local arch=$(uname -m)
            local download_arch=""
            
            case "$arch" in
                x86_64)
                    download_arch="x86-64"
                    print_status "info" "Architecture: x86-64"
                    ;;
                aarch64)
                    download_arch="arm-64"
                    print_status "info" "Architecture: ARM 64-bit"
                    ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    flatpak install -y flathub org.localsend.localsend_app
                    cd - > /dev/null
                    return 0
                    ;;
            esac
            
            print_status "info" "Fetching latest LocalSend release..."
            
            local latest_url=$(curl -s https://api.github.com/repos/localsend/localsend/releases/latest | \
                grep "browser_download_url.*linux-${download_arch}.rpm" | \
                head -n 1 | \
                cut -d '"' -f 4)
            
            if [ -n "$latest_url" ] && [ "$latest_url" != "null" ]; then
                print_status "info" "Downloading LocalSend from GitHub..."
                print_status "config" "URL: $latest_url"
                
                if wget -O localsend.rpm "$latest_url"; then
                    print_status "info" "Installing LocalSend..."
                    $INSTALL_CMD localsend.rpm
                    print_status "success" "LocalSend installed via .rpm package"
                else
                    print_status "warning" "Download failed. Installing via Flatpak..."
                    flatpak install -y flathub org.localsend.localsend_app
                    print_status "success" "LocalSend installed via Flatpak"
                fi
            else
                print_status "warning" "Could not fetch latest release. Installing via Flatpak..."
                flatpak install -y flathub org.localsend.localsend_app
                print_status "success" "LocalSend installed via Flatpak"
            fi
            ;;
    esac
    
    # Configure firewall for LocalSend (uses port 53317)
    print_status "info" "Configuring firewall for LocalSend..."
    case "$PACKAGE_MANAGER" in
        apt|pacman)
            if command_exists ufw; then
                sudo ufw allow 53317/tcp comment "LocalSend" 2>/dev/null
                sudo ufw allow 53317/udp comment "LocalSend" 2>/dev/null
                sudo ufw reload 2>/dev/null
                print_status "success" "Firewall configured for LocalSend (port 53317)"
            else
                print_status "info" "UFW not installed. Skipping firewall configuration."
            fi
            ;;
        dnf|yum|zypper)
            if command_exists firewall-cmd; then
                sudo firewall-cmd --permanent --add-port=53317/tcp 2>/dev/null
                sudo firewall-cmd --permanent --add-port=53317/udp 2>/dev/null
                sudo firewall-cmd --reload 2>/dev/null
                print_status "success" "Firewall configured for LocalSend (port 53317)"
            else
                print_status "info" "firewalld not installed. Skipping firewall configuration."
            fi
            ;;
    esac
    
    print_status "info" "LocalSend: Secure file sharing on your local network"
    print_status "config" "Available on Android, iOS, Windows, macOS, and Linux"
    
    cd - > /dev/null
}

# ============================================================================
# PINTA IMAGE EDITOR
# ============================================================================

install_pinta() {
    print_status "section" "PINTA IMAGE EDITOR"
    
    # Check if Pinta is already installed
    if command_exists pinta || flatpak list 2>/dev/null | grep -q "com.github.PintaProject.Pinta" || dpkg -l 2>/dev/null | grep -q "^ii  pinta "; then
        print_status "info" "Pinta already installed"
        return 0
    fi
    
    print_status "info" "Installing Pinta image editor..."
    
    case "$PACKAGE_MANAGER" in
        apt)
            # Try installing via apt first
            if install_package "pinta" "pinta" "pinta" "pinta"; then
                print_status "success" "Pinta installed via system package manager"
            else
                print_status "warning" "Pinta not available in repositories, trying Flatpak..."
                if command_exists flatpak; then
                    flatpak install -y flathub com.github.PintaProject.Pinta
                    print_status "success" "Pinta installed via Flatpak"
                else
                    print_status "error" "Could not install Pinta. Please install manually."
                    return 1
                fi
            fi
            ;;
        dnf|yum)
            # For RPM-based systems, try Flatpak first as Pinta might not be in main repos
            if command_exists flatpak; then
                flatpak install -y flathub com.github.PintaProject.Pinta
                print_status "success" "Pinta installed via Flatpak"
            else
                print_status "warning" "Flatpak not available, trying system repositories..."
                if install_package "pinta" "pinta" "pinta" "pinta"; then
                    print_status "success" "Pinta installed via system package manager"
                else
                    print_status "error" "Could not install Pinta. Please install Flatpak first or install Pinta manually."
                    return 1
                fi
            fi
            ;;
        pacman)
            # For Arch-based systems
            if command_exists yay; then
                yay -S --noconfirm pinta
                print_status "success" "Pinta installed from AUR"
            elif command_exists flatpak; then
                flatpak install -y flathub com.github.PintaProject.Pinta
                print_status "success" "Pinta installed via Flatpak"
            else
                print_status "warning" "Please install Pinta manually: yay -S pinta or enable Flatpak"
                return 1
            fi
            ;;
        zypper)
            # For openSUSE
            if command_exists flatpak; then
                flatpak install -y flathub com.github.PintaProject.Pinta
                print_status "success" "Pinta installed via Flatpak"
            else
                if install_package "pinta" "pinta" "pinta" "pinta"; then
                    print_status "success" "Pinta installed via system package manager"
                else
                    print_status "error" "Could not install Pinta. Please install Flatpak first."
                    return 1
                fi
            fi
            ;;
    esac
    
    # Final verification
    if command_exists pinta || flatpak list 2>/dev/null | grep -q "com.github.PintaProject.Pinta"; then
        print_status "success" "Pinta image editor is ready to use"
        print_status "info" "Pinta: Simple yet powerful image editing tool"
        print_status "config" "Alternative to Paint.NET for Linux"
        print_status "config" "Launch with: pinta"
        
        if flatpak list 2>/dev/null | grep -q "com.github.PintaProject.Pinta"; then
            print_status "config" "Or if installed via Flatpak: flatpak run com.github.PintaProject.Pinta"
        fi
    else
        print_status "warning" "Pinta installation could not be verified"
        print_status "info" "You can install Pinta manually:"
        print_status "config" "Flatpak: flatpak install flathub com.github.PintaProject.Pinta"
        print_status "config" "Or visit: https://www.pinta-project.com/"
    fi
}

# ============================================================================
# RUSTDESK REMOTE DESKTOP
# ============================================================================

install_rustdesk() {
    print_status "section" "RUSTDESK REMOTE DESKTOP"
    
    # Check if RustDesk is already installed
    if command_exists rustdesk || flatpak list 2>/dev/null | grep -q "com.rustdesk.RustDesk" || dpkg -l 2>/dev/null | grep -q "^ii  rustdesk "; then
        print_status "info" "RustDesk already installed"
        return 0
    fi
    
    cd "$DOWNLOADS_DIR"
    
    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Detecting system architecture..."
            
            # Detect architecture
            local arch=$(dpkg --print-architecture)
            local download_arch=""
            
            case "$arch" in
                amd64)
                    download_arch="x86_64"
                    print_status "info" "Architecture: x86-64 (amd64)"
                    ;;
                arm64)
                    download_arch="aarch64"
                    print_status "info" "Architecture: ARM 64-bit"
                    ;;
                armhf)
                    download_arch="armv7"
                    print_status "info" "Architecture: ARM 32-bit"
                    ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    flatpak install -y flathub com.rustdesk.RustDesk
                    cd - > /dev/null
                    return 0
                    ;;
            esac
            
            print_status "info" "Fetching latest RustDesk release..."
            
            # Get latest release info from GitHub API
            local latest_info=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest)
            local latest_version=$(echo "$latest_info" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            
            if [ -z "$latest_version" ]; then
                print_status "warning" "Could not fetch latest version, using fallback"
                latest_version="1.4.4"
            fi
            
            print_status "info" "Latest RustDesk version: $latest_version"
            
            # Construct download URL
            local deb_filename="rustdesk-${latest_version}-${download_arch}.deb"
            local latest_url="https://github.com/rustdesk/rustdesk/releases/download/${latest_version}/${deb_filename}"
            
            print_status "info" "Downloading RustDesk from GitHub..."
            print_status "config" "URL: $latest_url"
            
            if wget -O rustdesk.deb "$latest_url"; then
                print_status "success" "RustDesk downloaded successfully"
                
                # First, fix any existing broken dependencies
                print_status "info" "Checking for existing dependency issues..."
                sudo apt-get install -f -y || true
                
                # Install dependencies first - use minimal set to avoid conflicts
                print_status "info" "Installing RustDesk dependencies..."
                sudo apt-get update
                
                # Install only essential dependencies that won't cause conflicts
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
                
                for dep in "${essential_deps[@]}"; do
                    print_status "info" "Installing $dep..."
                    sudo apt-get install -y "$dep" || print_status "warning" "Failed to install $dep, continuing..."
                done
                
                # Try to install appindicator (handle both variants)
                if sudo apt-get install -y libayatana-appindicator3-1 2>/dev/null; then
                    print_status "info" "Installed libayatana-appindicator3-1"
                elif sudo apt-get install -y libappindicator3-1 2>/dev/null; then
                    print_status "info" "Installed libappindicator3-1"
                else
                    print_status "warning" "Could not install appindicator library, continuing..."
                fi
                
                print_status "info" "Installing RustDesk..."
                if sudo dpkg -i rustdesk.deb; then
                    print_status "success" "RustDesk installed via .deb package"
                else
                    print_status "warning" "dpkg installation had issues, fixing dependencies..."
                    sudo apt-get install -f -y
                    
                    # Verify installation
                    if dpkg -l | grep -q "^ii  rustdesk "; then
                        print_status "success" "RustDesk installed after fixing dependencies"
                    else
                        print_status "error" "Failed to install RustDesk via .deb package"
                        print_status "info" "Trying Flatpak installation..."
                        if flatpak install -y flathub com.rustdesk.RustDesk; then
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
                if flatpak install -y flathub com.rustdesk.RustDesk; then
                    print_status "success" "RustDesk installed via Flatpak"
                else
                    print_status "error" "Flatpak installation also failed"
                fi
            fi
            ;;
            
        dnf|yum)
            print_status "info" "Detecting system architecture..."
            
            # Detect architecture
            local arch=$(uname -m)
            local download_arch=""
            
            case "$arch" in
                x86_64)
                    download_arch="x86_64"
                    print_status "info" "Architecture: x86-64"
                    ;;
                aarch64)
                    download_arch="aarch64"
                    print_status "info" "Architecture: ARM 64-bit"
                    ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    flatpak install -y flathub com.rustdesk.RustDesk
                    cd - > /dev/null
                    return 0
                    ;;
            esac
            
            print_status "info" "Fetching latest RustDesk release..."
            
            # Get latest release info from GitHub API
            local latest_info=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest)
            local latest_version=$(echo "$latest_info" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            
            if [ -z "$latest_version" ]; then
                print_status "warning" "Could not fetch latest version, using fallback"
                latest_version="1.4.4"
            fi
            
            print_status "info" "Latest RustDesk version: $latest_version"
            
            # Construct download URL
            local rpm_filename="rustdesk-${latest_version}-${download_arch}.rpm"
            local latest_url="https://github.com/rustdesk/rustdesk/releases/download/${latest_version}/${rpm_filename}"
            
            print_status "info" "Downloading RustDesk from GitHub..."
            print_status "config" "URL: $latest_url"
            
            if wget -O rustdesk.rpm "$latest_url"; then
                print_status "info" "Installing RustDesk..."
                sudo $PACKAGE_MANAGER install -y rustdesk.rpm
                print_status "success" "RustDesk installed via .rpm package"
            else
                print_status "warning" "Download failed. Installing via Flatpak..."
                flatpak install -y flathub com.rustdesk.RustDesk
                print_status "success" "RustDesk installed via Flatpak"
            fi
            ;;
            
        pacman)
            if command_exists yay; then
                print_status "info" "Installing RustDesk from AUR..."
                yay -S --noconfirm rustdesk-bin
                print_status "success" "RustDesk installed from AUR"
            else
                print_status "info" "yay not found. Installing RustDesk via Flatpak..."
                flatpak install -y flathub com.rustdesk.RustDesk
                print_status "success" "RustDesk installed via Flatpak"
            fi
            ;;
            
        zypper)
            print_status "info" "Detecting system architecture..."
            
            # Detect architecture
            local arch=$(uname -m)
            local download_arch=""
            
            case "$arch" in
                x86_64)
                    download_arch="x86_64"
                    print_status "info" "Architecture: x86-64"
                    ;;
                aarch64)
                    download_arch="aarch64"
                    print_status "info" "Architecture: ARM 64-bit"
                    ;;
                *)
                    print_status "warning" "Unsupported architecture: $arch. Installing via Flatpak..."
                    flatpak install -y flathub com.rustdesk.RustDesk
                    cd - > /dev/null
                    return 0
                    ;;
            esac
            
            print_status "info" "Fetching latest RustDesk release..."
            
            # Get latest release info from GitHub API
            local latest_info=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest)
            local latest_version=$(echo "$latest_info" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            
            if [ -z "$latest_version" ]; then
                print_status "warning" "Could not fetch latest version, using fallback"
                latest_version="1.4.4"
            fi
            
            print_status "info" "Latest RustDesk version: $latest_version"
            
            # Construct download URL
            local rpm_filename="rustdesk-${latest_version}-${download_arch}.rpm"
            local latest_url="https://github.com/rustdesk/rustdesk/releases/download/${latest_version}/${rpm_filename}"
            
            print_status "info" "Downloading RustDesk from GitHub..."
            print_status "config" "URL: $latest_url"
            
            if wget -O rustdesk.rpm "$latest_url"; then
                print_status "info" "Installing RustDesk..."
                $INSTALL_CMD rustdesk.rpm
                print_status "success" "RustDesk installed via .rpm package"
            else
                print_status "warning" "Download failed. Installing via Flatpak..."
                flatpak install -y flathub com.rustdesk.RustDesk
                print_status "success" "RustDesk installed via Flatpak"
            fi
            ;;
    esac
    
    # Configure firewall for RustDesk (uses ports 21115-21119)
    print_status "info" "Configuring firewall for RustDesk..."
    case "$PACKAGE_MANAGER" in
        apt|pacman)
            if command_exists ufw; then
                sudo ufw allow 21115:21119/tcp comment "RustDesk" 2>/dev/null
                sudo ufw allow 21115:21119/udp comment "RustDesk" 2>/dev/null
                sudo ufw reload 2>/dev/null
                print_status "success" "Firewall configured for RustDesk (ports 21115-21119)"
            else
                print_status "info" "UFW not installed. Skipping firewall configuration."
            fi
            ;;
        dnf|yum|zypper)
            if command_exists firewall-cmd; then
                sudo firewall-cmd --permanent --add-port=21115-21119/tcp 2>/dev/null
                sudo firewall-cmd --permanent --add-port=21115-21119/udp 2>/dev/null
                sudo firewall-cmd --reload 2>/dev/null
                print_status "success" "Firewall configured for RustDesk (ports 21115-21119)"
            else
                print_status "info" "firewalld not installed. Skipping firewall configuration."
            fi
            ;;
    esac
    
    # Final verification
    if command_exists rustdesk || dpkg -l 2>/dev/null | grep -q "^ii  rustdesk " || flatpak list 2>/dev/null | grep -q "com.rustdesk.RustDesk"; then
        print_status "success" "RustDesk is ready to use"
        print_status "info" "RustDesk: Open-source remote desktop software"
        print_status "config" "Alternative to TeamViewer and AnyDesk"
        print_status "config" "Launch with: rustdesk"
        print_status "config" "You can set up your own relay server for better performance"
        
        # Show version if available
        if command_exists rustdesk; then
            rustdesk --version 2>&1 | head -n1 >> "$LOG_FILE" || true
        fi
    else
        print_status "warning" "RustDesk installation could not be verified"
        print_status "info" "You can install RustDesk manually from:"
        print_status "config" "https://github.com/rustdesk/rustdesk/releases"
        print_status "config" "Or via Flatpak: flatpak install flathub com.rustdesk.RustDesk"
    fi
    
    cd - > /dev/null
}

# ============================================================================
# SYSTEM OPTIMIZATION
# ============================================================================

cleanup_system() {
    print_status "section" "SYSTEM CLEANUP"

    # add lock verification
    if [ -f /var/lib/apt/lists/lock ]; then
        print_status "warning" "Apt lock detected, trying to release..."
        sudo rm -f /var/lib/apt/lists/lock
        sudo rm -f /var/lib/dpkg/lock
        sudo rm -f /var/lib/dpkg/lock-frontend
    fi
    
    # stop packagekitd temporarily
    sudo systemctl stop packagekitd 2>/dev/null || true
    
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
# ESPANSO INSTALLATION
# ============================================================================

install_espanso() {
    print_status "section" "ESPANSO (Text Expander)"

    if command_exists espanso; then
        print_status "success" "espanso is already installed: $(espanso --version 2>/dev/null || echo '')"
        return 0
    fi

    if ! check_internet; then
        print_status "error" "Internet connection required to install espanso"
        print_status "warning" "Skipping espanso installation due to no internet"
        return 0
    fi

    print_status "info" "Installing espanso using the official installer..."

    # Preferred method: official installer script (runs as non-root)
    if command_exists curl; then
        if curl -sS https://get.espanso.org/install.sh | sh; then
            print_status "success" "espanso installer finished"
        else
            print_status "warning" "espanso installer script failed, attempting package fallback"
        fi
    else
        print_status "info" "curl not found; installing curl and retrying installer"
        install_package curl curl curl curl
        if command_exists curl; then
            curl -sS https://get.espanso.org/install.sh | sh || true
        fi
    fi

    # If installer did not produce a usable binary, try Debian .deb fallback (requires sudo)
    if ! command_exists espanso && [ "$PACKAGE_MANAGER" = "apt" ]; then
        print_status "info" "Attempting Debian .deb installation as fallback (requires sudo)"
        # Determine session type: wayland or x11
        session_type="${XDG_SESSION_TYPE:-}"
        session_type="${session_type,,}"
        if [ -z "$session_type" ]; then
            # try to probe via loginctl (best-effort); default to x11 if unknown
            session_type=$(loginctl show-user "$USER" --property=Display | cut -d= -f2 2>/dev/null || true)
            session_type="${session_type,,}"
        fi
        if [ "$session_type" != "wayland" ]; then
            session_type="x11"
        fi

        TMPDIR=$(mktemp -d)
        cd "$TMPDIR" || true
        deb_url="https://github.com/espanso/espanso/releases/latest/download/espanso-debian-${session_type}-amd64.deb"
        print_status "info" "Downloading: $deb_url"
        # try wget then curl with retries
        wget --tries=3 --quiet -O espanso.deb "$deb_url" || curl -L --retry 3 -o espanso.deb "$deb_url" || true
        if [ -s espanso.deb ]; then
            print_status "info" "Installing espanso .deb (requires sudo)"
            sudo apt update || true
            sudo apt install -y ./espanso.deb || true
        else
            print_status "warning" "Could not download espanso .deb from $deb_url"
        fi
        cd - >/dev/null 2>&1 || true
        rm -rf "$TMPDIR"
    fi

    # AppImage fallback (works on any distro; registers env-path)
    if ! command_exists espanso; then
        print_status "info" "Attempting AppImage fallback (will place in ~/opt)"
        mkdir -p "$HOME/opt"
        app_image_url="https://github.com/espanso/espanso/releases/latest/download/Espanso-X11.AppImage"
        app_image_path="$HOME/opt/Espanso.AppImage"
        wget --tries=3 -q -O "$app_image_path" "$app_image_url" || curl -L --retry 3 -o "$app_image_path" "$app_image_url" || true
        if [ -s "$app_image_path" ]; then
            chmod u+x "$app_image_path" || true
            # register env-path (may require sudo for the wrapper)
            "$app_image_path" env-path register || true
        else
            print_status "warning" "AppImage fallback failed to download"
        fi
    fi

    if command_exists espanso; then
        print_status "success" "espanso installed: $(espanso --version 2>/dev/null || echo '')"
        # Grant required capability if available
        if command_exists setcap && command_exists espanso; then
            sudo setcap "cap_dac_override+p" "$(command -v espanso)" 2>/dev/null || true
        fi
        # Try to register and start user service (best-effort)
        if command_exists espanso; then
            espanso service register 2>/dev/null || true
            espanso start 2>/dev/null || true
        fi
    else
        print_status "warning" "espanso installation failed or binary not found in PATH"
        print_status "info" "Manual options:"
        print_status "config" "  - Use official installer: curl -sS https://get.espanso.org/install.sh | sh"
        print_status "config" "  - Download .deb: wget https://github.com/espanso/espanso/releases/latest/download/espanso-debian-x11-amd64.deb && sudo apt install ./espanso-debian-x11-amd64.deb"
        print_status "config" "  - Or install the AppImage into ~/opt and run: ~/opt/Espanso.AppImage env-path register"
    fi

    # Do not abort full installation if espanso failed; leave as warning
    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

show_menu() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}   ${MAGENTA}Multi-Distribution Development Environment Setup${NC}   ${CYAN}      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${GREEN}Detected System:${NC} $DISTRO"
    echo -e "${GREEN}Package Manager:${NC} $PACKAGE_MANAGER"
    if [ -n "$UBUNTU_VERSION" ]; then
        echo -e "${GREEN}Ubuntu Version:${NC} $UBUNTU_VERSION ($UBUNTU_CODENAME)"
    fi
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
    install_slack
    install_snap_apps
    install_flatpak_apps
    install_utilities
    install_flameshot
    install_warp_terminal
    install_virtual_machine_manager
    configure_gsconnect
    install_miro
    install_linear
    install_localsend
    install_rustdesk
    install_pinta
    install_insync
    install_clamav
    install_neovim
    install_ollama
    install_vitals  # Added Vitals installation
    install_espanso
    cleanup_system
    
    print_status "section" "INSTALLATION COMPLETE!"
    print_status "success" "All components installed successfully"
    print_status "info" "Log file: $LOG_FILE"
    print_status "warning" "Please reboot your system to complete the setup"
    print_status "info" "After reboot, verify installations:"
    print_status "config" "  - Homebrew: brew --version"
    print_status "config" "  - asdf: asdf --version"
    print_status "config" "  - Cursor: cursor --version"
    print_status "config" "  - Insync: insync start"
    print_status "config" "  - RustDesk: rustdesk"
    print_status "config" "  - Pinta: pinta (image editor)"
    print_status "config" "  - Flameshot: flameshot gui (for screenshots)"
    print_status "config" "  - Slack: slack (or check in applications menu)"
    print_status "config" "  - Neovim: nvim (run :PlugInstall after first launch)"
    print_status "config" "  - Ollama: ollama --version (AI platform)"
    print_status "config" "  - Vitals: Check GNOME extensions (system monitor)"
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
        "install_slack:Slack"
        "install_snap_apps:Snap Applications"
        "install_flatpak_apps:Flatpak Applications"
        "install_utilities:System Utilities"
        "install_flameshot:Flameshot Screenshot Tool"
        "install_warp_terminal:Warp Terminal"
        "install_virtual_machine_manager:VM Manager"
        "configure_gsconnect:GSConnect"
        "install_miro:Miro Collaboration Tool"
        "install_linear:Linear (Project Management)"
        "install_localsend:LocalSend File Sharing"
        "install_rustdesk:RustDesk Remote Desktop"
        "install_pinta:Pinta Image Editor"
        "install_insync:Insync (Google Drive)"
        "install_clamav:ClamAV Antivirus"
        "install_neovim:Neovim Text Editor"
        "install_ollama:Ollama AI Platform"
        "install_vitals:Vitals System Monitor"  # Added Vitals to custom installation
        "install_espanso:Espanso (Text Expander)"
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
    
    # Check if Homebrew, asdf, or Vitals were installed and remind user to reload shell
    if command_exists brew || command_exists asdf || command_exists ollama; then
        print_status "info" "Tools installed. Reload your shell:"
        print_status "config" "source ~/.bashrc"
    fi
    
    # Special note for Vitals
    if gnome-extensions list 2>/dev/null | grep -q "Vitals@CoreCoding.com"; then
        print_status "info" "Vitals extension installed. You may need to:"
        print_status "config" "1. Log out and log back in, OR"
        print_status "config" "2. Restart GNOME Shell: Alt+F2, type 'r', press Enter"
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