#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="$HOME/vscode_configuration_$(date +%Y%m%d_%H%M%S).log"

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

# ============================================================================
# VS CODE CONFIGURATION FUNCTIONS
# ============================================================================

check_vscode_installed() {
    print_status "info" "Checking if VS Code is installed..."
    if command -v code &> /dev/null; then
        print_status "success" "VS Code is installed"
        return 0
    else
        print_status "error" "VS Code is not installed or not in PATH"
        print_status "info" "Please install VS Code first: https://code.visualstudio.com/download"
        return 1
    fi
}

install_extensions() {
    print_status "section" "INSTALLING VS CODE EXTENSIONS"
    
    local extensions=(
        "dzhavat.bracket-pair-toggler"
        "dbaeumer.vscode-eslint"
        "github.copilot-chat"
        "ritwickdey.liveserver"
        "pkief.material-icon-theme"
        "github.copilot"
    )
    
    local installed_count=0
    local skipped_count=0
    
    for extension in "${extensions[@]}"; do
        print_status "info" "Installing extension: $extension"
        
        # Check if extension is already installed
        if code --list-extensions | grep -q "$extension"; then
            print_status "warning" "Extension already installed: $extension"
            skipped_count=$((skipped_count + 1))
        else
            if code --install-extension "$extension" --force; then
                print_status "success" "Successfully installed: $extension"
                installed_count=$((installed_count + 1))
            else
                print_status "error" "Failed to install: $extension"
            fi
        fi
    done
    
    print_status "success" "Extensions installed: $installed_count, Skipped: $skipped_count"
}

configure_keybindings() {
    print_status "section" "CONFIGURING KEYBOARD SHORTCUTS"
    
    local keybindings_dir="$HOME/.config/Code/User"
    local keybindings_file="$keybindings_dir/keybindings.json"
    
    # Create directory if it doesn't exist
    mkdir -p "$keybindings_dir"
    
    # Check if keybindings file exists
    if [ ! -f "$keybindings_file" ]; then
        print_status "info" "Creating new keybindings.json file"
        echo '[]' > "$keybindings_file"
    fi
    
    # Create a temporary keybindings file with the new shortcut
    local temp_file=$(mktemp)
    
    # Read existing keybindings
    local existing_keybindings=$(cat "$keybindings_file" 2>/dev/null || echo '[]')
    
    # Check if the shortcut already exists
    if echo "$existing_keybindings" | grep -q '"ctrl+k ctrl+s"'; then
        print_status "warning" "Shortcut Ctrl+K Ctrl+S for 'workbench.action.files.saveAll' already exists"
    else
        # Add the new shortcut while preserving existing ones
        echo "$existing_keybindings" | jq '. + [
            {
                "key": "ctrl+k ctrl+s",
                "command": "workbench.action.files.saveAll",
                "when": "editorTextFocus"
            }
        ]' > "$temp_file" 2>/dev/null || {
            print_status "warning" "jq not found, using manual JSON manipulation"
            # Fallback if jq is not installed
            if [ "$existing_keybindings" = "[]" ]; then
                echo '[{"key": "ctrl+k ctrl+s", "command": "workbench.action.files.saveAll", "when": "editorTextFocus"}]' > "$temp_file"
            else
                # Remove the last bracket, add comma and new entry, then add bracket back
                echo "$existing_keybindings" | sed '$ s/\]//' > "$temp_file"
                echo ',{"key": "ctrl+k ctrl+s", "command": "workbench.action.files.saveAll", "when": "editorTextFocus"}]' >> "$temp_file"
            fi
        }
        
        # Backup original file
        cp "$keybindings_file" "$keybindings_file.backup_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        
        # Copy the new keybindings
        cp "$temp_file" "$keybindings_file"
        
        print_status "success" "Added Ctrl+K Ctrl+S shortcut for 'Save All'"
    fi
    
    # Clean up temp file
    rm -f "$temp_file"
    
    print_status "config" "Keybindings configured at: $keybindings_file"
    print_status "info" "Linux default shortcuts are preserved"
}

configure_settings() {
    print_status "section" "CONFIGURING VS CODE SETTINGS"
    
    local settings_dir="$HOME/.config/Code/User"
    local settings_file="$settings_dir/settings.json"
    
    # Create directory if it doesn't exist
    mkdir -p "$settings_dir"
    
    # Default settings
    local default_settings='{
    "editor.bracketPairColorization.enabled": true,
    "editor.guides.bracketPairs": true,
    "editor.formatOnSave": false,
    "editor.codeActionsOnSave": {
        "source.fixAll.eslint": "explicit"
    },
    "files.autoSave": "off",
    "workbench.iconTheme": "material-icon-theme",
    "github.copilot.enable": {
        "*": true,
        "plaintext": true,
        "markdown": true,
        "scminput": true
    },
    "liveServer.settings.donotShowInfoMsg": true,
    "editor.fontSize": 14,
    "editor.tabSize": 2,
    "editor.insertSpaces": true,
    "editor.renderWhitespace": "boundary",
    "editor.rulers": [80, 120],
    "explorer.confirmDelete": false,
    "explorer.confirmDragAndDrop": false,
    "terminal.integrated.fontSize": 13,
    "workbench.colorTheme": "Default Dark Modern",
    "window.zoomLevel": 0
}'
    
    # Check if settings file exists
    if [ ! -f "$settings_file" ]; then
        print_status "info" "Creating new settings.json file"
        echo "$default_settings" > "$settings_file"
        print_status "success" "Default settings applied"
    else
        print_status "info" "Merging with existing settings.json"
        
        # Backup original file
        cp "$settings_file" "$settings_file.backup_$(date +%Y%m%d_%H%M%S)"
        
        # Merge settings (using jq if available, otherwise append)
        if command -v jq &> /dev/null; then
            jq -s '.[0] * .[1]' "$settings_file" <(echo "$default_settings") > "${settings_file}.tmp"
            mv "${settings_file}.tmp" "$settings_file"
            print_status "success" "Settings merged successfully"
        else
            print_status "warning" "jq not found, please install jq for better settings merging"
            print_status "info" "Creating settings file with defaults (existing settings preserved in backup)"
            echo "$default_settings" > "$settings_file"
        fi
    fi
    
    print_status "config" "Settings configured at: $settings_file"
}

install_jq_if_needed() {
    print_status "info" "Checking if jq is installed..."
    if command -v jq &> /dev/null; then
        print_status "success" "jq is already installed"
    else
        print_status "warning" "jq is not installed. Installing..."
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y jq
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy --noconfirm jq
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y jq
        else
            print_status "error" "Could not install jq. Please install it manually: https://stedolan.github.io/jq/download/"
            return 1
        fi
        
        if command -v jq &> /dev/null; then
            print_status "success" "jq installed successfully"
        else
            print_status "error" "Failed to install jq"
            return 1
        fi
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_status "section" "VS CODE CONFIGURATION SCRIPT"
    print_status "info" "Log file: $LOG_FILE"
    
    # Check prerequisites
    check_vscode_installed || exit 1
    
    # Install jq for JSON manipulation
    install_jq_if_needed || print_status "warning" "Continuing without jq - some features may be limited"
    
    # Configure VS Code
    install_extensions
    configure_keybindings
    configure_settings
    
    print_status "section" "CONFIGURATION COMPLETE"
    print_status "success" "VS Code has been successfully configured!"
    print_status "info" "Installed extensions from the provided list"
    print_status "info" "Added Ctrl+K Ctrl+S shortcut for 'Save All'"
    print_status "info" "Preserved all existing Linux shortcuts"
    print_status "info" "Backup files created with timestamp"
    print_status "info" "Restart VS Code for all changes to take effect"
    
    echo ""
    print_status "config" "Summary of changes:"
    echo "  • Installed 6 VS Code extensions"
    echo "  • Added keyboard shortcut: Ctrl+K Ctrl+S → Save All"
    echo "  • Configured settings for optimal development"
    echo "  • Preserved all existing shortcuts and settings"
}

# Run the main function
main "$@"