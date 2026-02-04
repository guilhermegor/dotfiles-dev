#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="$HOME/vscode_undo_$(date +%Y%m%d_%H%M%S).log"

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
# UNDO FUNCTIONS
# ============================================================================

restore_backup() {
    print_status "section" "RESTORING VS CODE SETTINGS"
    
    local vscode_settings="$HOME/.config/Code/User/settings.json"
    local backup_pattern="${vscode_settings}.backup_*"
    
    # Find the most recent backup
    local latest_backup=$(ls -t $backup_pattern 2>/dev/null | head -1)
    
    if [ -n "$latest_backup" ]; then
        print_status "info" "Found backup: $latest_backup"
        
        # Create a safety backup of current settings
        if [ -f "$vscode_settings" ]; then
            local safety_backup="${vscode_settings}.current_$(date +%Y%m%d_%H%M%S)"
            cp "$vscode_settings" "$safety_backup"
            print_status "info" "Created safety backup of current settings: $safety_backup"
        fi
        
        # Restore from backup
        cp "$latest_backup" "$vscode_settings"
        print_status "success" "Restored original settings from backup"
        
        # Show backup timestamp
        local backup_time=$(stat -c %y "$latest_backup" 2>/dev/null || echo "unknown")
        print_status "config" "Backup created on: $backup_time"
        
        return 0
    else
        print_status "warning" "No backup files found matching: $backup_pattern"
        return 1
    fi
}

list_backups() {
    print_status "section" "AVAILABLE BACKUPS"
    
    local vscode_settings="$HOME/.config/Code/User/settings.json"
    local backup_pattern="${vscode_settings}.backup_*"
    
    local backups=$(ls -t $backup_pattern 2>/dev/null)
    
    if [ -n "$backups" ]; then
        print_status "info" "Found backup files:"
        echo ""
        
        local count=1
        for backup in $backups; do
            local timestamp=$(echo "$backup" | grep -oE 'backup_[0-9]{8}_[0-9]{6}' | sed 's/backup_//')
            local formatted_time=$(echo "$timestamp" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
            
            if [ -n "$formatted_time" ]; then
                echo "  $count. $formatted_time"
            else
                echo "  $count. $(basename "$backup")"
            fi
            count=$((count + 1))
        done
        echo ""
        
        return 0
    else
        print_status "warning" "No backup files found"
        return 1
    fi
}

restore_default_settings() {
    print_status "section" "RESETTING TO DEFAULT SETTINGS"
    
    local vscode_settings="$HOME/.config/Code/User/settings.json"
    
    if [ -f "$vscode_settings" ]; then
        # Create a backup before resetting
        local backup_file="${vscode_settings}.before_reset_$(date +%Y%m%d_%H%M%S)"
        cp "$vscode_settings" "$backup_file"
        print_status "info" "Created backup before reset: $backup_file"
        
        # Remove specific comfort settings by creating a minimal file
        # or remove the entire settings file to let VS Code recreate defaults
        print_status "info" "Resetting VS Code settings to default..."
        
        # Option 1: Create minimal settings (safer, preserves some user config)
        cat > "$vscode_settings" << 'EOF'
{
  // Minimal default settings
  "window.zoomLevel": 0
}
EOF
        
        print_status "success" "Reset to minimal default settings"
        print_status "info" "VS Code will use its internal defaults for other settings"
        
        return 0
    else
        print_status "warning" "No settings file found to reset"
        return 1
    fi
}

remove_font_settings_only() {
    print_status "section" "REMOVING ONLY FONT SETTINGS"
    
    local vscode_settings="$HOME/.config/Code/User/settings.json"
    
    if [ ! -f "$vscode_settings" ]; then
        print_status "error" "Settings file not found: $vscode_settings"
        return 1
    fi
    
    # Create backup
    local backup_file="${vscode_settings}.before_font_removal_$(date +%Y%m%d_%H%M%S)"
    cp "$vscode_settings" "$backup_file"
    print_status "info" "Created backup: $backup_file"
    
    # Check if jq is available for JSON manipulation
    if command -v jq &> /dev/null; then
        print_status "info" "Using jq to remove font settings..."
        
        # Remove specific font-related settings
        jq 'del(
          ."editor.fontSize",
          ."terminal.integrated.fontSize",
          ."debug.console.fontSize",
          ."editor.fontFamily",
          ."editor.lineHeight",
          ."editor.letterSpacing",
          ."editor.tabSize",
          ."editor.insertSpaces",
          ."editor.detectIndentation",
          ."editor.lineNumbers",
          ."editor.minimap.enabled",
          ."editor.cursorBlinking",
          ."editor.cursorWidth",
          ."editor.bracketPairColorization.enabled",
          ."editor.guides.bracketPairs",
          ."editor.matchBrackets",
          ."editor.renderWhitespace",
          ."editor.renderControlCharacters",
          ."editor.formatOnSave",
          ."editor.formatOnPaste",
          ."editor.suggestSelection",
          ."editor.quickSuggestions",
          ."terminal.integrated.fontFamily",
          ."terminal.integrated.lineHeight",
          ."terminal.integrated.cursorBlinking",
          ."files.autoSave",
          ."files.autoSaveDelay",
          ."explorer.compactFolders",
          ."git.autofetch"
        )' "$vscode_settings" > "${vscode_settings}.tmp"
        
        mv "${vscode_settings}.tmp" "$vscode_settings"
        print_status "success" "Font settings removed while keeping other configurations"
        
    else
        print_status "warning" "jq not installed. Creating minimal settings file instead..."
        # Fallback: create minimal settings
        cat > "$vscode_settings" << 'EOF'
{
  // Minimal settings after font removal
  "window.zoomLevel": 0,
  "workbench.colorTheme": "Default Dark Modern",
  "workbench.iconTheme": "material-icon-theme"
}
EOF
        print_status "info" "Created minimal settings file"
    fi
    
    return 0
}

show_current_font_settings() {
    print_status "section" "CURRENT FONT SETTINGS"
    
    local vscode_settings="$HOME/.config/Code/User/settings.json"
    
    if [ -f "$vscode_settings" ]; then
        print_status "info" "Current font settings in VS Code:"
        echo ""
        
        if command -v jq &> /dev/null; then
            jq '{
                editorFontSize: ."editor.fontSize",
                terminalFontSize: ."terminal.integrated.fontSize",
                editorFontFamily: ."editor.fontFamily",
                editorLineHeight: ."editor.lineHeight",
                editorTabSize: ."editor.tabSize",
                windowZoomLevel: ."window.zoomLevel"
            }' "$vscode_settings" 2>/dev/null || echo "  Unable to parse JSON or no font settings found"
        else
            grep -E '(fontSize|fontFamily|lineHeight|tabSize|zoomLevel)' "$vscode_settings" 2>/dev/null || echo "  No font settings found in file"
        fi
    else
        print_status "warning" "No settings file found at: $vscode_settings"
    fi
    
    echo ""
}

display_manual_reset_instructions() {
    print_status "section" "MANUAL RESET INSTRUCTIONS"
    
    print_status "info" "If automatic methods don't work, you can manually reset VS Code:"
    echo ""
    print_status "config" "Option 1: Delete settings file"
    echo "  rm ~/.config/Code/User/settings.json"
    echo "  # VS Code will recreate with defaults on next launch"
    echo ""
    print_status "config" "Option 2: Reset through VS Code UI"
    echo "  1. Open VS Code"
    echo "  2. Press Ctrl+Shift+P (Cmd+Shift+P on Mac)"
    echo "  3. Type 'Preferences: Open Settings (JSON)'"
    echo "  4. Delete the contents and save"
    echo ""
    print_status "config" "Option 3: Keyboard shortcuts to adjust font size"
    echo "  • Reset zoom: Ctrl+0 (Cmd+0 on Mac)"
    echo "  • Decrease font: Ctrl+- (Cmd+- on Mac)"
    echo "  • Increase font: Ctrl+= (Cmd+= on Mac)"
    echo ""
    print_status "warning" "⚠️  Warning: Deleting settings will remove ALL customizations"
}

display_undo_summary() {
    print_status "section" "UNDO COMPLETE"
    
    print_status "success" "VS Code comfort settings have been removed!"
    echo ""
    print_status "info" "Next steps:"
    echo "  1. Restart VS Code for changes to take effect"
    echo "  2. VS Code will use default font sizes"
    echo "  3. Default font is usually 'Consolas' or 'Monaco'"
    echo "  4. Default font size is usually 12-14px"
    echo ""
    print_status "config" "To manually adjust font size in VS Code:"
    echo "  • Open Command Palette: Ctrl+Shift+P"
    echo "  • Search for 'Preferences: Open Settings (UI)'"
    echo "  • Search for 'font size'"
    echo "  • Adjust 'Editor: Font Size' as desired"
    echo ""
    print_status "info" "Log file: $LOG_FILE"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_status "section" "VS CODE COMFORT SETTINGS UNDO SCRIPT"
    print_status "info" "This script will undo the comfort settings changes"
    print_status "info" "Log file: $LOG_FILE"
    echo ""
    
    # Show current settings before changes
    show_current_font_settings
    
    # List available backups
    if list_backups; then
        echo ""
        read -p "$(echo -e ${YELLOW}Do you want to restore from backup? [Y/n]: ${NC})" -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            print_status "info" "Skipping backup restore"
        else
            restore_backup
        fi
    else
        print_status "info" "No backups found, trying other methods..."
    fi
    
    # If no backup restored, offer other options
    echo ""
    print_status "config" "Select undo method:"
    echo "  1. Remove only font settings (keep other configurations)"
    echo "  2. Reset to minimal default settings"
    echo "  3. Show manual instructions only"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Enter choice [1-3]: ${NC})" -n 1 choice
    echo ""
    
    case $choice in
        1)
            remove_font_settings_only
            ;;
        2)
            restore_default_settings
            ;;
        3)
            display_manual_reset_instructions
            exit 0
            ;;
        *)
            print_status "warning" "Invalid choice. Using method 1 (remove font settings only)."
            remove_font_settings_only
            ;;
    esac
    
    # Show settings after changes
    echo ""
    show_current_font_settings
    
    # Display manual instructions as reference
    display_manual_reset_instructions
    
    # Display summary
    display_undo_summary
}

# Run the main function
main "$@"