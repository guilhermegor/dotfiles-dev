#!/bin/bash

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# --- Global Variables ---
SCRIPT_DIR="$HOME/bin"
WORKSPACE_SCRIPTS=("next_workspace.sh" "prev_workspace.sh")
XBINDKEYS_CONFIG="$HOME/.xbindkeysrc"
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/xbindkeys.desktop"

# --- Helper Functions ---

# Print status messages with color coding
print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success") echo -e "${GREEN}[✓]${NC} ${message}" ;;
        "error") echo -e "${RED}[✗]${NC} ${message}" >&2 ;;
        "warning") echo -e "${YELLOW}[!]${NC} ${message}" ;;
        "info") echo -e "${BLUE}[i]${NC} ${message}" ;;
        "config") echo -e "${CYAN}[→]${NC} ${message}" ;;
        *) echo -e "[ ] ${message}" ;;
    esac
}

# Create backup of existing files with timestamp
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.bak-$(date +%Y%m%d%H%M%S)"
        if cp "$file" "$backup"; then
            print_status "success" "Backed up ${file} to ${backup}"
        else
            print_status "error" "Failed to backup ${file}"
            return 1
        fi
    else
        print_status "info" "No existing ${file} to backup"
    fi
}

# Check if command is available
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- Core Functions ---

# Install required dependencies
install_dependencies() {
    print_status "config" "Checking/installing dependencies..."
    
    local packages=("xdotool" "xbindkeys")
    local missing_packages=()
    
    # Check which packages are missing
    for pkg in "${packages[@]}"; do
        if ! command_exists "$pkg"; then
            missing_packages+=("$pkg")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        sudo apt update && sudo apt install -y "${missing_packages[@]}" || {
            print_status "error" "Failed to install dependencies"
            return 1
        }
        print_status "success" "Dependencies installed successfully"
    else
        print_status "info" "All dependencies already installed"
    fi
}

# Configure natural scrolling
configure_natural_scrolling() {
    print_status "config" "Configuring natural scrolling..."
    gsettings set org.gnome.desktop.peripherals.mouse natural-scroll true
    print_status "success" "Mouse scroll direction changed to natural"
}

# Create workspace switching scripts
create_workspace_scripts() {
    print_status "config" "Creating workspace switching scripts..."
    
    # Create script directory if it doesn't exist
    mkdir -p "$SCRIPT_DIR" || {
        print_status "error" "Failed to create ${SCRIPT_DIR}"
        return 1
    }
    
    # Next workspace script
    cat > "$SCRIPT_DIR/${WORKSPACE_SCRIPTS[0]}" << 'EOF'
#!/bin/bash
xdotool key Ctrl+Alt+Right
EOF
    
    # Previous workspace script
    cat > "$SCRIPT_DIR/${WORKSPACE_SCRIPTS[1]}" << 'EOF'
#!/bin/bash
xdotool key Ctrl+Alt+Left
EOF
    
    # Make scripts executable
    chmod +x "$SCRIPT_DIR"/*.sh || {
        print_status "error" "Failed to make scripts executable"
        return 1
    }
    
    print_status "success" "Workspace switching scripts created"
}

# Configure xbindkeys
configure_xbindkeys() {
    print_status "config" "Configuring xbindkeys..."
    
    backup_file "$XBINDKEYS_CONFIG" || return 1
    
    cat > "$XBINDKEYS_CONFIG" << EOF
"$SCRIPT_DIR/${WORKSPACE_SCRIPTS[0]}"
  b:9

"$SCRIPT_DIR/${WORKSPACE_SCRIPTS[1]}"
  b:8
EOF
    
    print_status "success" "xbindkeys configuration created"
}

# Set up autostart
setup_autostart() {
    print_status "config" "Setting up autostart..."
    
    mkdir -p "$AUTOSTART_DIR" || {
        print_status "error" "Failed to create autostart directory"
        return 1
    }
    
    backup_file "$AUTOSTART_FILE" || return 1
    
    cat > "$AUTOSTART_FILE" << EOF
[Desktop Entry]
Name=XBindKeys
Exec=xbindkeys
Type=Application
EOF
    
    print_status "success" "Autostart configuration created"
}

# Restart xbindkeys service
restart_xbindkeys() {
    print_status "config" "Restarting xbindkeys..."
    
    # Kill existing xbindkeys process if running
    if pgrep xbindkeys >/dev/null; then
        pkill xbindkeys && print_status "info" "Stopped existing xbindkeys process"
    fi
    
    # Start new xbindkeys process
    xbindkeys || {
        print_status "error" "Failed to start xbindkeys"
        return 1
    }
    
    print_status "success" "xbindkeys started successfully"
}

# Verify installation
verify_installation() {
    print_status "info" "Verifying installation..."
    
    local verification_passed=true
    
    # Check if scripts exist and are executable
    for script in "${WORKSPACE_SCRIPTS[@]}"; do
        if [ ! -x "$SCRIPT_DIR/$script" ]; then
            print_status "error" "Script $script is missing or not executable"
            verification_passed=false
        fi
    done
    
    # Check if xbindkeys is running
    if ! pgrep xbindkeys >/dev/null; then
        print_status "error" "xbindkeys is not running"
        verification_passed=false
    fi
    
    if $verification_passed; then
        print_status "success" "Verification complete - everything looks good!"
    else
        print_status "warning" "Verification completed with some issues"
        return 1
    fi
}

# Display final instructions
display_summary() {
    echo -e "\n${MAGENTA}Configuration Summary:${NC}"
    echo -e "  • ${CYAN}Button 9${NC} (Forward) → Next workspace"
    echo -e "  • ${CYAN}Button 8${NC} (Back) → Previous workspace"
    echo -e "  • Natural scrolling enabled (macOS-style)"
    echo -e "\n${YELLOW}Note:${NC} Changes should take effect immediately."
    echo -e "If buttons don't work, try logging out and back in."
}

# --- Main Execution ---
main() {
    print_status "info" "Starting MX Master Configuration"
    
    # Execute all configuration steps in order
    configure_natural_scrolling || exit 1
    install_dependencies || exit 1
    create_workspace_scripts || exit 1
    configure_xbindkeys || exit 1
    setup_autostart || exit 1
    restart_xbindkeys || exit 1
    verify_installation || exit 1
    
    print_status "success" "Configuration completed successfully!"
    display_summary
}

# Run the main function
main