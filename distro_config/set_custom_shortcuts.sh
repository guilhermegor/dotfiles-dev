#!/bin/bash

# colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # no color

# function to print colored text
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# function to check if a keybinding already exists
keybinding_exists() {
    local binding="$1"
    
    # check in custom keybindings
    local custom_bindings=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)
    for i in $(seq 0 $(($(echo "$custom_bindings" | grep -o "custom" | wc -l)-1))); do
        existing_binding=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${i}/ binding 2>/dev/null)
        if [ "$existing_binding" = "'$binding'" ]; then
            echo "Conflict found in custom keybinding $i: $existing_binding"
            return 0
        fi
    done
    
    # check in default keybindings
    local default_bindings=$(gsettings list-recursively org.gnome.settings-daemon.plugins.media-keys | grep -v "custom-keybindings")
    while read -r line; do
        if [[ "$line" == *"'$binding'"* ]]; then
            echo "Conflict found in default keybinding: $line"
            return 0
        fi
    done <<< "$default_bindings"
    
    return 1
}

# function to verify keybindings
verify_keybindings() {
    local bindings=("$@")
    local conflict_found=0
    
    print_status $BLUE "Verifying keybindings for conflicts..."
    
    for binding in "${bindings[@]}"; do
        if keybinding_exists "$binding"; then
            print_status $RED "Conflict detected! The keybinding '$binding' is already in use."
            conflict_found=1
        else
            print_status $GREEN "Keybinding '$binding' is available."
        fi
    done
    
    if [ $conflict_found -eq 1 ]; then
        print_status $RED "\nWarning: One or more keybinding conflicts detected!"
        read -p "Do you want to continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status $RED "Aborting due to keybinding conflicts."
            exit 1
        fi
    else
        print_status $GREEN "\nAll keybindings are available. No conflicts detected."
    fi
}

# function to set the custom keybindings array
set_keybindings_array() {
    print_status $BLUE "Setting up custom keybindings array..."
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
    "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/', \
    '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/']"
}

# function to set individual keybindings
set_individual_keybinding() {
    local index="$1"
    local name="$2"
    local command="$3"
    local binding="$4"
    
    print_status $YELLOW "Setting up keybinding $index: $name..."
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${index}/ name "$name"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${index}/ command "$command"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${index}/ binding "$binding"
}

# function to create the copy-path script
create_copy_path_script() {
    local script_path="$HOME/.local/bin/copy-path.sh"
    local nautilus_scripts_dir="$HOME/.local/share/nautilus/scripts"
    local symlink_path="$nautilus_scripts_dir/Copy Path"

    print_status $BLUE "Creating enhanced copy-path script at $script_path..."
    
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$nautilus_scripts_dir"
    
    cat > "$script_path" << 'EOF'
#!/bin/bash

# Enhanced file path copier with paste support
# Can be called from Nautilus or as a standalone command

# If we have paths from Nautilus (right-click in Nautilus)
if [ -n "$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS" ]; then
    # Clean and copy the paths
    cleaned_paths=$(echo "$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS" | sed "s/'/\\'/g" | tr '\n' ' ')
    echo -n "$cleaned_paths" | xclip -selection clipboard
    echo -n "$cleaned_paths" > /tmp/last_copied_paths
    notify-send "Path(s) copied to clipboard:" "$cleaned_paths"
    
# If we're called with --paste argument (from keybinding)
elif [ "$1" = "--paste" ]; then
    if [ -f /tmp/last_copied_paths ]; then
        # Get the current clipboard content to restore later
        current_clip=$(xclip -o -selection clipboard 2>/dev/null)
        
        # Put the paths back in clipboard
        cat /tmp/last_copied_paths | xclip -selection clipboard
        
        # Give time for clipboard to update
        sleep 0.3
        
        # Paste using Ctrl+V (more reliable than typing)
        xdotool key --clearmodifiers ctrl+v
        
        # Restore original clipboard content after a delay
        (sleep 1; echo -n "$current_clip" | xclip -selection clipboard) &
    else
        notify-send "No paths to paste" "Copy some files first with Ctrl+Shift+C"
    fi
EOF

    chmod +x "$script_path"
    
    # Create symlink in Nautilus scripts directory
    ln -sf "$script_path" "$symlink_path"
    
    print_status $GREEN "Enhanced copy-path script created successfully!"
    print_status $GREEN "Nautilus integration set up automatically!"
}

# Modified main function to set up all keybindings including Insync kill
set_all_keybindings() {
    print_status $GREEN "Configuring GNOME custom keybindings..."
    
    # Define the keybindings we'll be using (including new Super+K)
    local bindings=("<Super>e" "<Super>r" "<Super>t" "<Super><Ctrl>s" "<Ctrl><Shift>c" "<Ctrl><Shift>v" "<Super>k")
    
    # Ask user if they want to verify conflicts
    read -p "Do you want to verify for shortcut conflicts before proceeding? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        verify_keybindings "${bindings[@]}"
    fi
    
    # Create the enhanced copy-path script and set up Nautilus integration
    create_copy_path_script
    
    # Increase the array size to accommodate the new keybindings (now 7 items)
    set_keybindings_array
    
    # Set individual keybindings
    set_individual_keybinding 0 "Open File Manager" "nautilus --new-window" "<Super>e"
    set_individual_keybinding 1 "Restart PC" "systemctl reboot" "<Super>r"
    set_individual_keybinding 2 "Shutdown PC" "systemctl poweroff" "<Super>t"
    set_individual_keybinding 3 "Open Settings" "gnome-control-center" "<Super><Ctrl>s"
    set_individual_keybinding 4 "Copy File Path" "$HOME/.local/bin/copy-path.sh" "<Ctrl><Shift>c"
    set_individual_keybinding 5 "Paste File Path" "$HOME/.local/bin/copy-path.sh --paste" "<Ctrl><Shift>v"
    set_individual_keybinding 6 "Kill Insync" "pkill -f insync" "<Super>k"
    
    print_status $GREEN "All keybindings have been configured successfully!"
    print_status $YELLOW "You can now use:"
    print_status $YELLOW "  - Ctrl+Shift+C in Nautilus to copy file paths"
    print_status $YELLOW "  - Ctrl+Shift+V anywhere to paste the paths"
    print_status $YELLOW "  - Super+K to kill Insync processes"
}

# execute the main function
set_all_keybindings