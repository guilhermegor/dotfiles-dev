#!/bin/bash
#
# distro_config/install_coding_lib/languages.sh
#
# Language runtimes + per-language toolchains. Sourced by install_coding.sh.
# Depends on asdf being installed (see bootstrappers.sh) and on Node.js for the
# npm-based installs (typescript, nestjs, copilot, claude_code).
#
# Contains:
#   - asdf helpers (asdf_set_*, is_tool_*, get_*)
#   - npm helpers (npm_install_global, npm_global_install_all_nvm_versions)
#   - Language installs: nodejs, nvm, npx, typescript, nestjs, rust
#   - Framework CLIs: blueprintx
#   - Cross-cutting: sync_globals_to_all_nvm_versions

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "languages.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# ============================================================================
# ASDF / TOOLCHAIN HELPERS
# ============================================================================

asdf_set_global() {
    local tool="$1"
    local version="$2"
    run_or_echo asdf set -g "$tool" "$version"
}

asdf_set_local() {
    local tool="$1"
    local version="$2"
    asdf set -l "$tool" "$version"
}

asdf_is_global_set() {
    local tool="$1"
    if [ -f "$HOME/.tool-versions" ]; then
        grep -q "^$tool " "$HOME/.tool-versions"
        return $?
    fi
    return 1
}

asdf_get_global_version() {
    local tool="$1"
    if [ -f "$HOME/.tool-versions" ]; then
        grep "^$tool " "$HOME/.tool-versions" | awk '{print $2}'
    fi
}

get_asdf_version() {
    asdf --version 2>/dev/null | head -n1 | sed 's/asdf version //' || echo "unknown"
}

check_asdf() {
    print_status "section" "CHECKING ASDF VERSION MANAGER"

    if ! command_exists asdf; then
        print_status "error" "asdf version manager is not installed!"
        print_status "info" "asdf is required to install Node.js and Rust."
        print_status "warning" "Please install asdf first using one of these methods:"
        echo ""
        print_status "config" "Method 1: Run install_coding.sh and choose 'asdf' from the menu"
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
# NPM HELPERS
# ============================================================================

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
        if run_or_echo nvm exec "${ver#v}" npm install -g "$package" 2>&1 | tee -a "$LOG_FILE"; then
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

    run_or_echo npm install -g "$package_spec" 2>&1 | tee -a "$LOG_FILE"
}

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

    local -a managed_packages=(
        "npx"
        "typescript"
        "@nestjs/cli"
        "@github/copilot"
        "@anthropic-ai/claude-code"
    )

    print_status "info" "Checking installed managed packages in active Node version..."
    local -a to_sync=()
    local pkg
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

# ============================================================================
# NODE.JS (via asdf)
# ============================================================================

install_nodejs() {
    print_status "section" "NODE.JS INSTALLATION"

    if is_tool_installed "nodejs" && is_tool_global_set "nodejs"; then
        local current_version=$(get_current_global_version "nodejs")
        print_status "info" "Node.js is already installed with version $current_version set as global"
        print_status "info" "Skipping Node.js installation as requested"
        return 0
    fi

    if ! asdf plugin list | grep -q "^nodejs$"; then
        print_status "info" "Adding Node.js plugin to asdf..."
        run_or_echo asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
        print_status "success" "Node.js plugin added"
    else
        print_status "info" "Node.js plugin already installed"
    fi

    local installed_versions=$(get_installed_versions "nodejs")
    local latest_installed=$(get_latest_installed_version "nodejs")

    if [ -n "$installed_versions" ]; then
        print_status "info" "Node.js is already installed with version(s):"
        echo "$installed_versions" | while read version; do
            print_status "config" "  - $version"
        done

        if [ -n "$latest_installed" ] && ! is_tool_global_set "nodejs"; then
            print_status "info" "Setting latest installed version ($latest_installed) as global default"

            if asdf set -g nodejs "$latest_installed" 2>/dev/null; then
                print_status "success" "Node.js $latest_installed set as global default (using 'asdf set -g')"
            elif asdf global nodejs "$latest_installed" 2>/dev/null; then
                print_status "success" "Node.js $latest_installed set as global default (using 'asdf global')"
            else
                echo "nodejs $latest_installed" > "$HOME/.tool-versions"
                print_status "success" "Node.js $latest_installed set as global default (direct write to ~/.tool-versions)"
            fi

            run_or_echo asdf reshim nodejs "$latest_installed" 2>/dev/null && print_status "info" "Shims refreshed"
            return 0
        fi

        echo -e "\n${YELLOW}Do you want to install another version? (y/n):${NC}"
        read -r install_another
        if [[ ! "$install_another" =~ ^[Yy]$ ]]; then
            print_status "info" "Skipping Node.js installation"
            return 0
        fi
    fi

    echo -e "\n${YELLOW}Enter Node.js version to install (or press Enter for latest):${NC}"
    echo -e "${CYAN}Examples: 20.11.0, 18.19.0, latest${NC}"
    read -r node_version

    if [ -z "$node_version" ]; then
        node_version="latest"
        print_status "info" "No version specified, installing latest Node.js"
    fi

    print_status "info" "Installing Node.js $node_version..."
    print_status "warning" "This may take a few minutes..."

    if asdf install nodejs "$node_version" 2>&1 | tee -a "$LOG_FILE"; then
        local installed_version=$(asdf list nodejs 2>/dev/null | tail -n1 | sed 's/^\s*\*//;s/^\s*//')

        if [ -z "$installed_version" ]; then
            installed_version=$(grep "Installed node-" "$LOG_FILE" | tail -n1 | sed 's/.*node-//;s/-.*//')
        fi

        if [ -z "$installed_version" ]; then
            installed_version="$node_version"
        fi

        print_status "success" "Node.js $installed_version installed successfully"

        print_status "info" "Setting $installed_version as global default..."

        if asdf set -g nodejs "$installed_version" 2>/dev/null; then
            print_status "success" "Node.js $installed_version set as global default (using 'asdf set -g')"
        elif asdf global nodejs "$installed_version" 2>/dev/null; then
            print_status "success" "Node.js $installed_version set as global default (using 'asdf global')"
        else
            if [ -f "$HOME/.tool-versions" ]; then
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

        run_or_echo asdf reshim nodejs "$installed_version" 2>/dev/null && print_status "info" "Shims refreshed"

        print_status "info" "Verifying installation..."
        source "$HOME/.asdf/asdf.sh" 2>/dev/null || true

        if command_exists node; then
            print_status "info" "Node.js current version: $(node --version 2>/dev/null || echo 'Not available')"
        else
            print_status "warning" "Node.js command not found. You may need to restart your shell."
        fi

        if command_exists npm; then
            print_status "info" "npm version: $(npm --version 2>/dev/null || echo 'Not available')"
        fi

        if command_exists npx; then
            print_status "info" "npx version: $(npx --version 2>/dev/null || echo 'Not available')"
        else
            print_status "info" "npx not found (it may come with newer npm versions)"
        fi

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
# NVM (alternative Node version manager)
# ============================================================================

install_nvm() {
    print_status "section" "NVM (Node Version Manager) Installation"

    if command_exists nvm || [ -d "$HOME/.nvm" ]; then
        local nvm_version=$(nvm --version 2>/dev/null || echo "unknown")
        print_status "warning" "NVM is already installed (version: $nvm_version)"

        read -r -p "Do you want to reinstall NVM? (y/n): " reinstall_nvm
        if [[ ! "$reinstall_nvm" =~ ^[Yy]$ ]]; then
            print_status "info" "Skipping NVM installation"
            return 0
        fi
    fi

    print_status "info" "Installing required dependencies..."
    local dependencies=("curl" "wget" "git")
    local dep
    for dep in "${dependencies[@]}"; do
        if ! command_exists "$dep"; then
            print_status "warning" "Installing $dep..."
            if command_exists apt-get; then
                sudo apt-get update -qq && sudo apt-get install -y "$dep" > /dev/null 2>&1
            elif command_exists yum; then
                sudo yum install -y "$dep" > /dev/null 2>&1
            elif command_exists brew; then
                run_or_echo brew install "$dep" > /dev/null 2>&1
            else
                print_status "error" "Unable to install $dep. Please install it manually."
                return 1
            fi
        fi
    done

    print_status "info" "Downloading NVM..."
    local NVM_VERSION
    NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")' || echo "v0.39.0")
    local NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"

    print_status "info" "Installing NVM ${NVM_VERSION}..."

    if curl -o- "$NVM_INSTALL_URL" 2>&1 | tee -a "$LOG_FILE" | bash; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

        print_status "success" "NVM installed successfully"

        local nvm_version=$(nvm --version 2>/dev/null || echo "")
        if [ -n "$nvm_version" ]; then
            print_status "info" "NVM version: $nvm_version"
        fi

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

        print_status "info" "Configuring shell initialization..."

        local shell_rc="$HOME/.bashrc"
        [ -f "$HOME/.zshrc" ] && shell_rc="$HOME/.zshrc"

        if [ -f "$shell_rc" ]; then
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
# NPX
# ============================================================================

install_npx() {
    print_status "section" "NPX INSTALLATION"

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

    if ! command_exists npm; then
        print_status "error" "npm is not available. Please ensure Node.js is properly installed."
        return 1
    fi

    print_status "info" "Checking for existing NPX installation..."

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

    echo -e "\n${YELLOW}Install NPX globally via npm? (y/n):${NC}"
    echo -e "${CYAN}This will install NPX via: npm install -g npx${NC}"
    echo -e "${YELLOW}Note: If you have npm 5.2+, npx should already be available${NC}"
    read -r install_npx
    if [[ ! "$install_npx" =~ ^[Yy]$ ]]; then
        print_status "info" "Skipping NPX installation"
        return 0
    fi

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
        npx_version=$(npx --version 2>/dev/null || echo "")

        if [ -n "$npx_version" ]; then
            print_status "success" "NPX $npx_version installed successfully"
        else
            print_status "success" "NPX installed successfully"
        fi

        print_status "info" "Verifying installation..."
        if command_exists npx; then
            print_status "info" "NPX version: $(npx --version 2>/dev/null || echo 'Not available')"
        else
            print_status "warning" "NPX command not found. You may need to reload your shell."
        fi

        echo ""
        print_status "info" "NPX management commands:"
        print_status "config" "  Check version: npx --version"
        print_status "config" "  Run command without installing: npx create-react-app my-app"
        print_status "config" "  Execute local binaries: npx jest"
        print_status "config" "  Update NPX: npm update -g npx"
        print_status "config" "  Install specific version: npm install -g npx@10.2.0"
        print_status "config" "  Note: NPX comes bundled with npm 5.2+"

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
# TYPESCRIPT
# ============================================================================

install_typescript() {
    print_status "section" "TYPESCRIPT INSTALLATION"

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

    if ! command_exists npm; then
        print_status "error" "npm is not available. Please ensure Node.js is properly installed."
        return 1
    fi

    print_status "info" "Checking for existing TypeScript installation..."
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

    echo -e "\n${YELLOW}Install TypeScript globally? (y/n):${NC}"
    echo -e "${CYAN}This will install TypeScript via: npm install -g typescript${NC}"
    read -r install_ts
    if [[ ! "$install_ts" =~ ^[Yy]$ ]]; then
        print_status "info" "Skipping TypeScript installation"
        return 0
    fi

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
        tsc_version=$(npm list -g typescript 2>/dev/null | grep typescript@ | head -1 | sed 's/.*typescript@//' | cut -d' ' -f1)

        if [ -n "$tsc_version" ]; then
            print_status "success" "TypeScript $tsc_version installed successfully"
        else
            print_status "success" "TypeScript installed successfully"
        fi

        print_status "info" "Verifying installation..."
        if command_exists tsc; then
            print_status "info" "TypeScript compiler version: $(tsc --version 2>/dev/null | sed 's/Version //' || echo 'Not available')"
        else
            print_status "warning" "TypeScript compiler (tsc) command not found. You may need to reload your shell."
        fi

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
# NESTJS CLI
# ============================================================================

install_nestjs() {
    print_status "section" "NESTJS CLI INSTALLATION"

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

    if ! command_exists npm; then
        print_status "error" "npm is not available. Please ensure Node.js is properly installed."
        return 1
    fi

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

    echo -e "\n${YELLOW}Install NestJS CLI globally? (y/n):${NC}"
    echo -e "${CYAN}This will install NestJS CLI via: npm install -g @nestjs/cli${NC}"
    read -r install_nestjs
    if [[ ! "$install_nestjs" =~ ^[Yy]$ ]]; then
        print_status "info" "Skipping NestJS CLI installation"
        return 0
    fi

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
        nestjs_version=$(npm list -g @nestjs/cli 2>/dev/null | grep @nestjs/cli@ | head -1 | sed 's/.*@nestjs\/cli@//' | cut -d' ' -f1)

        if [ -n "$nestjs_version" ]; then
            print_status "success" "NestJS CLI $nestjs_version installed successfully"
        else
            print_status "success" "NestJS CLI installed successfully"
        fi

        print_status "info" "Verifying installation..."
        if command_exists nest; then
            print_status "info" "NestJS CLI version: $(nest --version 2>/dev/null || echo 'Not available')"
        else
            print_status "warning" "NestJS CLI command (nest) not found. You may need to reload your shell."
        fi

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
# RUST (via asdf)
# ============================================================================

install_rust() {
    print_status "section" "RUST INSTALLATION"

    if is_tool_installed "rust" && is_tool_global_set "rust"; then
        local current_version=$(get_current_global_version "rust")
        print_status "info" "Rust is already installed with version $current_version set as global"
        print_status "info" "Skipping Rust installation as requested"
        return 0
    fi

    if ! asdf plugin list | grep -q "^rust$"; then
        print_status "info" "Adding Rust plugin to asdf..."
        run_or_echo asdf plugin add rust https://github.com/asdf-community/asdf-rust.git
        print_status "success" "Rust plugin added"
    else
        print_status "info" "Rust plugin already installed"
    fi

    local installed_versions=$(get_installed_versions "rust")
    local latest_installed=$(get_latest_installed_version "rust")

    if [ -n "$installed_versions" ]; then
        print_status "info" "Rust is already installed with version(s):"
        echo "$installed_versions" | while read version; do
            print_status "config" "  - $version"
        done

        if [ -n "$latest_installed" ] && ! is_tool_global_set "rust"; then
            print_status "info" "Setting latest installed version ($latest_installed) as global default"

            if asdf set -g rust "$latest_installed" 2>/dev/null; then
                print_status "success" "Rust $latest_installed set as global default (using 'asdf set -g')"
            elif asdf global rust "$latest_installed" 2>/dev/null; then
                print_status "success" "Rust $latest_installed set as global default (using 'asdf global')"
            else
                if [ -f "$HOME/.tool-versions" ]; then
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

            run_or_echo asdf reshim rust "$latest_installed" 2>/dev/null && print_status "info" "Shims refreshed"
            return 0
        fi

        echo -e "\n${YELLOW}Do you want to install another version? (y/n):${NC}"
        read -r install_another
        if [[ ! "$install_another" =~ ^[Yy]$ ]]; then
            print_status "info" "Skipping Rust installation"
            return 0
        fi
    fi

    echo -e "\n${YELLOW}Enter Rust version to install (or press Enter for latest):${NC}"
    echo -e "${CYAN}Examples: 1.75.0, 1.74.1, stable, nightly, latest${NC}"
    read -r rust_version

    if [ -z "$rust_version" ]; then
        rust_version="latest"
        print_status "info" "No version specified, installing latest stable Rust"
    fi

    print_status "info" "Installing Rust $rust_version..."
    print_status "warning" "This may take several minutes (Rust compiles from source)..."

    if asdf install rust "$rust_version" 2>&1 | tee -a "$LOG_FILE"; then
        local installed_version=$(asdf list rust 2>/dev/null | tail -n1 | sed 's/^\s*\*//;s/^\s*//')

        if [ -z "$installed_version" ]; then
            installed_version=$(grep -E "Installed rust-|Installed version" "$LOG_FILE" | tail -n1 | sed 's/.*rust-//;s/\s.*//')
        fi

        if [ -z "$installed_version" ]; then
            installed_version="$rust_version"
        fi

        print_status "success" "Rust $installed_version installed successfully"

        print_status "info" "Setting $installed_version as global default..."

        if asdf set -g rust "$installed_version" 2>/dev/null; then
            print_status "success" "Rust $installed_version set as global default (using 'asdf set -g')"
        elif asdf global rust "$installed_version" 2>/dev/null; then
            print_status "success" "Rust $installed_version set as global default (using 'asdf global')"
        else
            if [ -f "$HOME/.tool-versions" ]; then
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

        run_or_echo asdf reshim rust "$installed_version" 2>/dev/null && print_status "info" "Shims refreshed"

        print_status "info" "Verifying installation..."
        source "$HOME/.asdf/asdf.sh" 2>/dev/null || true

        if command_exists rustc; then
            print_status "info" "Rust current version: $(rustc --version 2>/dev/null || echo 'Not available')"
        else
            print_status "warning" "Rust command not found. You may need to restart your shell."
        fi

        if command_exists cargo; then
            print_status "info" "Cargo version: $(cargo --version 2>/dev/null || echo 'Not available')"
        fi

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
# BLUEPRINTX (project scaffolding)
# ============================================================================

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
            if run_or_echo sudo apt-get install -y blueprintx 2>&1 | tee -a "$LOG_FILE"; then
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
               run_or_echo brew install blueprintx 2>&1 | tee -a "$LOG_FILE"; then
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
                run_or_echo mkdir -p "$bin_dir"
                printf '#!/usr/bin/env bash\nexec bash "%s/bin/blueprintx.sh" "$@"\n' "$install_dir" \
                    > "$bin_dir/blueprintx"
                run_or_echo chmod +x "$bin_dir/blueprintx"

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

INSTALL_REGISTRY+=(
    "install_nodejs:Node.js (asdf)::"
    "install_nvm:NVM (Node Version Manager)::"
    "install_npx:NPX::"
    "install_typescript:TypeScript::"
    "install_nestjs:NestJS CLI::"
    "install_rust:Rust (asdf)::"
    "install_blueprintx:BlueprintX (Project Scaffolding)::"
    "sync_globals_to_all_nvm_versions:Sync npm globals to all nvm versions::"
)
