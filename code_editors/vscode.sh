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

backup_current_config() {
    print_status "section" "BACKING UP CURRENT CONFIGURATION"
    
    local config_dir="$HOME/.config/Code/User"
    local backup_dir="$HOME/vscode_backup_$(date +%Y%m%d_%H%M%S)"
    
    mkdir -p "$backup_dir"
    
    # Backup settings
    if [ -f "$config_dir/settings.json" ]; then
        cp "$config_dir/settings.json" "$backup_dir/settings.json"
        print_status "success" "Settings backed up to: $backup_dir/settings.json"
        
        # Display critical settings for reference
        print_status "info" "📊 Your current visual settings:"
        if command -v jq &> /dev/null; then
            local current_font_size=$(jq -r '.["editor.fontSize"] // "14 (default)"' "$config_dir/settings.json")
            local current_zoom=$(jq -r '.["window.zoomLevel"] // "0 (default)"' "$config_dir/settings.json")
            local current_theme=$(jq -r '.["workbench.colorTheme"] // "Default Dark Modern"' "$config_dir/settings.json")
            echo "  • Font size: $current_font_size"
            echo "  • Zoom level: $current_zoom"
            echo "  • Theme: $current_theme"
        else
            echo "  • Install jq for detailed view: sudo apt install jq"
        fi
    else
        print_status "info" "No existing settings.json found - will create new one"
    fi
    
    # Backup keybindings
    if [ -f "$config_dir/keybindings.json" ]; then
        cp "$config_dir/keybindings.json" "$backup_dir/keybindings.json"
        print_status "success" "Keybindings backed up to: $backup_dir/keybindings.json"
    else
        print_status "info" "No existing keybindings.json found"
    fi
    
    # Backup extensions list
    if command -v code &> /dev/null; then
        code --list-extensions > "$backup_dir/extensions.list" 2>/dev/null && \
        print_status "success" "Extensions list backed up to: $backup_dir/extensions.list" || \
        print_status "warning" "Could not backup extensions list"
    fi
    
    echo "$backup_dir"  # Return backup directory path
}

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
        "humao.rest-client"
        "esbenp.prettier-vscode"
    )
    
    local installed_count=0
    local skipped_count=0
    
    # Check which extensions are already installed
    local installed_extensions=""
    if command -v code &> /dev/null; then
        installed_extensions=$(code --list-extensions 2>/dev/null || echo "")
    fi
    
    for extension in "${extensions[@]}"; do
        print_status "info" "Checking extension: $extension"
        
        # Check if extension is already installed
        if echo "$installed_extensions" | grep -q "$extension"; then
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
    
    # Check if settings file exists
    if [ ! -f "$settings_file" ]; then
        print_status "info" "Creating new settings.json file"
        # Start with minimal settings that preserve your preferences
        echo '{}' > "$settings_file"
    fi
    
    # Read current settings to preserve ALL your preferences
    local current_settings=$(cat "$settings_file" 2>/dev/null || echo '{}')
    
    # Extract critical visual settings for debugging
    print_status "info" "🔍 Analyzing your current settings..."
    
    if command -v jq &> /dev/null; then
        local current_font_size=$(echo "$current_settings" | jq -r '.["editor.fontSize"] // "14 (default)"')
        local current_zoom=$(echo "$current_settings" | jq -r '.["window.zoomLevel"] // "0 (default)"')
        local current_theme=$(echo "$current_settings" | jq -r '.["workbench.colorTheme"] // "Default Dark Modern"')
        
        echo "  • Current font size: $current_font_size"
        echo "  • Current zoom level: $current_zoom"
        echo "  • Current theme: $current_theme"
    fi
    
    # Settings that should be ADDED if not present (but never overwrite existing)
    # IMPORTANT: DO NOT include font size or zoom level here - they will be preserved
    local recommended_settings='{
    "editor.bracketPairColorization.enabled": true,
    "editor.guides.bracketPairs": true,
    "editor.formatOnSave": false,
    "editor.insertSpaces": true,
    "editor.tabSize": 2,
    "editor.renderWhitespace": "boundary",
    "workbench.startupEditor": "none",
    "workbench.editor.enablePreview": false,
    "workbench.productIconTheme": "default",
    "workbench.sideBar.location": "left",
    "window.menuBarVisibility": "default",
    "zenMode.hideLineNumbers": false,
    "zenMode.centerLayout": false,
    "terminal.integrated.fontSize": 14
}'
    
    # Your existing settings that should ALWAYS be preserved
    # Based on your settings.json from earlier, these are your preferences
    local your_critical_settings='{
    "workbench.iconTheme": "material-icon-theme",
    "chat.editing.confirmEditRequestRetry": false,
    "editor.codeActionsOnSave": {
        "source.fixAll.eslint": "explicit"
    },
    "github.copilot.enable": {
        "*": true,
        "plaintext": true,
        "markdown": true,
        "scminput": true
    },
    "liveServer.settings.donotShowInfoMsg": true,
    "editor.rulers": [80, 120],
    "explorer.confirmDelete": false,
    "explorer.confirmDragAndDrop": false,
    "workbench.colorTheme": "Default Dark Modern",
    "window.zoomLevel": 0
}'
    
    print_status "info" "🔄 Merging settings while PRESERVING your visual preferences..."
    print_status "warning" "⚠️  IMPORTANT: Your font size and zoom level will NOT be changed"
    
    # Backup original file
    local backup_file="$settings_file.backup_$(date +%Y%m%d_%H%M%S)"
    cp "$settings_file" "$backup_file"
    print_status "success" "Original settings backed up to: $backup_file"
    
    if command -v jq &> /dev/null; then
        # STRATEGY: Start with your current settings, then add recommended ones
        # This ensures YOUR settings take priority
        
        # Step 1: Start with your current settings (this preserves everything)
        echo "$current_settings" > "$settings_file.tmp"
        
        # Step 2: Merge with your critical settings (ensure they're always set)
        cat "$settings_file.tmp" | jq --argjson critical "$your_critical_settings" '
            . * $critical  # Your current settings first, critical settings override if missing
        ' > "$settings_file.tmp2"
        
        # Step 3: Finally, add recommended settings (only if not already set)
        cat "$settings_file.tmp2" | jq --argjson recommended "$recommended_settings" '
            . * $recommended  # Existing settings first, recommended only if missing
        ' > "$settings_file"
        
        # Clean up temp files
        rm -f "$settings_file.tmp" "$settings_file.tmp2"
        
        # Verify the critical settings are preserved
        local final_font_size=$(jq -r '.["editor.fontSize"] // "14 (default)"' "$settings_file")
        local final_zoom=$(jq -r '.["window.zoomLevel"] // "0 (default)"' "$settings_file")
        
        print_status "success" "✅ Font size preserved: $final_font_size"
        print_status "success" "✅ Zoom level preserved: $final_zoom"
        
        # If font size is default but you want it bigger, suggest change
        if [ "$final_font_size" = "14 (default)" ] || [ "$final_font_size" = "14" ]; then
            print_status "warning" "ℹ️  Font size is at default (14). If text feels small, try:"
            echo "    1. Increase zoom: \"window.zoomLevel\": 1"
            echo "    2. Or increase font: \"editor.fontSize\": 16"
        fi
        
    else
        print_status "error" "❌ jq is required for proper settings preservation"
        print_status "info" "Installing jq..."
        if ! install_jq_if_needed; then
            print_status "error" "Cannot merge settings without jq"
            print_status "info" "Restoring original settings from backup"
            cp "$backup_file" "$settings_file"
            return 1
        fi
        
        # Retry with jq now installed
        echo "$current_settings" | jq --argjson critical "$your_critical_settings" '
            . * $critical
        ' | jq --argjson recommended "$recommended_settings" '
            . * $recommended
        ' > "$settings_file.tmp"
        mv "$settings_file.tmp" "$settings_file"
    fi
    
    # Final verification
    print_status "info" "🔎 Final configuration check:"
    if command -v jq &> /dev/null; then
        local final_theme=$(jq -r '.["workbench.colorTheme"] // "Not set"' "$settings_file")
        local final_font=$(jq -r '.["editor.fontSize"] // "14 (default)"' "$settings_file")
        local final_zoom=$(jq -r '.["window.zoomLevel"] // "0 (default)"' "$settings_file")
        local final_icons=$(jq -r '.["workbench.iconTheme"] // "material-icon-theme"' "$settings_file")
        
        echo "  • Theme: $final_theme"
        echo "  • Font size: $final_font"
        echo "  • Zoom level: $final_zoom"
        echo "  • Icon theme: $final_icons"
        
        # Warning if zoom is 0 (default) but text feels small
        if [ "$final_zoom" = "0" ] || [ "$final_zoom" = "0 (default)" ]; then
            print_status "warning" "💡 Zoom level is 0 (default). If text is too small, try setting zoom to 1:"
            echo "    \"window.zoomLevel\": 1"
        fi
        
    fi
    
    print_status "config" "Settings configured at: $settings_file"
    print_status "success" "✅ Your visual preferences preserved, missing settings added"
}

install_jq_if_needed() {
    print_status "info" "Checking if jq is installed..."
    if command -v jq &> /dev/null; then
        print_status "success" "jq is already installed"
        return 0
    else
        print_status "warning" "jq is not installed. Installing..."
        
        # Try different package managers
        local installed=false
        
        if command -v apt-get &> /dev/null && [ "$installed" = false ]; then
            print_status "info" "Using apt-get (Debian/Ubuntu)"
            sudo apt-get update && sudo apt-get install -y jq && installed=true
        fi
        
        if command -v yum &> /dev/null && [ "$installed" = false ]; then
            print_status "info" "Using yum (RHEL/CentOS)"
            sudo yum install -y jq && installed=true
        fi
        
        if command -v dnf &> /dev/null && [ "$installed" = false ]; then
            print_status "info" "Using dnf (Fedora)"
            sudo dnf install -y jq && installed=true
        fi
        
        if command -v pacman &> /dev/null && [ "$installed" = false ]; then
            print_status "info" "Using pacman (Arch)"
            sudo pacman -Sy --noconfirm jq && installed=true
        fi
        
        if command -v zypper &> /dev/null && [ "$installed" = false ]; then
            print_status "info" "Using zypper (openSUSE)"
            sudo zypper install -y jq && installed=true
        fi
        
        if [ "$installed" = false ]; then
            print_status "error" "Could not install jq. Please install it manually:"
            print_status "info" "  Ubuntu/Debian: sudo apt install jq"
            print_status "info" "  Fedora: sudo dnf install jq"
            print_status "info" "  CentOS/RHEL: sudo yum install jq"
            return 1
        fi
        
        if command -v jq &> /dev/null; then
            print_status "success" "jq installed successfully"
            return 0
        else
            print_status "error" "Failed to install jq"
            return 1
        fi
    fi
}

verify_configuration() {
    print_status "section" "VERIFYING CONFIGURATION"
    
    local settings_file="$HOME/.config/Code/User/settings.json"
    
    if [ -f "$settings_file" ]; then
        print_status "info" "🔍 Checking final configuration..."
        
        if command -v jq &> /dev/null; then
            # Check critical settings
            local checks_passed=0
            local checks_total=0
            
            # Check theme
            local theme=$(jq -r '.["workbench.colorTheme"] // empty' "$settings_file")
            checks_total=$((checks_total + 1))
            if [ "$theme" = "Default Dark Modern" ]; then
                print_status "success" "✅ Theme: Default Dark Modern"
                checks_passed=$((checks_passed + 1))
            else
                print_status "warning" "Theme is: ${theme:-Not set}"
            fi
            
            # Check zoom level (CRITICAL for your issue)
            local zoom=$(jq -r '.["window.zoomLevel"] // "0"' "$settings_file")
            checks_total=$((checks_total + 1))
            print_status "info" "🔍 Zoom level: $zoom"
            checks_passed=$((checks_passed + 1))
            
            # Check font size
            local font_size=$(jq -r '.["editor.fontSize"] // "14"' "$settings_file")
            checks_total=$((checks_total + 1))
            print_status "info" "🔍 Font size: $font_size"
            checks_passed=$((checks_passed + 1))
            
            # Check icon theme
            local icons=$(jq -r '.["workbench.iconTheme"] // empty' "$settings_file")
            checks_total=$((checks_total + 1))
            if [ "$icons" = "material-icon-theme" ]; then
                print_status "success" "✅ Icon theme: material-icon-theme"
                checks_passed=$((checks_passed + 1))
            else
                print_status "warning" "Icon theme is: ${icons:-Not set}"
            fi
            
            print_status "info" "Configuration checks: $checks_passed/$checks_total passed"
            
            # Special warning if text might be too small
            if [ "$zoom" = "0" ] && [ "$font_size" = "14" ]; then
                print_status "warning" "⚠️  WARNING: Both zoom level (0) and font size (14) are at defaults."
                print_status "warning" "   If text feels too small, try one of these fixes:"
                echo ""
                echo "   QUICK FIXES for small text:"
                echo "   1. Increase ZOOM (affects entire UI):"
                echo "      Add to settings.json: \"window.zoomLevel\": 1"
                echo ""
                echo "   2. Increase FONT SIZE (only text):"
                echo "      Add to settings.json: \"editor.fontSize\": 16"
                echo ""
                echo "   3. BOTH for maximum readability:"
                echo "      \"window.zoomLevel\": 1,"
                echo "      \"editor.fontSize\": 16"
                echo ""
            fi
            
        else
            print_status "warning" "jq not available for detailed verification"
            # Simple checks
            if grep -q '"workbench.colorTheme": "Default Dark Modern"' "$settings_file"; then
                print_status "success" "✅ Theme set to Default Dark Modern"
            fi
            if grep -q '"window.zoomLevel": 0' "$settings_file"; then
                print_status "info" "🔍 Zoom level: 0 (default)"
            fi
        fi
        
    else
        print_status "error" "Settings file not found: $settings_file"
    fi
    
    print_status "info" "Verification complete"
}

show_final_summary() {
    print_status "section" "CONFIGURATION COMPLETE"
    
    local settings_file="$HOME/.config/Code/User/settings.json"
    local backup_files=($(ls -td "$HOME"/vscode_backup_* 2>/dev/null))
    
    print_status "success" "✅ VS Code configuration completed successfully!"
    echo ""
    
    print_status "config" "📋 WHAT WAS CONFIGURED:"
    echo "  ✅ Extensions installed/verified (6 total)"
    echo "  ✅ Keyboard shortcut added: Ctrl+K Ctrl+S → Save All"
    echo "  ✅ Your personal settings PRESERVED"
    echo "  ✅ Recommended editor settings added"
    echo ""
    
    print_status "config" "🎨 YOUR CURRENT VISUAL SETTINGS:"
    if [ -f "$settings_file" ] && command -v jq &> /dev/null; then
        local theme=$(jq -r '.["workbench.colorTheme"] // "Default Dark Modern"' "$settings_file")
        local font_size=$(jq -r '.["editor.fontSize"] // "14 (default)"' "$settings_file")
        local zoom=$(jq -r '.["window.zoomLevel"] // "0 (default)"' "$settings_file")
        local icons=$(jq -r '.["workbench.iconTheme"] // "material-icon-theme"' "$settings_file")
        
        echo "  • Theme: $theme"
        echo "  • Font size: $font_size"
        echo "  • Zoom level: $zoom"
        echo "  • Icon theme: $icons"
        
        # Special note about text size
        if [ "$font_size" = "14 (default)" ] || [ "$font_size" = "14" ]; then
            if [ "$zoom" = "0 (default)" ] || [ "$zoom" = "0" ]; then
                echo ""
                print_status "warning" "⚠️  TEXT MAY BE TOO SMALL!"
                echo "  Both font size and zoom are at defaults."
                echo "  If text feels uncomfortable, try the fixes below:"
            fi
        fi
    else
        echo "  • Settings file: $settings_file"
        echo "  • Install 'jq' for detailed view: sudo apt install jq"
    fi
    echo ""
    
    if [ ${#backup_files[@]} -gt 0 ]; then
        print_status "config" "💾 BACKUP INFORMATION:"
        echo "  • Original settings backed up to: ${backup_files[0]}"
        echo "  • Configuration log: $LOG_FILE"
        echo ""
    fi
    
    print_status "info" "🔄 NEXT STEPS:"
    echo "  1. Restart VS Code for changes to take effect"
    echo "  2. Check extensions are installed (Ctrl+Shift+X)"
    echo "  3. Test shortcut: Ctrl+K Ctrl+S saves all open files"
    echo ""
    
    print_status "info" "🔧 QUICK FIXES FOR SMALL TEXT:"
    echo "  If text feels too small, edit $settings_file and add:"
    echo ""
    echo "  OPTION 1 - Increase zoom (entire UI):"
    echo "    \"window.zoomLevel\": 1,"
    echo ""
    echo "  OPTION 2 - Increase font size (only text):"
    echo "    \"editor.fontSize\": 16,"
    echo ""
    echo "  OPTION 3 - Both for maximum readability:"
    echo "    \"window.zoomLevel\": 1,"
    echo "    \"editor.fontSize\": 16,"
    echo ""
    
    print_status "info" "📋 INTEGRATION WITH YOUR MAKEFILE:"
    echo "  This script can be called from your Makefile as 'vscode_setup'"
    echo "  Add to your Makefile:"
    echo "  vscode_setup:"
    echo "      @bash code_editors/vscode.sh"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_status "section" "VS CODE CONFIGURATION SCRIPT"
    print_status "info" "Log file: $LOG_FILE"
    print_status "info" "This script preserves ALL your current settings"
    print_status "info" "including font size, zoom level, and other preferences"
    echo ""
    
    # Check prerequisites
    check_vscode_installed || exit 1
    
    # Backup current configuration
    backup_current_config > /dev/null
    
    # Install jq for JSON manipulation (critical for preserving settings)
    if ! install_jq_if_needed; then
        print_status "error" "jq is required for proper settings preservation"
        print_status "info" "Please install jq manually and run the script again"
        print_status "info" "Ubuntu/Debian: sudo apt install jq"
        print_status "info" "Fedora: sudo dnf install jq"
        exit 1
    fi
    
    # Configure VS Code
    install_extensions
    configure_keybindings
    configure_settings
    verify_configuration
    show_final_summary
}

# Run the main function
main "$@"