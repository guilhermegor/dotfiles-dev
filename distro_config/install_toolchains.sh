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

# Install an npm package globally for every nvm-managed Node version.
# Each nvm version keeps its own global node_modules tree, so a plain
# "npm install -g" only covers the currently active version.
npm_global_install_all_nvm_versions() {
    local package="$1"
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"

    if [ ! -s "$nvm_dir/nvm.sh" ]; then
        print_status "warning" "nvm not found at $nvm_dir; skipping multi-version install"
        return 1
    fi

    export NVM_DIR="$nvm_dir"
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"

    local versions
    versions=$(nvm ls --no-colors 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -Vu)

    if [ -z "$versions" ]; then
        print_status "warning" "No nvm-managed Node versions found"
        return 1
    fi

    print_status "info" "Found nvm-managed Node versions:"
    while IFS= read -r ver; do
        print_status "config" "  $ver"
    done <<< "$versions"
    echo ""

    local -a failed_versions=()
    while IFS= read -r ver; do
        print_status "info" "[$ver] npm install -g $package ..."
        if nvm exec "${ver#v}" npm install -g "$package" 2>&1 | tee -a "$LOG_FILE"; then
            print_status "success" "  $ver: installed"
        else
            print_status "error" "  $ver: failed"
            failed_versions+=("$ver")
        fi
    done <<< "$versions"

    if [ "${#failed_versions[@]}" -gt 0 ]; then
        print_status "warning" "Failed for Node versions: ${failed_versions[*]}"
        return 1
    fi

    print_status "success" "$package installed across all nvm Node versions"
}

# Thin wrapper around "npm install -g": when nvm is present, lists all
# managed Node versions and offers to install across all of them.
npm_install_global() {
    local package_spec="$1"
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"

    if [ -s "$nvm_dir/nvm.sh" ]; then
        export NVM_DIR="$nvm_dir"
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh"

        local versions
        versions=$(nvm ls --no-colors 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -Vu)

        if [ -n "$versions" ]; then
            echo -e "\n${CYAN}nvm-managed Node versions detected:${NC}"
            while IFS= read -r ver; do
                print_status "config" "  $ver"
            done <<< "$versions"

            echo -e "\n${YELLOW}Install ${package_spec} across ALL versions above? (y/n):${NC}"
            echo -e "${CYAN}Ensures the package is available regardless of active Node version${NC}"
            local install_all_nvm
            read -r install_all_nvm
            if [[ "$install_all_nvm" =~ ^[Yy]$ ]]; then
                npm_global_install_all_nvm_versions "$package_spec"
                return $?
            fi
        fi
    fi

    npm install -g "$package_spec" 2>&1 | tee -a "$LOG_FILE"
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
        
        # Check npx version (npx comes with npm 5.2+)
        if command_exists npx; then
            local npx_version=$(npx --version 2>/dev/null || echo "Not available")
            print_status "info" "npx version: $npx_version"
        else
            print_status "info" "npx not found (it may come with newer npm versions)"
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
# NVM (NODE VERSION MANAGER) INSTALLATION
# ============================================================================

install_nvm() {
    print_status "section" "NVM (Node Version Manager) Installation"
    
    # Check if nvm is already installed
    if command_exists nvm || [ -d "$HOME/.nvm" ]; then
        nvm_version=$(nvm --version 2>/dev/null || echo "unknown")
        print_status "warning" "NVM is already installed (version: $nvm_version)"
        
        read -r -p "Do you want to reinstall NVM? (y/n): " reinstall_nvm
        if [[ ! "$reinstall_nvm" =~ ^[Yy]$ ]]; then
            print_status "info" "Skipping NVM installation"
            return 0
        fi
    fi
    
    # Install dependencies
    print_status "info" "Installing required dependencies..."
    dependencies=("curl" "wget" "git")
    
    for dep in "${dependencies[@]}"; do
        if ! command_exists "$dep"; then
            print_status "warning" "Installing $dep..."
            if command_exists apt-get; then
                sudo apt-get update -qq && sudo apt-get install -y "$dep" > /dev/null 2>&1
            elif command_exists yum; then
                sudo yum install -y "$dep" > /dev/null 2>&1
            elif command_exists brew; then
                brew install "$dep" > /dev/null 2>&1
            else
                print_status "error" "Unable to install $dep. Please install it manually."
                return 1
            fi
        fi
    done
    
    # Download and install nvm
    print_status "info" "Downloading NVM..."
    NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")' || echo "v0.39.0")
    NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
    
    print_status "info" "Installing NVM ${NVM_VERSION}..."
    
    if curl -o- "$NVM_INSTALL_URL" 2>&1 | tee -a "$LOG_FILE" | bash; then
        # Source nvm
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        
        print_status "success" "NVM installed successfully"
        
        # Get installed version
        local nvm_version=$(nvm --version 2>/dev/null || echo "")
        if [ -n "$nvm_version" ]; then
            print_status "info" "NVM version: $nvm_version"
        fi
        
        # Ask for Node.js version
        echo ""
        echo -e "${YELLOW}Install a Node.js version with NVM?${NC}"
        echo -e "${CYAN}1) LTS (recommended)${NC}"
        echo -e "${CYAN}2) Latest${NC}"
        echo -e "${CYAN}3) Specific version${NC}"
        echo -e "${CYAN}4) Skip${NC}"
        echo -e "${CYAN}Enter 1-4 (default: 1):${NC}"
        read -r nodejs_choice
        
        case "$nodejs_choice" in
            1)
                print_status "info" "Installing Node.js LTS..."
                nvm install --lts 2>&1 | tee -a "$LOG_FILE"
                nvm use --lts 2>&1 | tee -a "$LOG_FILE"
                print_status "success" "Node.js LTS installed: $(node --version)"
                ;;
            2)
                print_status "info" "Installing latest Node.js..."
                nvm install node 2>&1 | tee -a "$LOG_FILE"
                nvm use node 2>&1 | tee -a "$LOG_FILE"
                print_status "success" "Node.js latest installed: $(node --version)"
                ;;
            3)
                echo -e "${CYAN}Enter Node.js version (e.g., 18.17.0):${NC}"
                read -r nodejs_version
                if [ -n "$nodejs_version" ]; then
                    print_status "info" "Installing Node.js $nodejs_version..."
                    nvm install "$nodejs_version" 2>&1 | tee -a "$LOG_FILE"
                    nvm use "$nodejs_version" 2>&1 | tee -a "$LOG_FILE"
                    print_status "success" "Node.js $nodejs_version installed: $(node --version)"
                else
                    print_status "warning" "No version specified. Skipping Node.js installation."
                fi
                ;;
            *)
                print_status "info" "Skipping Node.js installation"
                ;;
        esac
        
        # Set up shell configuration
        print_status "info" "Configuring shell initialization..."
        
        local shell_rc="$HOME/.bashrc"
        [ -f "$HOME/.zshrc" ] && shell_rc="$HOME/.zshrc"
        
        if [ -f "$shell_rc" ]; then
            # Check if nvm is already sourced
            if ! grep -q 'export NVM_DIR=' "$shell_rc"; then
                cat >> "$shell_rc" << 'EOF'

# NVM configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
EOF
                print_status "success" "NVM configuration added to $shell_rc"
            fi
        fi
        
        # Usage tips
        echo ""
        print_status "info" "NVM usage:"
        print_status "config" "  Install LTS: nvm install --lts"
        print_status "config" "  Install latest: nvm install node"
        print_status "config" "  List installed: nvm list"
        print_status "config" "  List remote: nvm list-remote"
        print_status "config" "  Use version: nvm use <version>"
        print_status "config" "  Set default: nvm alias default <version>"
        print_status "config" "  Uninstall: nvm uninstall <version>"
        
        print_status "warning" "Important: Reload your shell for changes to take effect:"
        print_status "config" "source $shell_rc"
        
    else
        print_status "error" "Failed to install NVM"
        return 1
    fi
}

# ============================================================================
# NPX INSTALLATION
# ============================================================================

install_npx() {
    print_status "section" "NPX INSTALLATION"
    
    # Check if Node.js is installed
    if ! is_tool_installed "nodejs"; then
        print_status "error" "Node.js is not installed! NPX requires Node.js."
        echo -e "\n${YELLOW}Do you want to install Node.js first? (y/n):${NC}"
        read -r install_nodejs_first
        
        if [[ "$install_nodejs_first" =~ ^[Yy]$ ]]; then
            install_nodejs
        else
            print_status "warning" "Skipping NPX installation as Node.js is required"
            return 1
        fi
    fi
    
    # Check if npm is available
    if ! command_exists npm; then
        print_status "error" "npm is not available. Please ensure Node.js is properly installed."
        return 1
    fi
    
    # Check if npx is already available (npx comes with npm 5.2+)
    print_status "info" "Checking for existing NPX installation..."
    
    # Try to get npx version
    local npx_version=""
    if command_exists npx; then
        npx_version=$(npx --version 2>/dev/null || echo "")
    fi
    
    if [ -n "$npx_version" ]; then
        print_status "info" "NPX is already available (version: $npx_version)"
        print_status "info" "NPX typically comes bundled with npm 5.2.0 and above"
        
        echo -e "\n${YELLOW}Do you want to install/update NPX globally anyway? (y/n):${NC}"
        echo -e "${CYAN}Note: This will install NPX globally via npm${NC}"
        read -r update_npx
        if [[ ! "$update_npx" =~ ^[Yy]$ ]]; then
            print_status "info" "Keeping existing NPX version"
            return 0
        fi
    else
        print_status "info" "NPX not found in PATH"
        print_status "info" "NPX typically comes with npm 5.2+. Your npm version: $(npm --version 2>/dev/null || echo 'unknown')"
    fi
    
    # Ask for NPX installation
    echo -e "\n${YELLOW}Install NPX globally via npm? (y/n):${NC}"
    echo -e "${CYAN}This will install NPX via: npm install -g npx${NC}"
    echo -e "${YELLOW}Note: If you have npm 5.2+, npx should already be available${NC}"
    read -r install_npx
    
    if [[ ! "$install_npx" =~ ^[Yy]$ ]]; then
        print_status "info" "Skipping NPX installation"
        return 0
    fi
    
    # Ask for specific version
    echo -e "\n${YELLOW}Enter NPX version to install (or press Enter for latest):${NC}"
    echo -e "${CYAN}Examples: latest, 10.2.0, 7.1.0${NC}"
    echo -e "${CYAN}Note: Latest versions of npx are included in npm. Installing separately is optional.${NC}"
    read -r npx_version_input
    
    local package_spec="npx"
    if [ -n "$npx_version_input" ] && [ "$npx_version_input" != "latest" ]; then
        package_spec="npx@$npx_version_input"
        print_status "info" "Installing NPX $npx_version_input..."
    else
        print_status "info" "Installing latest NPX version..."
    fi

    print_status "warning" "This may take a moment..."

    if npm_install_global "$package_spec"; then
        # Get the installed version
        npx_version=$(npx --version 2>/dev/null || echo "")
        
        if [ -n "$npx_version" ]; then
            print_status "success" "NPX $npx_version installed successfully"
        else
            print_status "success" "NPX installed successfully"
        fi
        
        # Verify installation
        print_status "info" "Verifying installation..."
        
        # Check npx version
        if command_exists npx; then
            local actual_npx_version=$(npx --version 2>/dev/null || echo "Not available")
            print_status "info" "NPX version: $actual_npx_version"
        else
            print_status "warning" "NPX command not found. You may need to reload your shell."
        fi
        
        # Usage tips
        echo ""
        print_status "info" "NPX management commands:"
        print_status "config" "  Check version: npx --version"
        print_status "config" "  Run command without installing: npx create-react-app my-app"
        print_status "config" "  Execute local binaries: npx jest"
        print_status "config" "  Update NPX: npm update -g npx"
        print_status "config" "  Install specific version: npm install -g npx@10.2.0"
        print_status "config" "  Note: NPX comes bundled with npm 5.2+"
        
        # Check if npx came from npm or separate installation
        if command_exists npm; then
            local npm_version=$(npm --version 2>/dev/null)
            if [[ "$npm_version" =~ ^[5-9]\. ]]; then
                print_status "info" "Your npm version ($npm_version) includes npx natively"
            fi
        fi
        
    else
        print_status "error" "Failed to install NPX"
        return 1
    fi
}

# ============================================================================
# TYPESCRIPT INSTALLATION
# ============================================================================

install_typescript() {
    print_status "section" "TYPESCRIPT INSTALLATION"
    
    # Check if Node.js is installed
    if ! is_tool_installed "nodejs"; then
        print_status "error" "Node.js is not installed! TypeScript requires Node.js."
        echo -e "\n${YELLOW}Do you want to install Node.js first? (y/n):${NC}"
        read -r install_nodejs_first
        
        if [[ "$install_nodejs_first" =~ ^[Yy]$ ]]; then
            install_nodejs
        else
            print_status "warning" "Skipping TypeScript installation as Node.js is required"
            return 1
        fi
    fi
    
    # Check if npm is available
    if ! command_exists npm; then
        print_status "error" "npm is not available. Please ensure Node.js is properly installed."
        return 1
    fi
    
    # Check if TypeScript is already installed globally
    print_status "info" "Checking for existing TypeScript installation..."
    
    # Try to get TypeScript version
    local tsc_version=$(npm list -g typescript 2>/dev/null | grep typescript@ | head -1 | sed 's/.*typescript@//' | cut -d' ' -f1)
    
    if [ -n "$tsc_version" ]; then
        print_status "info" "TypeScript is already installed globally (version: $tsc_version)"
        
        echo -e "\n${YELLOW}Do you want to update TypeScript to the latest version? (y/n):${NC}"
        read -r update_ts
        if [[ ! "$update_ts" =~ ^[Yy]$ ]]; then
            print_status "info" "Keeping existing TypeScript version $tsc_version"
            return 0
        fi
    fi
    
    # Ask for TypeScript installation
    echo -e "\n${YELLOW}Install TypeScript globally? (y/n):${NC}"
    echo -e "${CYAN}This will install TypeScript via: npm install -g typescript${NC}"
    read -r install_ts
    
    if [[ ! "$install_ts" =~ ^[Yy]$ ]]; then
        print_status "info" "Skipping TypeScript installation"
        return 0
    fi
    
    # Ask for specific version
    echo -e "\n${YELLOW}Enter TypeScript version to install (or press Enter for latest):${NC}"
    echo -e "${CYAN}Examples: latest, 5.3.0, 5.2.0, 4.9.0${NC}"
    read -r ts_version
    
    local package_spec="typescript"
    if [ -n "$ts_version" ] && [ "$ts_version" != "latest" ]; then
        package_spec="typescript@$ts_version"
        print_status "info" "Installing TypeScript $ts_version..."
    else
        print_status "info" "Installing latest TypeScript version..."
    fi

    print_status "warning" "This may take a moment..."

    if npm_install_global "$package_spec"; then
        # Get the installed version
        tsc_version=$(npm list -g typescript 2>/dev/null | grep typescript@ | head -1 | sed 's/.*typescript@//' | cut -d' ' -f1)
        
        if [ -n "$tsc_version" ]; then
            print_status "success" "TypeScript $tsc_version installed successfully"
        else
            print_status "success" "TypeScript installed successfully"
        fi
        
        # Verify installation
        print_status "info" "Verifying installation..."
        
        # Check tsc version
        if command_exists tsc; then
            local actual_tsc_version=$(tsc --version 2>/dev/null | sed 's/Version //' || echo "Not available")
            print_status "info" "TypeScript compiler version: $actual_tsc_version"
        else
            print_status "warning" "TypeScript compiler (tsc) command not found. You may need to reload your shell."
        fi
        
        # Usage tips
        echo ""
        print_status "info" "TypeScript management commands:"
        print_status "config" "  Check version: tsc --version"
        print_status "config" "  Compile TypeScript: tsc filename.ts"
        print_status "config" "  Initialize tsconfig: tsc --init"
        print_status "config" "  Update TypeScript: npm update -g typescript"
        print_status "config" "  Install specific version: npm install -g typescript@5.3.0"
        print_status "config" "  List globally installed packages: npm list -g --depth=0"
        
    else
        print_status "error" "Failed to install TypeScript"
        return 1
    fi
}

# ============================================================================
# NESTJS CLI INSTALLATION
# ============================================================================

install_nestjs() {
    print_status "section" "NESTJS CLI INSTALLATION"
    
    # Check if Node.js is installed
    if ! is_tool_installed "nodejs"; then
        print_status "error" "Node.js is not installed! NestJS CLI requires Node.js."
        echo -e "\n${YELLOW}Do you want to install Node.js first? (y/n):${NC}"
        read -r install_nodejs_first
        
        if [[ "$install_nodejs_first" =~ ^[Yy]$ ]]; then
            install_nodejs
        else
            print_status "warning" "Skipping NestJS CLI installation as Node.js is required"
            return 1
        fi
    fi
    
    # Check if npm is available
    if ! command_exists npm; then
        print_status "error" "npm is not available. Please ensure Node.js is properly installed."
        return 1
    fi
    
    # Check if NestJS CLI is already installed globally
    print_status "info" "Checking for existing NestJS CLI installation..."
    
    local nestjs_version=$(npm list -g @nestjs/cli 2>/dev/null | grep @nestjs/cli@ | head -1 | sed 's/.*@nestjs\/cli@//' | cut -d' ' -f1)
    
    if [ -n "$nestjs_version" ]; then
        print_status "info" "NestJS CLI is already installed globally (version: $nestjs_version)"
        
        echo -e "\n${YELLOW}Do you want to update NestJS CLI to the latest version? (y/n):${NC}"
        read -r update_nestjs
        if [[ ! "$update_nestjs" =~ ^[Yy]$ ]]; then
            print_status "info" "Keeping existing NestJS CLI version $nestjs_version"
            return 0
        fi
    fi
    
    # Ask for NestJS CLI installation
    echo -e "\n${YELLOW}Install NestJS CLI globally? (y/n):${NC}"
    echo -e "${CYAN}This will install NestJS CLI via: npm install -g @nestjs/cli${NC}"
    read -r install_nestjs
    
    if [[ ! "$install_nestjs" =~ ^[Yy]$ ]]; then
        print_status "info" "Skipping NestJS CLI installation"
        return 0
    fi
    
    # Ask for specific version
    echo -e "\n${YELLOW}Enter NestJS CLI version to install (or press Enter for latest):${NC}"
    echo -e "${CYAN}Examples: latest, 10.4.0, 10.3.2${NC}"
    read -r nestjs_version_input
    
    local package_spec="@nestjs/cli"
    if [ -n "$nestjs_version_input" ] && [ "$nestjs_version_input" != "latest" ]; then
        package_spec="@nestjs/cli@$nestjs_version_input"
        print_status "info" "Installing NestJS CLI $nestjs_version_input..."
    else
        print_status "info" "Installing latest NestJS CLI version..."
    fi

    print_status "warning" "This may take a moment..."

    if npm_install_global "$package_spec"; then
        # Get the installed version
        nestjs_version=$(npm list -g @nestjs/cli 2>/dev/null | grep @nestjs/cli@ | head -1 | sed 's/.*@nestjs\/cli@//' | cut -d' ' -f1)
        
        if [ -n "$nestjs_version" ]; then
            print_status "success" "NestJS CLI $nestjs_version installed successfully"
        else
            print_status "success" "NestJS CLI installed successfully"
        fi
        
        # Verify installation
        print_status "info" "Verifying installation..."
        
        if command_exists nest; then
            local actual_nestjs_version=$(nest --version 2>/dev/null || echo "Not available")
            print_status "info" "NestJS CLI version: $actual_nestjs_version"
        else
            print_status "warning" "NestJS CLI command (nest) not found. You may need to reload your shell."
        fi
        
        # Usage tips
        echo ""
        print_status "info" "NestJS CLI usage:"
        print_status "config" "  Check version: nest --version"
        print_status "config" "  Create a new project: nest new my-app"
        print_status "config" "  Generate a resource: nest g resource users"
        print_status "config" "  Update NestJS CLI: npm update -g @nestjs/cli"
        print_status "config" "  Install specific version: npm install -g @nestjs/cli@10.4.0"
        print_status "config" "  List globally installed packages: npm list -g --depth=0"
        
    else
        print_status "error" "Failed to install NestJS CLI"
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
# GITHUB COPILOT CLI INSTALLATION
# ============================================================================

install_github_copilot_cli() {
    print_status "section" "GITHUB COPILOT CLI INSTALLATION"
    
    # Check if Node.js is installed
    if ! is_tool_installed "nodejs"; then
        print_status "error" "Node.js is not installed! GitHub Copilot CLI requires Node.js."
        echo -e "\n${YELLOW}Do you want to install Node.js first? (y/n):${NC}"
        read -r install_nodejs_first
        
        if [[ "$install_nodejs_first" =~ ^[Yy]$ ]]; then
            install_nodejs
        else
            print_status "warning" "Skipping GitHub Copilot CLI installation as Node.js is required"
            return 1
        fi
    fi
    
    # Check if npm is available
    if ! command_exists npm; then
        print_status "error" "npm is not available. Please ensure Node.js is properly installed."
        return 1
    fi
    
    # Check if GitHub Copilot CLI is already installed globally
    print_status "info" "Checking for existing GitHub Copilot CLI installation..."
    
    # Try to get Copilot CLI version with timeout
    local copilot_version=""
    if command_exists copilot; then
        copilot_version=$(timeout 10 copilot --version 2>/dev/null | head -n1 | sed 's/.*v//' || echo "")
    fi
    
    if [ -n "$copilot_version" ]; then
        print_status "info" "GitHub Copilot CLI is already installed (version: $copilot_version)"
        
        echo -e "\n${YELLOW}Do you want to update GitHub Copilot CLI to the latest version? (y/n):${NC}"
        read -r update_copilot
        if [[ ! "$update_copilot" =~ ^[Yy]$ ]]; then
            print_status "info" "Keeping existing GitHub Copilot CLI version $copilot_version"
            return 0
        fi
    fi
    
    # Ask for GitHub Copilot CLI installation
    echo -e "\n${YELLOW}Install GitHub Copilot CLI? (y/n):${NC}"
    read -r install_copilot
    
    if [[ ! "$install_copilot" =~ ^[Yy]$ ]]; then
        print_status "info" "Skipping GitHub Copilot CLI installation"
        return 0
    fi
    
    # Ask for installation method
    echo -e "\n${YELLOW}Choose installation method:${NC}"
    echo -e "${CYAN}1) npm (recommended)${NC}"
    if command_exists brew; then
        echo -e "${CYAN}2) Homebrew${NC}"
    fi
    echo -e "${CYAN}Enter 1"
    if command_exists brew; then
        echo -e "${CYAN} or 2 (default: 1):${NC}"
    else
        echo -e "${CYAN} (default: 1):${NC}"
    fi
    read -r method_choice
    
    if [ "$method_choice" = "2" ] && command_exists brew; then
        install_method="brew"
        print_status "info" "Using Homebrew for installation"
    else
        install_method="npm"
        print_status "info" "Using npm for installation"
    fi
    
    # Ask for version (stable or prerelease)
    echo -e "\n${YELLOW}Install stable or prerelease version?${NC}"
    echo -e "${CYAN}1) Stable (recommended)${NC}"
    echo -e "${CYAN}2) Prerelease${NC}"
    echo -e "${CYAN}Enter 1 or 2 (default: 1):${NC}"
    read -r version_choice
    
    local install_ok=true
    if [ "$install_method" = "brew" ]; then
        if [ "$version_choice" = "2" ]; then
            package_name="copilot-cli@prerelease"
            print_status "info" "Installing GitHub Copilot CLI prerelease version via Homebrew..."
        else
            package_name="copilot-cli"
            print_status "info" "Installing GitHub Copilot CLI stable version via Homebrew..."
        fi
        print_status "warning" "This may take a moment..."
        brew install "$package_name" 2>&1 | tee -a "$LOG_FILE" || install_ok=false
    else
        if [ "$version_choice" = "2" ]; then
            package_name="@github/copilot@prerelease"
            print_status "info" "Installing GitHub Copilot CLI prerelease version via npm..."
        else
            package_name="@github/copilot"
            print_status "info" "Installing GitHub Copilot CLI stable version via npm..."
        fi
        print_status "warning" "This may take a moment..."
        npm_install_global "$package_name" || install_ok=false
    fi

    if $install_ok; then
        # Get the installed version
        copilot_version=$(timeout 5 copilot --version 2>/dev/null | head -n1 | sed 's/.*v//' || echo "")
        
        if [ -n "$copilot_version" ]; then
            print_status "success" "GitHub Copilot CLI $copilot_version installed successfully"
        else
            print_status "success" "GitHub Copilot CLI installed successfully"
        fi
        
        # Set update command based on installation method
        if [ "$install_method" = "brew" ]; then
            update_cmd="brew upgrade $package_name"
        else
            update_cmd="npm update -g $package_name"
        fi
        
        # Verify installation
        print_status "info" "Verifying installation..."
        
        # Check copilot version
        if command_exists copilot; then
            local actual_copilot_version=$(timeout 5 copilot --version 2>/dev/null | head -n1 || echo "Not available")
            print_status "info" "GitHub Copilot CLI version: $actual_copilot_version"
        else
            print_status "warning" "GitHub Copilot CLI command not found. You may need to reload your shell."
        fi
        
        # Usage tips
        echo ""
        print_status "info" "GitHub Copilot CLI usage:"
        print_status "config" "  Launch CLI: copilot"
        print_status "config" "  Check version: copilot --version"
        print_status "config" "  Update: $update_cmd"
        print_status "config" "  Note: Requires GitHub CLI authentication for full functionality"
        print_status "config" "  Authenticate with: gh auth login"
        
    else
        print_status "error" "Failed to install GitHub Copilot CLI"
        return 1
    fi
}

# ============================================================================
# CLAUDE CODE INSTALLATION
# ============================================================================

install_claude_code() {
    print_status "section" "CLAUDE CODE INSTALLATION"

    # Check if Node.js is installed
    if ! is_tool_installed "nodejs"; then
        print_status "error" "Node.js is not installed! Claude Code requires Node.js."
        echo -e "\n${YELLOW}Do you want to install Node.js first? (y/n):${NC}"
        read -r install_nodejs_first

        if [[ "$install_nodejs_first" =~ ^[Yy]$ ]]; then
            install_nodejs
        else
            print_status "warning" "Skipping Claude Code installation as Node.js is required"
            return 1
        fi
    fi

    # Check if npm is available
    if ! command_exists npm; then
        print_status "error" "npm is not available. Please ensure Node.js is properly installed."
        return 1
    fi

    # Check if Claude is already installed globally
    print_status "info" "Checking for existing Claude Code installation..."

    local claude_version=""
    if command_exists claude; then
        claude_version=$(timeout 10 claude --version 2>/dev/null | head -n1 || echo "")
    fi

    if [ -n "$claude_version" ]; then
        print_status "info" "Claude Code is already installed ($claude_version)"

        echo -e "\n${YELLOW}Do you want to update Claude Code to the latest version? (y/n):${NC}"
        read -r update_claude
        if [[ ! "$update_claude" =~ ^[Yy]$ ]]; then
            print_status "info" "Keeping existing Claude Code installation"
            return 0
        fi
    fi

    echo -e "\n${YELLOW}Install Claude Code globally? (y/n):${NC}"
    echo -e "${CYAN}This will run: npm install -g @anthropic-ai/claude-code${NC}"
    read -r install_claude

    if [[ ! "$install_claude" =~ ^[Yy]$ ]]; then
        print_status "info" "Skipping Claude Code installation"
        return 0
    fi

    print_status "warning" "This may take a moment..."

    npm_install_global "@anthropic-ai/claude-code" || {
        print_status "error" "Failed to install Claude Code"
        return 1
    }

    print_status "success" "Claude Code package installed successfully"

    # Verify installation
    print_status "info" "Verifying Claude Code installation..."

    if command_exists claude; then
        local actual_claude_version=$(timeout 10 claude --version 2>/dev/null | head -n1 || echo "Not available")
        print_status "success" "Claude Code command is available: $actual_claude_version"
    else
        print_status "warning" "Claude command not found in PATH"
        local npm_prefix=$(npm config get prefix 2>/dev/null || echo "")
        if [ -n "$npm_prefix" ]; then
            print_status "info" "npm global prefix detected: $npm_prefix"
            print_status "config" "If needed, add to PATH: export PATH=\"$npm_prefix/bin:\$PATH\""
        fi
    fi

    # Optional login
    echo -e "\n${YELLOW}Do you want to run Claude login now? (y/n):${NC}"
    read -r run_claude_login
    if [[ "$run_claude_login" =~ ^[Yy]$ ]]; then
        print_status "info" "Starting Claude login..."
        claude login 2>&1 | tee -a "$LOG_FILE" || print_status "warning" "Claude login was not completed in this run"
    else
        print_status "info" "You can login later with: claude login"
        print_status "info" "Or set API key manually: export ANTHROPIC_API_KEY=\"your_key_here\""
    fi

    # Usage tips
    echo ""
    print_status "info" "Claude Code usage:"
    print_status "config" "  Check version: claude --version"
    print_status "config" "  Login: claude login"
    print_status "config" "  Update (current version): npm update -g @anthropic-ai/claude-code"
    print_status "config" "  Update all nvm versions: re-run this installer and choose 'all'"
    print_status "config" "  Run in project: cd /path/to/project && claude"
}

# ============================================================================
# QWEN CODE INSTALLATION
# ============================================================================

install_qwen() {
    print_status "section" "QWEN CODE INSTALLATION"

    local qwen_version=""
    if command_exists qwen; then
        qwen_version=$(timeout 10 qwen --version 2>/dev/null | head -n1 || echo "")
    fi

    if [ -n "$qwen_version" ]; then
        print_status "info" "Qwen Code is already installed ($qwen_version)"

        echo -e "\n${YELLOW}Do you want to reinstall/update Qwen Code? (y/n):${NC}"
        read -r update_qwen
        if [[ ! "$update_qwen" =~ ^[Yy]$ ]]; then
            print_status "info" "Keeping existing Qwen Code installation"
            return 0
        fi
    fi

    echo -e "\n${YELLOW}Install Qwen Code? (y/n):${NC}"
    echo -e "${CYAN}This will run the official Qwen Code installer script${NC}"
    read -r install_qwen_confirm

    if [[ ! "$install_qwen_confirm" =~ ^[Yy]$ ]]; then
        print_status "info" "Skipping Qwen Code installation"
        return 0
    fi

    if ! command_exists curl; then
        print_status "error" "curl is not available. Please install curl first."
        return 1
    fi

    print_status "info" "Downloading and running Qwen Code installer..."
    print_status "warning" "This may take a moment..."

    if bash -c "$(curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen.sh)" -s --source qwenchat 2>&1 | tee -a "$LOG_FILE"; then
        print_status "success" "Qwen Code installed successfully"

        export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

        print_status "info" "Verifying Qwen Code installation..."

        if command_exists qwen; then
            local actual_qwen_version=$(timeout 10 qwen --version 2>/dev/null | head -n1 || echo "Not available")
            print_status "success" "Qwen Code is available: $actual_qwen_version"
        else
            print_status "warning" "qwen command not found in PATH. You may need to reload your shell."
        fi

        echo ""
        print_status "info" "Qwen Code usage:"
        print_status "config" "  Check version: qwen --version"
        print_status "config" "  Run in project: cd /path/to/project && qwen"
        print_status "config" "  Update: re-run the installer script"

    else
        print_status "error" "Failed to install Qwen Code"
        return 1
    fi
}

install_blueprintx() {
    print_status "section" "BLUEPRINTX (PROJECT SCAFFOLDING)"

    if command_exists blueprintx; then
        print_status "info" "blueprintx already installed"
        return 0
    fi

    if ! command_exists git; then
        print_status "error" "git is required but not found — install git first"
        return 1
    fi

    echo -e "\n${YELLOW}Choose installation method:${NC}"
    echo -e "  ${GREEN}1)${NC} apt  (Debian/Ubuntu — adds signed repository)"
    if command_exists brew; then
        echo -e "  ${GREEN}2)${NC} Homebrew"
    fi
    echo -e "  ${GREEN}3)${NC} Git clone (any platform)"
    echo -e "  ${GREEN}4)${NC} Snap  (coming soon — not yet available)"
    echo -e "\n${CYAN}Choice:${NC} "
    read -r bpx_method

    case "$bpx_method" in
        1)
            if ! command_exists apt-get; then
                print_status "error" "apt-get not available on this system"
                return 1
            fi
            print_status "info" "Adding BlueprintX GPG key..."
            curl -fsSL https://guilhermegor.github.io/blueprintx/apt/gpg.key \
                | sudo gpg --dearmor -o /usr/share/keyrings/blueprintx.gpg 2>&1 | tee -a "$LOG_FILE"

            print_status "info" "Adding BlueprintX apt repository..."
            echo "deb [arch=all signed-by=/usr/share/keyrings/blueprintx.gpg] https://guilhermegor.github.io/blueprintx/apt stable main" \
                | sudo tee /etc/apt/sources.list.d/blueprintx.list 2>&1 | tee -a "$LOG_FILE"

            sudo apt update 2>&1 | tee -a "$LOG_FILE"

            print_status "info" "Installing blueprintx via apt..."
            if sudo apt-get install -y blueprintx 2>&1 | tee -a "$LOG_FILE"; then
                print_status "success" "blueprintx installed via apt"
            else
                print_status "error" "apt installation failed — check $LOG_FILE"
                return 1
            fi
            ;;
        2)
            if ! command_exists brew; then
                print_status "error" "Homebrew not found — install Homebrew first"
                return 1
            fi
            print_status "info" "Tapping guilhermegor/blueprintx..."
            if brew tap guilhermegor/blueprintx https://github.com/guilhermegor/blueprintx 2>&1 | tee -a "$LOG_FILE" && \
               brew install blueprintx 2>&1 | tee -a "$LOG_FILE"; then
                print_status "success" "blueprintx installed via Homebrew"
            else
                print_status "error" "Homebrew installation failed — check $LOG_FILE"
                return 1
            fi
            ;;
        3)
            local install_dir="$HOME/.local/share/blueprintx"
            local bin_dir="$HOME/.local/bin"

            print_status "info" "Cloning blueprintx to $install_dir..."
            if git clone https://github.com/guilhermegor/blueprintx.git "$install_dir" 2>&1 | tee -a "$LOG_FILE"; then
                mkdir -p "$bin_dir"
                printf '#!/usr/bin/env bash\nexec bash "%s/bin/blueprintx.sh" "$@"\n' "$install_dir" \
                    > "$bin_dir/blueprintx"
                chmod +x "$bin_dir/blueprintx"

                if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
                    print_status "warning" "$bin_dir is not in PATH — add it to your shell profile"
                    print_status "config" "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
                fi
                print_status "success" "blueprintx installed from source"
            else
                print_status "error" "git clone failed — check $LOG_FILE"
                return 1
            fi
            ;;
        4)
            print_status "warning" "Snap package for blueprintx is not yet published — check back later"
            print_status "info" "Once available: sudo snap install blueprintx"
            return 0
            ;;
        *)
            print_status "warning" "Invalid choice — aborting"
            return 1
            ;;
    esac

    if command_exists blueprintx; then
        print_status "success" "blueprintx installation verified"
    else
        print_status "warning" "blueprintx not found in PATH yet — reload your shell"
    fi

    echo ""
    print_status "info" "blueprintx commands:"
    print_status "config" "  blueprintx new        — interactive project scaffolding"
    print_status "config" "  blueprintx preview    — show available skeleton structures"
    print_status "config" "  blueprintx dry-run    — preview generated structure only"
}

# ============================================================================
# MENU AND MAIN EXECUTION
# ============================================================================

# ============================================================================
# SYNC MANAGED NPM GLOBALS TO ALL NVM VERSIONS
# ============================================================================

sync_globals_to_all_nvm_versions() {
    print_status "section" "SYNC NPM GLOBALS TO ALL NVM VERSIONS"

    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [ ! -s "$nvm_dir/nvm.sh" ]; then
        print_status "error" "nvm not found; cannot sync across versions"
        return 1
    fi

    export NVM_DIR="$nvm_dir"
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"

    local versions
    versions=$(nvm ls --no-colors 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -Vu)

    if [ -z "$versions" ]; then
        print_status "warning" "No nvm-managed Node versions found"
        return 1
    fi

    print_status "info" "nvm-managed Node versions that will be targeted:"
    while IFS= read -r ver; do
        print_status "config" "  $ver"
    done <<< "$versions"
    echo ""

    # Packages managed by this script
    local -a managed_packages=(
        "npx"
        "typescript"
        "@nestjs/cli"
        "@github/copilot"
        "@anthropic-ai/claude-code"
    )

    print_status "info" "Checking installed managed packages in active Node version..."
    local -a to_sync=()
    for pkg in "${managed_packages[@]}"; do
        if npm list -g "$pkg" --depth=0 2>/dev/null | grep -q "$pkg"; then
            print_status "success" "  $pkg — installed, will sync"
            to_sync+=("$pkg")
        else
            print_status "info" "  $pkg — not installed, skipping"
        fi
    done
    echo ""

    if [ "${#to_sync[@]}" -eq 0 ]; then
        print_status "warning" "No managed packages found in active Node version"
        return 0
    fi

    echo -e "${YELLOW}Sync the packages above to all nvm versions listed? (y/n):${NC}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "info" "Sync cancelled"
        return 0
    fi

    local -a failed_packages=()
    for pkg in "${to_sync[@]}"; do
        print_status "section" "Syncing $pkg"
        npm_global_install_all_nvm_versions "$pkg" || failed_packages+=("$pkg")
    done

    echo ""
    if [ "${#failed_packages[@]}" -gt 0 ]; then
        print_status "warning" "Failed to sync: ${failed_packages[*]}"
        return 1
    fi

    print_status "success" "All managed packages synced across nvm versions"
}

show_menu() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}               ${MAGENTA}Toolchains Installation via asdf${NC}                ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Select installation option:${NC}"
    echo -e "  ${GREEN}1)${NC} Install Node.js only"
    echo -e "  ${GREEN}2)${NC} Install Rust only"
    echo -e "  ${GREEN}3)${NC} Install TypeScript only (requires Node.js)"
    echo -e "  ${GREEN}4)${NC} Install NPX only (requires Node.js)"
    echo -e "  ${GREEN}5)${NC} Install NestJS CLI only (requires Node.js)"
    echo -e "  ${GREEN}6)${NC} Install Node.js + TypeScript"
    echo -e "  ${GREEN}7)${NC} Install Node.js + NPX"
    echo -e "  ${GREEN}8)${NC} Install Node.js + TypeScript + NPX"
    echo -e "  ${GREEN}9)${NC} Install NVM (Node Version Manager)"
    echo -e "  ${GREEN}10)${NC} Install GitHub Copilot CLI (requires Node.js)"
    echo -e "  ${GREEN}11)${NC} Install Claude Code (requires Node.js)"
    echo -e "  ${GREEN}12)${NC} Install Qwen Code"
    echo -e "  ${GREEN}13)${NC} Install BlueprintX (project scaffolding)"
    echo -e "  ${GREEN}14)${NC} Install all toolchains and tools"
    echo -e "  ${GREEN}15)${NC} Sync managed npm globals to all nvm versions"
    echo -e "  ${GREEN}16)${NC} Exit"
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
                install_typescript
                break
                ;;
            4)
                install_npx
                break
                ;;
            5)
                install_nestjs
                break
                ;;
            6)
                install_nodejs
                echo ""
                install_typescript
                break
                ;;
            7)
                install_nodejs
                echo ""
                install_npx
                break
                ;;
            8)
                install_nodejs
                echo ""
                install_typescript
                echo ""
                install_npx
                break
                ;;
            9)
                install_nvm
                break
                ;;
            10)
                install_github_copilot_cli
                break
                ;;
            11)
                install_claude_code
                break
                ;;
            12)
                install_qwen
                break
                ;;
            13)
                install_blueprintx
                break
                ;;
            14)
                install_nodejs
                echo ""
                install_typescript
                echo ""
                install_npx
                echo ""
                install_nestjs
                echo ""
                install_rust
                echo ""
                install_github_copilot_cli
                echo ""
                install_claude_code
                echo ""
                install_qwen
                echo ""
                install_blueprintx
                break
                ;;
            15)
                sync_globals_to_all_nvm_versions
                break
                ;;
            16)
                print_status "info" "Installation cancelled"
                exit 0
                ;;
            *)
                print_status "error" "Invalid option. Please select 1-16."
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
    
    # Check npx
    if command_exists npx; then
        print_status "config" "  npx: $(npx --version 2>/dev/null || echo 'Not available')"
    fi
    
    # Check TypeScript
    if command_exists tsc; then
        print_status "config" "  TypeScript: $(tsc --version 2>/dev/null | sed 's/Version //' || echo 'Not available')"
    fi

    # Check NestJS CLI
    if command_exists nest; then
        print_status "config" "  NestJS CLI: $(nest --version 2>/dev/null || echo 'Not available')"
    fi
    
    # Check rustc
    if command_exists rustc; then
        print_status "config" "  Rust: $(rustc --version 2>/dev/null || echo 'Not available')"
    fi
    
    # Check cargo
    if command_exists cargo; then
        print_status "config" "  Cargo: $(cargo --version 2>/dev/null || echo 'Not available')"
    fi
    
    # Check GitHub Copilot CLI
    if command_exists copilot; then
        print_status "config" "  GitHub Copilot CLI: $(timeout 5 copilot --version 2>/dev/null | head -n1 || echo 'Not available')"
    fi

    # Check Claude Code
    if command_exists claude; then
        print_status "config" "  Claude Code: $(timeout 5 claude --version 2>/dev/null | head -n1 || echo 'Not available')"
    fi

    # Check Qwen Code
    if command_exists qwen; then
        print_status "config" "  Qwen Code: $(timeout 5 qwen --version 2>/dev/null | head -n1 || echo 'Not available')"
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
    print_status "config" "  Update TypeScript: npm update -g typescript"
    print_status "config" "  Update NPX: npm update -g npx"
    print_status "config" "  Update GitHub Copilot CLI: npm update -g @github/copilot"
    print_status "config" "  Update Claude Code: npm update -g @anthropic-ai/claude-code"
    echo ""
}

# Execute main function
main "$@"