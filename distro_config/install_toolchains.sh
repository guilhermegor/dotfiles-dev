#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="$HOME/toolchains_installation_$(date +%Y%m%d_%H%M%S).log"

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

command_exists() {
    command -v "$1" &> /dev/null
}

get_asdf_version() {
    asdf --version 2>/dev/null | head -n1 | sed 's/asdf version //' || echo "unknown"
}

# ============================================================================
# ASDF COMMAND FUNCTIONS (version-specific)
# ============================================================================

# Set global version (compatible with asdf 0.18.0)
asdf_set_global() {
    local tool="$1"
    local version="$2"
    
    # In asdf 0.18.0, use "asdf set -g" instead of "asdf global"
    asdf set -g "$tool" "$version"
}

# Set local version (compatible with asdf 0.18.0)
asdf_set_local() {
    local tool="$1"
    local version="$2"
    
    asdf set -l "$tool" "$version"
}

# Check if a version is set globally
asdf_is_global_set() {
    local tool="$1"
    
    # Check ~/.tool-versions file
    if [ -f "$HOME/.tool-versions" ]; then
        grep -q "^$tool " "$HOME/.tool-versions"
        return $?
    fi
    return 1
}

# Get global version
asdf_get_global_version() {
    local tool="$1"
    
    if [ -f "$HOME/.tool-versions" ]; then
        grep "^$tool " "$HOME/.tool-versions" | awk '{print $2}'
    fi
}

# ============================================================================
# ASDF VERIFICATION
# ============================================================================

check_asdf() {
    print_status "section" "CHECKING ASDF VERSION MANAGER"
    
    if ! command_exists asdf; then
        print_status "error" "asdf version manager is not installed!"
        print_status "info" "asdf is required to install Node.js and Rust."
        print_status "warning" "Please install asdf first using one of these methods:"
        echo ""
        print_status "config" "Method 1: Run the install_programs.sh script"
        print_status "config" "  This script includes asdf installation and setup"
        echo ""
        print_status "config" "Method 2: Install asdf manually"
        print_status "config" "  1. Install Homebrew first (if not installed):"
        print_status "config" "     /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        print_status "config" "  2. Install asdf via Homebrew:"
        print_status "config" "     brew install asdf"
        print_status "config" "  3. Add to your shell configuration (~/.bashrc or ~/.zshrc):"
        print_status "config" "     echo '. \$(brew --prefix asdf)/libexec/asdf.sh' >> ~/.bashrc"
        print_status "config" "  4. Reload your shell:"
        print_status "config" "     source ~/.bashrc"
        echo ""
        exit 1
    fi
    
    local asdf_version=$(get_asdf_version)
    print_status "success" "asdf is installed (version: $asdf_version)"
    
    # Check asdf command structure
    print_status "info" "Detecting asdf command structure..."
    if asdf global --help &>/dev/null; then
        ASDF_GLOBAL_CMD="global"
        print_status "info" "Using 'asdf global' command"
    elif asdf set --help &>/dev/null; then
        ASDF_GLOBAL_CMD="set -g"
        print_status "info" "Using 'asdf set -g' command"
    else
        print_status "warning" "Could not detect asdf global command structure"
        print_status "info" "Will try both methods"
    fi
}

# ============================================================================
# TOOLCHAIN STATUS CHECK FUNCTIONS
# ============================================================================

is_tool_installed() {
    local tool="$1"
    asdf list "$tool" 2>/dev/null | grep -q .
}

get_installed_versions() {
    local tool="$1"
    asdf list "$tool" 2>/dev/null | sed 's/^\s*\*//;s/^\s*//;/^$/d'
}

get_latest_installed_version() {
    local tool="$1"
    get_installed_versions "$tool" | tail -n1 | xargs
}

is_tool_global_set() {
    local tool="$1"
    asdf_is_global_set "$tool"
}

get_current_global_version() {
    local tool="$1"
    asdf_get_global_version "$tool"
}

# ============================================================================
# NODE.JS INSTALLATION
# ============================================================================

install_nodejs() {
    print_status "section" "NODE.JS INSTALLATION"
    
    # Check if nodejs is already installed and has global version set
    if is_tool_installed "nodejs" && is_tool_global_set "nodejs"; then
        local current_version=$(get_current_global_version "nodejs")
        print_status "info" "Node.js is already installed with version $current_version set as global"
        print_status "info" "Skipping Node.js installation as requested"
        return 0
    fi
    
    # Check if nodejs plugin is already added
    if ! asdf plugin list | grep -q "^nodejs$"; then
        print_status "info" "Adding Node.js plugin to asdf..."
        asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
        print_status "success" "Node.js plugin added"
    else
        print_status "info" "Node.js plugin already installed"
    fi
    
    # Ask for version if not already installed
    local installed_versions=$(get_installed_versions "nodejs")
    local latest_installed=$(get_latest_installed_version "nodejs")
    
    if [ -n "$installed_versions" ]; then
        print_status "info" "Node.js is already installed with version(s):"
        echo "$installed_versions" | while read version; do
            print_status "config" "  - $version"
        done
        
        # If already installed but no global version set, set the latest installed as global
        if [ -n "$latest_installed" ] && ! is_tool_global_set "nodejs"; then
            print_status "info" "Setting latest installed version ($latest_installed) as global default"
            
            # Try multiple methods to set global version
            if asdf set -g nodejs "$latest_installed" 2>/dev/null; then
                print_status "success" "Node.js $latest_installed set as global default (using 'asdf set -g')"
            elif asdf global nodejs "$latest_installed" 2>/dev/null; then
                print_status "success" "Node.js $latest_installed set as global default (using 'asdf global')"
            else
                # Directly write to ~/.tool-versions file
                echo "nodejs $latest_installed" > "$HOME/.tool-versions"
                print_status "success" "Node.js $latest_installed set as global default (direct write to ~/.tool-versions)"
            fi
            
            # Reshim to make tools available immediately
            asdf reshim nodejs "$latest_installed" 2>/dev/null && print_status "info" "Shims refreshed"
            return 0
        fi
        
        echo -e "\n${YELLOW}Do you want to install another version? (y/n):${NC}"
        read -r install_another
        if [[ ! "$install_another" =~ ^[Yy]$ ]]; then
            print_status "info" "Skipping Node.js installation"
            return 0
        fi
    fi
    
    # Ask for version
    echo -e "\n${YELLOW}Enter Node.js version to install (or press Enter for latest):${NC}"
    echo -e "${CYAN}Examples: 20.11.0, 18.19.0, latest${NC}"
    read -r node_version
    
    # Default to latest if empty
    if [ -z "$node_version" ]; then
        node_version="latest"
        print_status "info" "No version specified, installing latest Node.js"
    fi
    
    print_status "info" "Installing Node.js $node_version..."
    print_status "warning" "This may take a few minutes..."
    
    if asdf install nodejs "$node_version" 2>&1 | tee -a "$LOG_FILE"; then
        # Get the actual version that was installed
        local installed_version=$(asdf list nodejs 2>/dev/null | tail -n1 | sed 's/^\s*\*//;s/^\s*//')
        
        if [ -z "$installed_version" ]; then
            # Try to get the version from the installation log
            installed_version=$(grep "Installed node-" "$LOG_FILE" | tail -n1 | sed 's/.*node-//;s/-.*//')
        fi
        
        if [ -z "$installed_version" ]; then
            installed_version="$node_version"
        fi
        
        print_status "success" "Node.js $installed_version installed successfully"
        
        # Always set the newly installed version as global
        print_status "info" "Setting $installed_version as global default..."
        
        # Try multiple methods to set global version
        if asdf set -g nodejs "$installed_version" 2>/dev/null; then
            print_status "success" "Node.js $installed_version set as global default (using 'asdf set -g')"
        elif asdf global nodejs "$installed_version" 2>/dev/null; then
            print_status "success" "Node.js $installed_version set as global default (using 'asdf global')"
        else
            # Directly write to ~/.tool-versions file
            if [ -f "$HOME/.tool-versions" ]; then
                # Update existing file
                if grep -q "^nodejs " "$HOME/.tool-versions"; then
                    sed -i "s/^nodejs .*/nodejs $installed_version/" "$HOME/.tool-versions"
                else
                    echo "nodejs $installed_version" >> "$HOME/.tool-versions"
                fi
            else
                echo "nodejs $installed_version" > "$HOME/.tool-versions"
            fi
            print_status "success" "Node.js $installed_version set as global default (direct write to ~/.tool-versions)"
        fi
        
        # Reshim to make tools available immediately
        asdf reshim nodejs "$installed_version" 2>/dev/null && print_status "info" "Shims refreshed"
        
        # Verify installation
        print_status "info" "Verifying installation..."
        
        # Source asdf to make sure we have the latest shims
        source "$HOME/.asdf/asdf.sh" 2>/dev/null || true
        
        # Check node version
        if command_exists node; then
            local node_current_version=$(node --version 2>/dev/null || echo "Not available")
            print_status "info" "Node.js current version: $node_current_version"
        else
            print_status "warning" "Node.js command not found. You may need to restart your shell."
        fi
        
        # Check npm version
        if command_exists npm; then
            local npm_version=$(npm --version 2>/dev/null || echo "Not available")
            print_status "info" "npm version: $npm_version"
        fi
        
        # Usage tips
        echo ""
        print_status "info" "Node.js management commands:"
        print_status "config" "  List all available versions: asdf list all nodejs"
        print_status "config" "  List installed versions: asdf list nodejs"
        print_status "config" "  Install specific version: asdf install nodejs 18.19.0"
        print_status "config" "  Set global version: asdf set -g nodejs 20.11.0"
        print_status "config" "  Set local version (project): asdf set -l nodejs 18.19.0"
        print_status "config" "  Check current version: node --version"
        
    else
        print_status "error" "Failed to install Node.js $node_version"
        return 1
    fi
}

# ============================================================================
# RUST INSTALLATION
# ============================================================================

install_rust() {
    print_status "section" "RUST INSTALLATION"
    
    # Check if rust is already installed and has global version set
    if is_tool_installed "rust" && is_tool_global_set "rust"; then
        local current_version=$(get_current_global_version "rust")
        print_status "info" "Rust is already installed with version $current_version set as global"
        print_status "info" "Skipping Rust installation as requested"
        return 0
    fi
    
    # Check if rust plugin is already added
    if ! asdf plugin list | grep -q "^rust$"; then
        print_status "info" "Adding Rust plugin to asdf..."
        asdf plugin add rust https://github.com/asdf-community/asdf-rust.git
        print_status "success" "Rust plugin added"
    else
        print_status "info" "Rust plugin already installed"
    fi
    
    # Ask for version if not already installed
    local installed_versions=$(get_installed_versions "rust")
    local latest_installed=$(get_latest_installed_version "rust")
    
    if [ -n "$installed_versions" ]; then
        print_status "info" "Rust is already installed with version(s):"
        echo "$installed_versions" | while read version; do
            print_status "config" "  - $version"
        done
        
        # If already installed but no global version set, set the latest installed as global
        if [ -n "$latest_installed" ] && ! is_tool_global_set "rust"; then
            print_status "info" "Setting latest installed version ($latest_installed) as global default"
            
            # Try multiple methods to set global version
            if asdf set -g rust "$latest_installed" 2>/dev/null; then
                print_status "success" "Rust $latest_installed set as global default (using 'asdf set -g')"
            elif asdf global rust "$latest_installed" 2>/dev/null; then
                print_status "success" "Rust $latest_installed set as global default (using 'asdf global')"
            else
                # Directly write to ~/.tool-versions file
                if [ -f "$HOME/.tool-versions" ]; then
                    # Update existing file
                    if grep -q "^rust " "$HOME/.tool-versions"; then
                        sed -i "s/^rust .*/rust $latest_installed/" "$HOME/.tool-versions"
                    else
                        echo "rust $latest_installed" >> "$HOME/.tool-versions"
                    fi
                else
                    echo "rust $latest_installed" > "$HOME/.tool-versions"
                fi
                print_status "success" "Rust $latest_installed set as global default (direct write to ~/.tool-versions)"
            fi
            
            # Reshim to make tools available immediately
            asdf reshim rust "$latest_installed" 2>/dev/null && print_status "info" "Shims refreshed"
            return 0
        fi
        
        echo -e "\n${YELLOW}Do you want to install another version? (y/n):${NC}"
        read -r install_another
        if [[ ! "$install_another" =~ ^[Yy]$ ]]; then
            print_status "info" "Skipping Rust installation"
            return 0
        fi
    fi
    
    # Ask for version
    echo -e "\n${YELLOW}Enter Rust version to install (or press Enter for latest):${NC}"
    echo -e "${CYAN}Examples: 1.75.0, 1.74.1, stable, nightly, latest${NC}"
    read -r rust_version
    
    # Default to latest if empty
    if [ -z "$rust_version" ]; then
        rust_version="latest"
        print_status "info" "No version specified, installing latest stable Rust"
    fi
    
    print_status "info" "Installing Rust $rust_version..."
    print_status "warning" "This may take several minutes (Rust compiles from source)..."
    
    if asdf install rust "$rust_version" 2>&1 | tee -a "$LOG_FILE"; then
        # Get the actual version that was installed
        local installed_version=$(asdf list rust 2>/dev/null | tail -n1 | sed 's/^\s*\*//;s/^\s*//')
        
        if [ -z "$installed_version" ]; then
            # Try to get the version from the installation log
            installed_version=$(grep -E "Installed rust-|Installed version" "$LOG_FILE" | tail -n1 | sed 's/.*rust-//;s/\s.*//')
        fi
        
        if [ -z "$installed_version" ]; then
            installed_version="$rust_version"
        fi
        
        print_status "success" "Rust $installed_version installed successfully"
        
        # Always set the newly installed version as global
        print_status "info" "Setting $installed_version as global default..."
        
        # Try multiple methods to set global version
        if asdf set -g rust "$installed_version" 2>/dev/null; then
            print_status "success" "Rust $installed_version set as global default (using 'asdf set -g')"
        elif asdf global rust "$installed_version" 2>/dev/null; then
            print_status "success" "Rust $installed_version set as global default (using 'asdf global')"
        else
            # Directly write to ~/.tool-versions file
            if [ -f "$HOME/.tool-versions" ]; then
                # Update existing file
                if grep -q "^rust " "$HOME/.tool-versions"; then
                    sed -i "s/^rust .*/rust $installed_version/" "$HOME/.tool-versions"
                else
                    echo "rust $installed_version" >> "$HOME/.tool-versions"
                fi
            else
                echo "rust $installed_version" > "$HOME/.tool-versions"
            fi
            print_status "success" "Rust $installed_version set as global default (direct write to ~/.tool-versions)"
        fi
        
        # Reshim to make tools available immediately
        asdf reshim rust "$installed_version" 2>/dev/null && print_status "info" "Shims refreshed"
        
        # Verify installation
        print_status "info" "Verifying installation..."
        
        # Source asdf to make sure we have the latest shims
        source "$HOME/.asdf/asdf.sh" 2>/dev/null || true
        
        # Check rustc version
        if command_exists rustc; then
            local rustc_version=$(rustc --version 2>/dev/null || echo "Not available")
            print_status "info" "Rust current version: $rustc_version"
        else
            print_status "warning" "Rust command not found. You may need to restart your shell."
        fi
        
        # Check cargo version
        if command_exists cargo; then
            local cargo_version=$(cargo --version 2>/dev/null || echo "Not available")
            print_status "info" "Cargo version: $cargo_version"
        fi
        
        # Usage tips
        echo ""
        print_status "info" "Rust management commands:"
        print_status "config" "  List all available versions: asdf list all rust"
        print_status "config" "  List installed versions: asdf list rust"
        print_status "config" "  Install specific version: asdf install rust 1.75.0"
        print_status "config" "  Install stable: asdf install rust stable"
        print_status "config" "  Install nightly: asdf install rust nightly"
        print_status "config" "  Set global version: asdf set -g rust 1.75.0"
        print_status "config" "  Set local version (project): asdf set -l rust stable"
        print_status "config" "  Check current version: rustc --version"
        print_status "config" "  Update Rust components: rustup update (if using rustup)"
        
    else
        print_status "error" "Failed to install Rust $rust_version"
        return 1
    fi
}

# ============================================================================
# MENU AND MAIN EXECUTION
# ============================================================================

show_menu() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}               ${MAGENTA}Toolchains Installation via asdf${NC}             ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Select installation option:${NC}"
    echo -e "  ${GREEN}1)${NC} Install Node.js only"
    echo -e "  ${GREEN}2)${NC} Install Rust only"
    echo -e "  ${GREEN}3)${NC} Install all toolchains"
    echo -e "  ${GREEN}4)${NC} Exit"
    echo -e "\n${CYAN}Choice: ${NC}"
}

main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then 
        print_status "error" "This script should NOT be run with sudo!"
        print_status "info" "Please run as: bash $0"
        exit 1
    fi
    
    # Ensure asdf is sourced
    if [ -f "$HOME/.asdf/asdf.sh" ]; then
        source "$HOME/.asdf/asdf.sh"
    elif [ -f "/opt/homebrew/opt/asdf/libexec/asdf.sh" ]; then
        source "/opt/homebrew/opt/asdf/libexec/asdf.sh"
    elif [ -f "/usr/local/opt/asdf/libexec/asdf.sh" ]; then
        source "/usr/local/opt/asdf/libexec/asdf.sh"
    fi
    
    # Check if asdf is installed
    check_asdf
    
    # Show menu
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                install_nodejs
                break
                ;;
            2)
                install_rust
                break
                ;;
            3)
                install_nodejs
                echo ""
                install_rust
                break
                ;;
            4)
                print_status "info" "Installation cancelled"
                exit 0
                ;;
            *)
                print_status "error" "Invalid option. Please select 1, 2, 3, or 4."
                ;;
        esac
    done
    
    print_status "section" "INSTALLATION COMPLETE!"
    print_status "info" "Log file: $LOG_FILE"
    
    # Final verification
    echo ""
    print_status "info" "Current tool versions:"
    
    # Source asdf one more time to ensure latest shims
    source "$HOME/.asdf/asdf.sh" 2>/dev/null || true
    
    # Check node
    if command_exists node; then
        print_status "config" "  Node.js: $(node --version 2>/dev/null || echo 'Not available')"
    else
        print_status "config" "  Node.js: Not available in current shell"
    fi
    
    # Check npm
    if command_exists npm; then
        print_status "config" "  npm: $(npm --version 2>/dev/null || echo 'Not available')"
    fi
    
    # Check rustc
    if command_exists rustc; then
        print_status "config" "  Rust: $(rustc --version 2>/dev/null || echo 'Not available')"
    fi
    
    # Check cargo
    if command_exists cargo; then
        print_status "config" "  Cargo: $(cargo --version 2>/dev/null || echo 'Not available')"
    fi
    
    echo ""
    print_status "info" "Global versions set in ~/.tool-versions:"
    if [ -f "$HOME/.tool-versions" ]; then
        cat "$HOME/.tool-versions" | while read line; do
            print_status "config" "  $line"
        done
    else
        print_status "config" "  No global versions file found"
    fi
    
    print_status "warning" "\nImportant: You may need to reload your shell for changes to take effect:"
    print_status "config" "source ~/.bashrc  # or source ~/.zshrc"
    echo ""
    print_status "info" "Quick reference:"
    print_status "config" "  Check installed versions: asdf current"
    print_status "config" "  View all managed tools: asdf plugin list"
    print_status "config" "  Project-specific versions: Create .tool-versions file"
    echo ""
}

# Execute main function
main "$@"