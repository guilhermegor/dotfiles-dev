#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success")
            echo -e "${GREEN}[Success]${NC} ${message}"
            ;;
        "error")
            echo -e "${RED}[Error]${NC} ${message}" >&2
            ;;
        "warning")
            echo -e "${YELLOW}[Warning]${NC} ${message}"
            ;;
        "info")
            echo -e "${BLUE}[Info]${NC} ${message}"
            ;;
        "config")
            echo -e "${CYAN}[Config]${NC} ${message}"
            ;;
        *)
            echo -e "[ ] ${message}"
            ;;
    esac
}

remove_thunderbird_completely() {
    print_status "info" "Completely removing Thunderbird from system..."
    
    # First, remove from dock favorites
    print_status "info" "Removing Thunderbird from dock favorites..."
    
    # Get current favorites
    local current_favorites=$(gsettings get org.gnome.shell favorite-apps)
    
    # Check if Thunderbird exists in favorites using the exact desktop file names found
    local thunderbird_patterns=(
        "thunderbird.desktop"
        "thunderbird_thunderbird.desktop"
        "org.mozilla.Thunderbird.desktop"
        "mozilla-thunderbird.desktop"
    )
    
    local found_thunderbird=false
    local new_favorites="$current_favorites"
    
    for pattern in "${thunderbird_patterns[@]}"; do
        if [[ "$current_favorites" == *"$pattern"* ]]; then
            print_status "info" "Found Thunderbird in favorites: $pattern"
            found_thunderbird=true
            
            # Remove the Thunderbird entry using robust pattern matching
            new_favorites=$(echo "$new_favorites" | sed "s/,'$pattern'//g" | sed "s/'$pattern',//g" | sed "s/'$pattern'//g")
            new_favorites=$(echo "$new_favorites" | sed "s/, *'$pattern'//g" | sed "s/'$pattern' *, *//g")
        fi
    done
    
    if [ "$found_thunderbird" = true ]; then
        gsettings set org.gnome.shell favorite-apps "$new_favorites"
        print_status "success" "Thunderbird removed from dock favorites"
    else
        print_status "info" "Thunderbird not found in dock favorites"
    fi
    
    # Remove from app folders
    print_status "info" "Removing Thunderbird from app folders..."
    
    local folder_children=$(gsettings get org.gnome.desktop.app-folders folder-children)
    folder_children=$(echo "$folder_children" | sed "s/\[//g" | sed "s/\]//g" | sed "s/'//g")
    IFS=',' read -ra folders <<< "$folder_children"
    
    for folder in "${folders[@]}"; do
        folder=$(echo "$folder" | xargs)
        if [ -n "$folder" ]; then
            local folder_apps=$(gsettings get org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/${folder}/ apps)
            
            for pattern in "${thunderbird_patterns[@]}"; do
                if [[ "$folder_apps" == *"$pattern"* ]]; then
                    print_status "info" "Removing Thunderbird from folder: $folder"
                    local new_folder_apps=$(echo "$folder_apps" | sed "s/,'$pattern'//g" | sed "s/'$pattern',//g" | sed "s/'$pattern'//g")
                    new_folder_apps=$(echo "$new_folder_apps" | sed "s/, *'$pattern'//g" | sed "s/'$pattern' *, *//g")
                    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/${folder}/ apps "$new_folder_apps"
                    print_status "success" "Thunderbird removed from $folder folder"
                fi
            done
        fi
    done
    
    # Kill any running Thunderbird processes
    print_status "info" "Stopping Thunderbird processes..."
    if pgrep -x "thunderbird" > /dev/null; then
        killall thunderbird 2>/dev/null
        sleep 2
        print_status "success" "Thunderbird processes stopped"
    else
        print_status "info" "No Thunderbird processes running"
    fi
    
    # Check for snap installation
    if snap list 2>/dev/null | grep -q "thunderbird"; then
        print_status "info" "Removing Thunderbird snap package..."
        sudo snap remove thunderbird
        if [ $? -eq 0 ]; then
            print_status "success" "Thunderbird snap package removed"
        else
            print_status "error" "Failed to remove Thunderbird snap package"
        fi
    else
        print_status "info" "Thunderbird snap package not found"
    fi
    
    # Check for apt installation
    if dpkg -l 2>/dev/null | grep -q "^ii.*thunderbird"; then
        print_status "info" "Removing Thunderbird apt package..."
        sudo apt remove --purge thunderbird thunderbird-gnome-support -y
        sudo apt autoremove -y
        if [ $? -eq 0 ]; then
            print_status "success" "Thunderbird apt package removed"
        else
            print_status "error" "Failed to remove Thunderbird apt package"
        fi
    else
        print_status "info" "Thunderbird apt package not found"
    fi
    
    # Check for flatpak installation
    if command -v flatpak &> /dev/null; then
        if flatpak list 2>/dev/null | grep -q "thunderbird"; then
            print_status "info" "Removing Thunderbird flatpak package..."
            flatpak uninstall org.mozilla.Thunderbird -y
            if [ $? -eq 0 ]; then
                print_status "success" "Thunderbird flatpak package removed"
            else
                print_status "error" "Failed to remove Thunderbird flatpak package"
            fi
        else
            print_status "info" "Thunderbird flatpak package not found"
        fi
    fi
    
    # Remove desktop files manually (in case of manual installation)
    print_status "info" "Checking for manual Thunderbird desktop files..."
    local desktop_locations=(
        "$HOME/.local/share/applications"
        "/usr/share/applications"
        "/usr/local/share/applications"
    )
    
    local removed_desktop_files=false
    for location in "${desktop_locations[@]}"; do
        for pattern in "${thunderbird_patterns[@]}"; do
            if [ -f "$location/$pattern" ]; then
                print_status "info" "Found desktop file: $location/$pattern"
                if [ -w "$location/$pattern" ]; then
                    rm "$location/$pattern"
                    removed_desktop_files=true
                    print_status "success" "Removed $location/$pattern"
                else
                    sudo rm "$location/$pattern"
                    removed_desktop_files=true
                    print_status "success" "Removed $location/$pattern (with sudo)"
                fi
            fi
        done
    done
    
    if [ "$removed_desktop_files" = false ]; then
        print_status "info" "No orphaned desktop files found"
    fi
    
    # Update desktop database
    if [ "$removed_desktop_files" = true ]; then
        print_status "info" "Updating desktop database..."
        update-desktop-database ~/.local/share/applications 2>/dev/null
        sudo update-desktop-database /usr/share/applications 2>/dev/null
        print_status "success" "Desktop database updated"
    fi
    
    # Information about user data
    if [ -d "$HOME/.thunderbird" ]; then
        print_status "warning" "Thunderbird configuration and data remains in ~/.thunderbird"
        print_status "info" "To remove all Thunderbird data, run: rm -rf ~/.thunderbird"
    else
        print_status "info" "No Thunderbird user data found"
    fi
    
    print_status "success" "Thunderbird has been completely removed from the system!"
}

configure_terminal() {
    print_status "info" "Configuring terminal profile..."
    
    # get default profile ID
    local profile_id=$(gsettings get org.gnome.Terminal.ProfilesList default)
    profile_id=${profile_id:1:-1} # remove single quotes
    
    # configure terminal appearance
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/ use-theme-colors false
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/ palette "['rgb(46,52,54)', 'rgb(204,0,0)', 'rgb(78,154,6)', 'rgb(196,160,0)', 'rgb(52,101,164)', 'rgb(117,80,123)', 'rgb(6,152,154)', 'rgb(211,215,207)', 'rgb(85,87,83)', 'rgb(239,41,41)', 'rgb(138,226,52)', 'rgb(252,233,79)', 'rgb(114,159,207)', 'rgb(173,127,168)', 'rgb(52,226,226)', 'rgb(238,238,236)']"
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/ background-color 'rgb(46,52,54)'
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/ foreground-color 'rgb(238,238,236)'
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/ bold-color-same-as-fg true
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/ bold-color 'rgb(238,238,236)'
    
    print_status "success" "Terminal configured with Tango Dark theme"
}

set_dark_mode() {
    print_status "info" "Configuring dark mode..."
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark'
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    print_status "success" "Dark mode configured"
}

set_dock_icon_size() {
    print_status "info" "Setting dock icon size to 48..."
    gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 48
    print_status "success" "Dock icon size set to 48"
}

set_dock_position_bottom() {
    print_status "info" "Setting dock position to bottom..."
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
    print_status "success" "Dock position set to BOTTOM"
}

set_workspaces_primary_only() {
    print_status "info" "Configuring workspaces for primary display only..."
    gsettings set org.gnome.mutter workspaces-only-on-primary true
    
    # Check if the schema exists before trying to set it
    if gsettings list-schemas | grep -q "org.gnome.shell.overrides"; then
        gsettings set org.gnome.shell.overrides workspaces-only-on-primary true
    else
        print_status "warning" "org.gnome.shell.overrides schema not available - skipping"
    fi
    
    print_status "success" "Workspaces configured for primary display only"
}

set_workspace_app_isolation() {
    print_status "info" "Configurando alternador de aplicativos para mostrar apenas apps do espaço de trabalho atual..."
    
    # This setting makes Alt+Tab show only applications from the current workspace
    gsettings set org.gnome.shell.app-switcher current-workspace-only true
    
    # Alternative setting for some GNOME versions
    if gsettings list-schemas | grep -q "org.gnome.shell.window-switcher"; then
        gsettings set org.gnome.shell.window-switcher current-workspace-only true
    fi
    
    local CURRENT_SETTING=$(gsettings get org.gnome.shell.app-switcher current-workspace-only)
    print_status "success" "Alternador de aplicativos configurado para espaço de trabalho atual: $CURRENT_SETTING"
}

configure_mouse() {
    print_status "info" "Configuring mouse settings..."
    
    # Set mouse speed (velocity) - middle value similar to the screenshot
    gsettings set org.gnome.desktop.peripherals.mouse speed 0.0
    
    # Enable mouse acceleration (default profile)
    gsettings set org.gnome.desktop.peripherals.mouse accel-profile 'default'
    
    # Enable natural scrolling
    gsettings set org.gnome.desktop.peripherals.mouse natural-scroll true
    
    local MOUSE_SPEED=$(gsettings get org.gnome.desktop.peripherals.mouse speed)
    local ACCEL_PROFILE=$(gsettings get org.gnome.desktop.peripherals.mouse accel-profile)
    local NATURAL_SCROLL=$(gsettings get org.gnome.desktop.peripherals.mouse natural-scroll)
    
    print_status "success" "Mouse configured:"
    print_status "config" "  Speed: $MOUSE_SPEED"
    print_status "config" "  Acceleration: $ACCEL_PROFILE"
    print_status "config" "  Natural scrolling: $NATURAL_SCROLL"
}

configure_dock() {
    print_status "info" "Configuring dock..."
    
    # First check if dash-to-dock is installed
    if ! gsettings list-schemas | grep -q org.gnome.shell.extensions.dash-to-dock; then
        print_status "warning" "Dash-to-dock extension not found. Installing..."
        sudo apt install -y gnome-shell-extension-dash-to-dock
        # Restart GNOME Shell to activate
        busctl --user call org.gnome.Shell /org/gnome/Shell org.gnome.Shell Eval s 'Meta.restart("Restarting GNOME Shell...")'
        sleep 3 # Wait for restart
    fi
    
    # Dock position and behavior
    gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false
    set_dock_position_bottom
    set_dock_icon_size
    gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.7
    gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'FIXED'
    
    # Disable showing volumes and devices in dock
    print_status "info" "Disabling volumes and devices in dock..."
    gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts false
    
    print_status "info" "Configuring dock auto-hide..."
    gsettings set org.gnome.shell.extensions.dash-to-dock autohide true
    gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
    
    # Additional dock hiding settings for better behavior
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
    gsettings set org.gnome.shell.extensions.dash-to-dock intellihide-mode 'FOCUS_APPLICATION_WINDOWS'
    
    # Set hide animation speed (in seconds)
    gsettings set org.gnome.shell.extensions.dash-to-dock animation-time 0.2
    gsettings set org.gnome.shell.extensions.dash-to-dock hide-delay 0.2
    gsettings set org.gnome.shell.extensions.dash-to-dock show-delay 0.25
    
    print_status "success" "Dock auto-hide configured"
    
    # Set favorite apps with robust desktop file detection
    print_status "info" "Configuring favorite apps..."
    
    # Function to check if desktop file exists and return the path
    find_desktop_file() {
        local app_name="$1"
        if [ -f "$HOME/.local/share/applications/$app_name" ]; then
            echo "$app_name"
            return 0
        elif [ -f "/usr/share/applications/$app_name" ]; then
            echo "$app_name"
            return 0
        elif [ -f "/var/lib/snapd/desktop/applications/$app_name" ]; then
            echo "$app_name"
            return 0
        elif [ -f "/var/lib/flatpak/exports/share/applications/$app_name" ]; then
            echo "$app_name"
            return 0
        fi
        return 1
    }
    
    # Build favorites list with apps in the specified order
    local favorites=()
    
    # 1. Spotify
    for app in 'spotify_spotify.desktop' 'spotify.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 2. Firefox
    for app in 'firefox_firefox.desktop' 'firefox.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 3. Google Chrome
    for app in 'google-chrome.desktop' 'chrome.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 4. Google Keep
    for app in 'chrome-eilembjdkfgodjkcjnpgpaenohkicgjd-Default.desktop' 'google-keep_google-keep.desktop' 'google-keep.desktop' 'keep.desktop' 'keep_keep.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 5. Notion
    for app in 'notion-snap-reborn_notion-snap-reborn.desktop' 'notion-app_notion-app.desktop' 'notion-app.desktop' 'notion.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 6. VS Code
    for app in 'code_code.desktop' 'code.desktop' 'visual-studio-code.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 7. Terminal
    for app in 'org.gnome.Terminal.desktop' 'gnome-terminal.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 8. Postman
    for app in 'Postman.desktop' 'postman_postman.desktop' 'postman.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 9. pgAdmin 4
    for app in 'pgadmin4.desktop' 'pgadmin4_pgadmin4.desktop' 'org.pgadmin.pgAdmin4.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 10. Docker Desktop
    for app in 'docker-desktop.desktop' 'docker_docker-desktop.desktop' 'docker.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # 11. DBeaver CE
    for app in 'dbeaver-ce_dbeaver-ce.desktop' 'dbeaver-ce.desktop' 'dbeaver.desktop' 'io.dbeaver.DBeaverCommunity.desktop'; do
        if result=$(find_desktop_file "$app"); then
            favorites+=("'$result'")
            break
        fi
    done
    
    # Convert array to comma-separated string
    local favorites_str=$(IFS=,; echo "${favorites[*]}")
    
    # Set favorites (this replaces all existing favorites)
    gsettings set org.gnome.shell favorite-apps "[${favorites_str}]"
    
    print_status "success" "Dock configured with ${#favorites[@]} favorite apps"
    print_status "info" "Apps in order: ${favorites_str}"
    
    # Now explicitly remove Thunderbird to ensure it's gone
    remove_thunderbird_completely
}

set_ubuntu_ui_interface() {
    print_status "info" "Setting verde-azulado (green-blue) accent color..."
    
    # Set Yaru themes
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-viridian-dark'
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru-viridian'
    gsettings set org.gnome.desktop.wm.preferences theme 'Yaru-viridian-dark'
    
    # Also set color scheme to dark
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    
    print_status "success" "Accent color set to verde-azulado (Yaru-viridian)"
}

configure_workspaces() {
    set_workspaces_primary_only
    set_workspace_app_isolation
}

apply_additional_tweaks() {
    print_status "info" "Applying additional tweaks..."
    gsettings set org.gnome.desktop.interface enable-animations true

    # Set clock format to show weekday name and week number
    gsettings set org.gnome.desktop.interface clock-format '24h'
    gsettings set org.gnome.desktop.interface clock-show-weekday true
    gsettings set org.gnome.desktop.interface clock-show-date true
    
    # Try different methods for week number display
    if gsettings list-schemas | grep -q org.gnome.shell.clock; then
        gsettings set org.gnome.shell.clock date-format "'%A %W'"  # shows weekday name and week number
    else
        # Alternative method for newer GNOME versions
        gsettings set org.gnome.desktop.interface clock-show-weekday true
        print_status "warning" "Direct week number display not available - using weekday only"
    fi
    
    # Other tweaks
    gsettings set org.gnome.desktop.background show-desktop-icons true
    gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
    
    print_status "success" "Additional tweaks applied"
}

configure_inactivity_time_lock() {
    print_status "info" "Set inactivity time to lock workspace..."
    gsettings set org.gnome.desktop.session idle-delay 900
    local CURRENT_DELAY=$(gsettings get org.gnome.desktop.session idle-delay)
    print_status "success" "Inactivity time set to $CURRENT_DELAY seconds"
}

configure_power_settings() {
    print_status "info" "Configuring power settings..."
    
    # Set screen blank time to 30 minutes (1800 seconds) when on battery
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 1800
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
    
    local BATTERY_TIMEOUT=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout)
    print_status "success" "Screen will turn off after $BATTERY_TIMEOUT seconds (30 min) on battery"
}

organize_app_folders() {
    print_status "info" "Organizing applications into folders..."
    
    # Function to find desktop file and return just the filename
    find_app_desktop_file() {
        local app_name="$1"
        if [ -f "$HOME/.local/share/applications/$app_name" ]; then
            echo "$app_name"
            return 0
        elif [ -f "/usr/share/applications/$app_name" ]; then
            echo "$app_name"
            return 0
        elif [ -f "/var/lib/snapd/desktop/applications/$app_name" ]; then
            echo "$app_name"
            return 0
        elif [ -f "/var/lib/flatpak/exports/share/applications/$app_name" ]; then
            echo "$app_name"
            return 0
        fi
        return 1
    }
    
    # Get current folder settings
    local current_folders=$(gsettings get org.gnome.desktop.app-folders folder-children)
    
    # Initialize array to store folder IDs
    local folder_ids=()
    
    # ==================== SISTEMA (SYSTEM) FOLDER ====================
    print_status "info" "Creating Sistema folder..."
    local sistema_apps=()
    
    # System applications - common desktop file names
    local system_app_names=(
        # Software/Package Management
        'update-manager.desktop' 'software-properties-gtk.desktop' 'software-properties-drivers.desktop'
        'synaptic.desktop' 'org.gnome.Software.desktop' 'snap-store_ubuntu-software.desktop'
        'io.github.flattool.Warehouse.desktop' 'com.github.tchx84.Flatseal.desktop' 'flatseal.desktop'
        
        # System Settings & Configuration
        'gnome-control-center.desktop' 'unity-control-center.desktop' 'org.gnome.Settings.desktop'
        'gnome-session-properties.desktop' 'gnome-startup-applications.desktop'
        'org.gnome.PowerStats.desktop' 'gnome-power-statistics.desktop' 'power-statistics.desktop'
        
        # System Monitoring
        'gnome-system-monitor.desktop' 'org.gnome.SystemMonitor.desktop'
        'htop.desktop' 'cpu-x.desktop' 'cpux.desktop'
        'io.github.thetumultuousunicornofdarkness.cpu-x.desktop'
        
        # Hardware & Drivers
        'nvidia-settings.desktop' 'software-properties-drivers.desktop'
        'gnome-firmware-panel.desktop' 'gnome-firmware.desktop' 'firmware-updater.desktop'
        'org.gnome.firmware.desktop' 'org.gnome.Firmware.desktop' 'fwupd.desktop'
        'solaar.desktop' 'io.github.pwr_solaar.solaar.desktop'
        
        # Language & Locale
        'gnome-language-selector.desktop' 'language-selector.desktop'
        
        # Help & Documentation
        'yelp.desktop' 'gnome-help.desktop' 'help.desktop' 'org.gnome.Yelp.desktop'
        
        # Ubuntu specific
        'ubuntu-session-properties.desktop' 'gnome-initial-setup.desktop'
        'update-notifier.desktop' 'software-center.desktop'
        
        # Firmware Updater - Snap package versions
        'firmware-updater_firmware-updater.desktop' 'firmware-updater_firmware-updater-app.desktop'

        # Mission Center (Central de Missões)
        'mission-center.desktop' 'io.missioncenter.MissionCenter.desktop'
        
        # GNOME Network Displays (Tela via Rede)
        'org.gnome.NetworkDisplays.desktop' 'gnome-network-displays.desktop'
        'org.gnome.Connections.desktop' 'gnome-connections.desktop' 'gnome-remote-desktop.desktop'
    )
    
    # Search for system apps
    for app in "${system_app_names[@]}"; do
        if result=$(find_app_desktop_file "$app"); then
            sistema_apps+=("'$result'")
        fi
    done
    
    # Also search for related patterns - INCLUDING SNAP/FLATPAK LOCATIONS
    shopt -s nullglob
    for desktop_file in /usr/share/applications/*system*.desktop \
                        /usr/share/applications/*settings*.desktop \
                        /usr/share/applications/*config*.desktop \
                        /usr/share/applications/*update*.desktop \
                        /usr/share/applications/*driver*.desktop \
                        /usr/share/applications/*firmware*.desktop \
                        /var/lib/snapd/desktop/applications/*firmware*.desktop \
                        /var/lib/snapd/desktop/applications/*system*.desktop \
                        /var/lib/snapd/desktop/applications/*update*.desktop \
                        /var/lib/flatpak/exports/share/applications/*missioncenter*.desktop \
                        /var/lib/flatpak/exports/share/applications/*cpu-x*.desktop \
                        /var/lib/flatpak/exports/share/applications/*NetworkDisplays*.desktop \
                        /var/lib/flatpak/exports/share/applications/*connections*.desktop \
                        "$HOME/.local/share/applications"/*system*.desktop \
                        "$HOME/.local/share/applications"/*settings*.desktop \
                        "$HOME/.local/share/applications"/*config*.desktop \
                        "$HOME/.local/share/applications"/*firmware*.desktop \
                        "$HOME/.local/share/applications"/*missioncenter*.desktop \
                        "$HOME/.local/share/applications"/*cpu-x*.desktop \
                        "$HOME/.local/share/applications"/*NetworkDisplays*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            if [[ ! "$basename" =~ "game" ]] && [[ ! "$basename" =~ "sound" ]] && \
               [[ ! "$basename" =~ "color" ]] && [[ ! " ${sistema_apps[@]} " =~ " '$basename' " ]]; then
                sistema_apps+=("'$basename'")
            fi
        fi
    done
    shopt -u nullglob
    
    # Remove duplicates
    sistema_apps=($(echo "${sistema_apps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    if [ ${#sistema_apps[@]} -gt 0 ]; then
        local sistema_apps_str=$(IFS=,; echo "${sistema_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Sistema/ name 'Sistema'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Sistema/ apps "[${sistema_apps_str}]"
        folder_ids+=("'Sistema'")
        print_status "success" "Sistema folder created with ${#sistema_apps[@]} apps"
        print_status "config" "  Apps: ${sistema_apps_str}"
    else
        print_status "warning" "No Sistema apps found"
    fi
    
    # ==================== SEGURANÇA (SECURITY) FOLDER ====================
    print_status "info" "Creating Segurança folder..."
    local seguranca_apps=()
    
    # Security and Backup applications
    local security_app_names=(
        'clamtk.desktop' 'com.gitlab.davem.ClamTk.desktop'
        'timeshift-gtk.desktop' 'timeshift.desktop' 'com.teejeetech.Timeshift.desktop'
        'org.gnome.DejaDup.desktop' 'deja-dup.desktop' 'deja-dup-preferences.desktop'
        'backups.desktop' 'gnome-backups.desktop'
        'duplicity.desktop' 'grsync.desktop' 'luckybackup.desktop'
        'veracrypt.desktop' 'keepassxc.desktop' 'seahorse.desktop' 'gnome-seahorse.desktop'
        'gufw.desktop' 'firewall-config.desktop' 'ufw.desktop'
    )
    
    for app in "${security_app_names[@]}"; do
        if result=$(find_app_desktop_file "$app"); then
            seguranca_apps+=("'$result'")
        fi
    done
    
    shopt -s nullglob
    for desktop_file in /usr/share/applications/*backup*.desktop \
                        /usr/share/applications/*timeshift*.desktop \
                        /usr/share/applications/*clam*.desktop \
                        /usr/share/applications/*security*.desktop \
                        /usr/share/applications/*firewall*.desktop \
                        /usr/share/applications/*encrypt*.desktop \
                        "$HOME/.local/share/applications"/*backup*.desktop \
                        "$HOME/.local/share/applications"/*timeshift*.desktop \
                        "$HOME/.local/share/applications"/*clam*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            if [[ ! " ${seguranca_apps[@]} " =~ " '$basename' " ]]; then
                seguranca_apps+=("'$basename'")
            fi
        fi
    done
    shopt -u nullglob
    
    seguranca_apps=($(echo "${seguranca_apps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    if [ ${#seguranca_apps[@]} -gt 0 ]; then
        local seguranca_apps_str=$(IFS=,; echo "${seguranca_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Seguranca/ name 'Segurança'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Seguranca/ apps "[${seguranca_apps_str}]"
        folder_ids+=("'Seguranca'")
        print_status "success" "Segurança folder created with ${#seguranca_apps[@]} apps"
        print_status "config" "  Apps: ${seguranca_apps_str}"
    else
        print_status "warning" "No Segurança apps found"
    fi
    
    # ==================== UTILITÁRIOS (UTILITIES) FOLDER ====================
    print_status "info" "Creating Utilitários folder..."
    local utilitarios_apps=()
    
    local utility_app_names=(
        'nm-connection-editor.desktop' 'network-admin.desktop' 'gnome-nettool.desktop'
        'org.gnome.baobab.desktop' 'baobab.desktop'
        'org.gnome.DiskUtility.desktop' 'gnome-disks.desktop' 'gnome-disk-utility.desktop'
        'org.gnome.FileShredder.desktop' 'file-shredder.desktop' 'shredder.desktop'
        'com.github.ADBeveridge.Raider.desktop' 'raider.desktop'
        'org.gnome.Evince.desktop' 'evince.desktop'
        'org.gnome.eog.desktop' 'eog.desktop' 'org.gnome.ImageViewer.desktop'
        'org.gnome.seahorse.Application.desktop' 'seahorse.desktop'
        'org.gnome.Software.desktop' 'gnome-software.desktop' 'software-center.desktop'
        'snap-store_ubuntu-software.desktop' 'snap-store_snap-store.desktop' 'snap-store.desktop'
        'io.snapcraft.Store.desktop' 'snapcraft-store.desktop'
        'org.gnome.Extensions.desktop' 'gnome-extensions.desktop' 'gnome-shell-extension-prefs.desktop'
        'com.mattjakeman.ExtensionManager.desktop' 'extension-manager.desktop' 'gnome-extension-manager.desktop'
        'com.github.hluk.copyq.desktop' 'copyq.desktop'
        'org.gnome.Shotwell.desktop' 'shotwell.desktop' 'shotwell-viewer.desktop'
        'org.gnome.clocks.desktop' 'gnome-clocks.desktop'
        'org.gnome.Calculator.desktop' 'gnome-calculator.desktop' 'gcalctool.desktop'
        'org.gnome.Nautilus.desktop' 'nautilus.desktop' 'org.gnome.Files.desktop'
        'org.freedesktop.Piper.desktop' 'piper.desktop'
        'vlc.desktop' 'org.videolan.VLC.desktop'
        'org.gnome.Logs.desktop' 'gnome-logs.desktop' 'gnome-system-log.desktop'
        'org.gnome.Characters.desktop' 'gucharmap.desktop' 'gnome-characters.desktop'
        'org.gnome.font-viewer.desktop' 'gnome-font-viewer.desktop' 'org.gnome.FontManager.desktop'
        'font-manager.desktop' 'fonts.desktop'
        'org.gnome.gedit.desktop' 'gedit.desktop' 'org.gnome.TextEditor.desktop' 'gnome-text-editor.desktop'
        'org.gnome.FileRoller.desktop' 'file-roller.desktop'
        'org.gnome.Screenshot.desktop' 'gnome-screenshot.desktop'
        'flameshot.desktop' 'org.flameshot.Flameshot.desktop'
        'org.gnome.Weather.desktop' 'gnome-weather.desktop'
        'org.gnome.Maps.desktop' 'gnome-maps.desktop'
        'evolution.desktop' 'org.gnome.Evolution.desktop'
        'geary.desktop' 'org.gnome.Geary.desktop'
        'usb-creator-gtk.desktop' 'gnome-multi-writer.desktop' 'org.gnome.MultiWriter.desktop'
        'startup-disk-creator.desktop'
        'simple-scan.desktop' 'org.gnome.SimpleScan.desktop' 'gnome-simple-san.desktop'
        'xsane.desktop' 'skanlite.desktop'
        'geomview.desktop' 'org.geomview.Geomview.desktop'
        'bleachbit.desktop'
    )
    
    for app in "${utility_app_names[@]}"; do
        if result=$(find_app_desktop_file "$app"); then
            utilitarios_apps+=("'$result'")
        fi
    done
    
    shopt -s nullglob
    for desktop_file in /usr/share/applications/org.gnome.*.desktop \
                        /usr/share/applications/*viewer*.desktop \
                        /usr/share/applications/*calculator*.desktop \
                        /usr/share/applications/*files*.desktop \
                        /usr/share/applications/*nautilus*.desktop \
                        /usr/share/applications/*evolution*.desktop \
                        /usr/share/applications/*geary*.desktop \
                        /usr/share/applications/*scan*.desktop \
                        /usr/share/applications/*usb-creator*.desktop \
                        /usr/share/applications/*startup-disk*.desktop \
                        /usr/share/applications/*geomview*.desktop \
                        /usr/share/applications/*flameshot*.desktop \
                        /var/lib/snapd/desktop/applications/snap-store*.desktop \
                        /var/lib/snapd/desktop/applications/*software*.desktop \
                        /var/lib/flatpak/exports/share/applications/*Raider*.desktop \
                        /var/lib/flatpak/exports/share/applications/*shredder*.desktop \
                        /var/lib/flatpak/exports/share/applications/*flameshot*.desktop \
                        "$HOME/.local/share/applications"/org.gnome.*.desktop \
                        "$HOME/.local/share/applications"/*evolution*.desktop \
                        "$HOME/.local/share/applications"/*scan*.desktop \
                        "$HOME/.local/share/applications"/*geomview*.desktop \
                        "$HOME/.local/share/applications"/*Raider*.desktop \
                        "$HOME/.local/share/applications"/*flameshot*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            if [[ ! "$basename" =~ "settings" ]] && [[ ! "$basename" =~ "control-center" ]] && \
               [[ ! "$basename" =~ "software-properties" ]] && [[ ! "$basename" =~ "update" ]] && \
               [[ ! "$basename" =~ "firmware" ]] && [[ ! " ${utilitarios_apps[@]} " =~ " '$basename' " ]]; then
                utilitarios_apps+=("'$basename'")
            fi
        fi
    done
    shopt -u nullglob
    
    utilitarios_apps=($(echo "${utilitarios_apps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    if [ ${#utilitarios_apps[@]} -gt 0 ]; then
        local utilitarios_apps_str=$(IFS=,; echo "${utilitarios_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Utilitarios/ name 'Utilitários'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Utilitarios/ apps "[${utilitarios_apps_str}]"
        folder_ids+=("'Utilitarios'")
        print_status "success" "Utilitários folder created with ${#utilitarios_apps[@]} apps"
        print_status "config" "  Apps: ${utilitarios_apps_str}"
    else
        print_status "warning" "No Utilitários apps found"
    fi
    
    # ==================== SHARING FOLDER ====================
    print_status "info" "Creating Sharing folder..."
    local sharing_apps=()
    
    for app in 'org.kde.kdeconnect.settings.desktop' 'org.kde.kdeconnect.nonplasma.desktop' \
               'org.kde.kdeconnect.app.desktop' 'org.kde.kdeconnect.sms.desktop' \
               'kdeconnect-settings.desktop' 'kdeconnect.desktop' 'kdeconnect-indicator.desktop' \
               'kdeconnect-sms.desktop' 'org.kde.kdeconnect_open.desktop' \
               'org.localsend.localsend_app.desktop' 'localsend.desktop' 'localsend_app.desktop' \
               'transmission-gtk.desktop' 'transmission.desktop' 'org.transmissionbt.Transmission.desktop' \
               'insync.desktop' 'com.insynchq.insync.desktop' 'insync-app.desktop'; do
        if result=$(find_app_desktop_file "$app"); then
            sharing_apps+=("'$result'")
        fi
    done
    
    shopt -s nullglob
    for desktop_file in /usr/share/applications/*kdeconnect*.desktop "$HOME/.local/share/applications"/*kdeconnect*.desktop \
                        /usr/share/applications/*localsend*.desktop "$HOME/.local/share/applications"/*localsend*.desktop \
                        /usr/share/applications/*transmission*.desktop "$HOME/.local/share/applications"/*transmission*.desktop \
                        /usr/share/applications/*insync*.desktop "$HOME/.local/share/applications"/*insync*.desktop \
                        /var/lib/flatpak/exports/share/applications/*insync*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            if [[ ! " ${sharing_apps[@]} " =~ " '$basename' " ]]; then
                sharing_apps+=("'$basename'")
            fi
        fi
    done
    shopt -u nullglob
    
    sharing_apps=($(echo "${sharing_apps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    if [ ${#sharing_apps[@]} -gt 0 ]; then
        local sharing_apps_str=$(IFS=,; echo "${sharing_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Sharing/ name 'Sharing'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Sharing/ apps "[${sharing_apps_str}]"
        folder_ids+=("'Sharing'")
        print_status "success" "Sharing folder created with ${#sharing_apps[@]} apps"
        print_status "config" "  Apps: ${sharing_apps_str}"
    else
        print_status "warning" "No Sharing apps found"
    fi
    
    # ==================== IRPF FOLDER ====================
    print_status "info" "Creating IRPF folder..."
    local irpf_apps=()
    
    shopt -s nullglob
    for desktop_file in /usr/share/applications/*.desktop "$HOME/.local/share/applications"/*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            if [[ "$basename" =~ [Ii][Rr][Pp][Ff] ]] || [[ "$basename" =~ irpf ]]; then
                irpf_apps+=("'$basename'")
            fi
        fi
    done
    shopt -u nullglob
    
    irpf_apps=($(echo "${irpf_apps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    if [ ${#irpf_apps[@]} -gt 0 ]; then
        local irpf_apps_str=$(IFS=,; echo "${irpf_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/IRPF/ name 'IRPF'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/IRPF/ apps "[${irpf_apps_str}]"
        folder_ids+=("'IRPF'")
        print_status "success" "IRPF folder created with ${#irpf_apps[@]} apps"
        print_status "config" "  Apps: ${irpf_apps_str}"
    else
        print_status "warning" "No IRPF apps found"
    fi
    
    # ==================== DEV FOLDER ====================
    print_status "info" "Creating DEV folder..."
    local dev_apps=()

    local dev_app_names=(
        'vim.desktop' 'gvim.desktop' 'org.vim.Vim.desktop'
        'nvim.desktop' 'neovim.desktop' 'org.neovim.nvim.desktop'  # Added Neovim
        'dev.warp.Warp.desktop' 'warp.desktop' 'warp-terminal.desktop'
        'me.iepure.devtoolbox.desktop' 'devtoolbox.desktop' 'dev-toolbox.desktop'
        'miro.desktop' 'com.miro.Miro.desktop' 'miro-app.desktop' 'RealtimeBoard.desktop'
        'miro_miro.desktop' 'snap-miro_miro.desktop'
        'cursor.desktop' 'com.cursor.Cursor.desktop' 'cursor-app.desktop'
        'notepadqq.desktop' 'com.notepadqq.Notepadqq.desktop'
        'slack.desktop' 'com.slack.Slack.desktop' 'slack_slack.desktop' 'slack-desktop.desktop'
    )

    for app in "${dev_app_names[@]}"; do
        if result=$(find_app_desktop_file "$app"); then
            dev_apps+=("'$result'")
            print_status "config" "Found DEV app: $result"
        fi
    done

    # SPECIFIC Miro Snap package detection
    print_status "info" "Adding Miro Snap package..."
    if [ -f "/var/lib/snapd/desktop/applications/miro_miro.desktop" ]; then
        if [[ ! " ${dev_apps[@]} " =~ " 'miro_miro.desktop' " ]]; then
            dev_apps+=("'miro_miro.desktop'")
            print_status "success" "✓ Added Miro Snap package: miro_miro.desktop"
        else
            print_status "info" "Miro Snap package already in list"
        fi
    else
        print_status "warning" "Miro Snap package not found at expected location"
    fi

    # SPECIFIC Chrome App Miro detection - using the exact filename we found
    print_status "info" "Adding Miro Chrome app..."
    local miro_chrome_app="chrome-bfldocfmjhokladppcchgfolcnpjlnng-Default.desktop"
    if [ -f "$HOME/.local/share/applications/$miro_chrome_app" ]; then
        if [[ ! " ${dev_apps[@]} " =~ " '$miro_chrome_app' " ]]; then
            dev_apps+=("'$miro_chrome_app'")
            print_status "success" "✓ Added Miro Chrome app: $miro_chrome_app"
        else
            print_status "info" "Miro Chrome app already in list"
        fi
    else
        print_status "warning" "Miro Chrome app not found at: $HOME/.local/share/applications/$miro_chrome_app"
    fi

    # Additional fallback search for any other Miro Chrome apps (in case there are multiple)
    print_status "info" "Searching for additional Miro Chrome shortcuts..."
    shopt -s nullglob
    for desktop_file in "$HOME/.local/share/applications/chrome-"*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            # Skip if it's already the one we specifically added
            if [ "$basename" != "$miro_chrome_app" ]; then
                # Check if it's Miro by examining the file content
                if grep -q -i "Name.*=.*Miro" "$desktop_file" || 
                grep -q -i "Exec.*=.*miro" "$desktop_file" || 
                grep -q -i "miro" "$desktop_file" || 
                grep -q -i "realtimeboard" "$desktop_file"; then
                    if [[ ! " ${dev_apps[@]} " =~ " '$basename' " ]]; then
                        dev_apps+=("'$basename'")
                        print_status "success" "✓ Added additional Miro Chrome shortcut: $basename"
                    fi
                fi
            fi
        fi
    done
    shopt -u nullglob

    # Search for Neovim desktop files in common locations
    print_status "info" "Searching for Neovim desktop files..."
    shopt -s nullglob
    for desktop_file in /usr/share/applications/nvim*.desktop \
                        /usr/share/applications/neovim*.desktop \
                        "$HOME/.local/share/applications"/nvim*.desktop \
                        "$HOME/.local/share/applications"/neovim*.desktop \
                        /var/lib/flatpak/exports/share/applications/*nvim*.desktop \
                        /var/lib/flatpak/exports/share/applications/*neovim*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            if [[ ! " ${dev_apps[@]} " =~ " '$basename' " ]]; then
                dev_apps+=("'$basename'")
                print_status "success" "✓ Added Neovim: $basename"
            fi
        fi
    done
    shopt -u nullglob

    # Check if Neovim is installed but doesn't have a desktop file
    if command -v nvim >/dev/null 2>&1; then
        print_status "info" "Neovim is installed but checking for desktop file..."
        
        # Check if we already found a desktop file
        local found_nvim_desktop=false
        for app in "${dev_apps[@]}"; do
            if [[ "$app" == *"nvim"* ]] || [[ "$app" == *"neovim"* ]]; then
                found_nvim_desktop=true
                break
            fi
        done
        
        if [ "$found_nvim_desktop" = false ]; then
            print_status "warning" "Neovim is installed but no desktop file found"
            print_status "info" "Creating a desktop file for Neovim..."
            
            local nvim_desktop_path="$HOME/.local/share/applications/nvim.desktop"
            mkdir -p "$HOME/.local/share/applications"
            
            cat > "$nvim_desktop_path" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Neovim
GenericName=Text Editor
Comment=Edit text files
Exec=nvim %F
Icon=nvim
Terminal=true
StartupNotify=true
Categories=Development;TextEditor;
Keywords=Text;Editor;
MimeType=text/plain;
EOF
            
            if [ -f "$nvim_desktop_path" ]; then
                dev_apps+=("'nvim.desktop'")
                print_status "success" "✓ Created and added Neovim desktop file"
            else
                print_status "error" "Failed to create Neovim desktop file"
            fi
        fi
    fi

    # Remove any duplicates that might have been added
    dev_apps=($(echo "${dev_apps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    if [ ${#dev_apps[@]} -gt 0 ]; then
        local dev_apps_str=$(IFS=,; echo "${dev_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/DEV/ name 'DEV'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/DEV/ apps "[${dev_apps_str}]"
        folder_ids+=("'DEV'")
        print_status "success" "DEV folder created with ${#dev_apps[@]} apps"
        print_status "config" "  Apps in DEV folder:"
        for app in "${dev_apps[@]}"; do
            print_status "config" "    - ${app//\'/}"
        done
    else
        print_status "warning" "No DEV apps found"
    fi
    
    # ==================== EREADER FOLDER ====================
    print_status "info" "Creating ereader folder..."
    local ereader_apps=()
    
    for app in 'calibre-gui.desktop' 'calibre.desktop' \
               'calibre-ebook-edit.desktop' 'ebook-edit.desktop' \
               'calibre-ebook-viewer.desktop' 'ebook-viewer.desktop' \
               'calibre-lrfviewer.desktop' 'lrfviewer.desktop'; do
        if result=$(find_app_desktop_file "$app"); then
            ereader_apps+=("'$result'")
        fi
    done
    
    shopt -s nullglob
    for desktop_file in /usr/share/applications/*calibre*.desktop "$HOME/.local/share/applications"/*calibre*.desktop \
                        /usr/share/applications/*ebook*.desktop "$HOME/.local/share/applications"/*ebook*.desktop \
                        /usr/share/applications/*lrf*.desktop "$HOME/.local/share/applications"/*lrf*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            if [[ ! " ${ereader_apps[@]} " =~ " '$basename' " ]]; then
                ereader_apps+=("'$basename'")
            fi
        fi
    done
    shopt -u nullglob
    
    ereader_apps=($(echo "${ereader_apps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    if [ ${#ereader_apps[@]} -gt 0 ]; then
        local ereader_apps_str=$(IFS=,; echo "${ereader_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Ereader/ name 'Ereader'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Ereader/ apps "[${ereader_apps_str}]"
        folder_ids+=("'Ereader'")
        print_status "success" "Ereader folder created with ${#ereader_apps[@]} apps"
        print_status "config" "  Apps: ${ereader_apps_str}"
    else
        print_status "warning" "No Ereader apps found"
    fi
    
    # ==================== OFFICE FOLDER ====================
    print_status "info" "Creating Office folder..."
    local office_apps=()

    for app in 'libreoffice-calc.desktop' 'libreoffice-draw.desktop' 'libreoffice-impress.desktop' \
            'libreoffice-math.desktop' 'libreoffice-writer.desktop' 'libreoffice-base.desktop' \
            'libreoffice-startcenter.desktop' 'libreoffice-xsltfilter.desktop' \
            'pinta.desktop' 'com.github.PintaProject.Pinta.desktop'; do
        if result=$(find_app_desktop_file "$app"); then
            office_apps+=("'$result'")
        fi
    done

    if [ ${#office_apps[@]} -gt 0 ]; then
        local office_apps_str=$(IFS=,; echo "${office_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Office/ name 'Office'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Office/ apps "[${office_apps_str}]"
        folder_ids+=("'Office'")
        print_status "success" "Office folder created with ${#office_apps[@]} apps"
        print_status "config" "  Apps: ${office_apps_str}"
    else
        print_status "warning" "No Office apps found"
    fi
    
    # ==================== AMBIENTE VIRTUAL FOLDER ====================
    print_status "info" "Creating Ambiente Virtual folder..."
    local ambiente_virtual_apps=()

    local virtualization_app_names=(
        'virt-manager.desktop' 'org.virt-manager.virt-manager.desktop'
        'gnome-boxes.desktop' 'org.gnome.Boxes.desktop'
        'virtualbox.desktop' 'org.virtualbox.VirtualBox.desktop' 'virtualbox-qt.desktop'
        'vmware-workstation.desktop' 'vmplayer.desktop'
        'virt-viewer.desktop' 'org.virt-manager.virt-viewer.desktop'
        'remote-viewer.desktop'
        'vinagre.desktop' 'org.gnome.Vinagre.desktop'
        'remmina.desktop' 'org.remmina.Remmina.desktop'
        'rdesktop.desktop' 'xfreerdp.desktop'
        'docker-desktop.desktop'
        'qemu.desktop' 'kvirt.desktop'
        'rustdesk.desktop' 'com.rustdesk.RustDesk.desktop' 'org.rustdesk.RustDesk.desktop'
    )

    for app in "${virtualization_app_names[@]}"; do
        if result=$(find_app_desktop_file "$app"); then
            ambiente_virtual_apps+=("'$result'")
        fi
    done

    shopt -s nullglob
    for desktop_file in /usr/share/applications/*virt*.desktop \
                        /usr/share/applications/*virtual*.desktop \
                        /usr/share/applications/*vmware*.desktop \
                        /usr/share/applications/*qemu*.desktop \
                        /usr/share/applications/*boxes*.desktop \
                        /usr/share/applications/*remote-viewer*.desktop \
                        /usr/share/applications/*vinagre*.desktop \
                        /usr/share/applications/*remmina*.desktop \
                        /usr/share/applications/*rustdesk*.desktop \
                        /var/lib/snapd/desktop/applications/*rustdesk*.desktop \
                        /var/lib/flatpak/exports/share/applications/*rustdesk*.desktop \
                        "$HOME/.local/share/applications"/*virt*.desktop \
                        "$HOME/.local/share/applications"/*virtual*.desktop \
                        "$HOME/.local/share/applications"/*rustdesk*.desktop; do
        if [ -f "$desktop_file" ]; then
            local basename=$(basename "$desktop_file")
            if [[ ! " ${ambiente_virtual_apps[@]} " =~ " '$basename' " ]]; then
                ambiente_virtual_apps+=("'$basename'")
            fi
        fi
    done
    shopt -u nullglob

    ambiente_virtual_apps=($(echo "${ambiente_virtual_apps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    if [ ${#ambiente_virtual_apps[@]} -gt 0 ]; then
        local ambiente_virtual_apps_str=$(IFS=,; echo "${ambiente_virtual_apps[*]}")
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/AmbienteVirtual/ name 'Ambiente Virtual'
        gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/AmbienteVirtual/ apps "[${ambiente_virtual_apps_str}]"
        folder_ids+=("'AmbienteVirtual'")
        print_status "success" "Ambiente Virtual folder created with ${#ambiente_virtual_apps[@]} apps"
        print_status "config" "  Apps: ${ambiente_virtual_apps_str}"
    else
        print_status "warning" "No Ambiente Virtual apps found"
    fi
    
    # ==================== UPDATE FOLDER LIST ====================
    local ordered_folder_ids=()

    for folder in "'Sistema'" "'Seguranca'" "'Utilitarios'" "'Sharing'" "'IRPF'" "'DEV'" "'Ereader'" "'Office'" "'AmbienteVirtual'"; do
        for created_folder in "${folder_ids[@]}"; do
            if [ "$created_folder" = "$folder" ]; then
                ordered_folder_ids+=("$folder")
                break
            fi
        done
    done

    if [ ${#ordered_folder_ids[@]} -gt 0 ]; then
        local ordered_folder_ids_str=$(IFS=,; echo "${ordered_folder_ids[*]}")
        gsettings set org.gnome.desktop.app-folders folder-children "[${ordered_folder_ids_str}]"
        print_status "success" "App folders organized in custom order: ${ordered_folder_ids_str}"
    else
        print_status "warning" "No folders were created"
    fi
    
    print_status "info" "Application organization complete"
}

main() {
    if [ "$EUID" -eq 0 ]; then 
        print_status "error" "This script should NOT be run with sudo!"
        print_status "info" "Please run as: bash $0"
        exit 1
    fi
    
    print_status "info" "Starting Ubuntu appearance configuration"
    echo -e "${MAGENTA}========================================${NC}"
    
    set_dark_mode
    configure_terminal
    configure_mouse
    configure_dock
    set_ubuntu_ui_interface
    configure_workspaces
    apply_additional_tweaks
    configure_inactivity_time_lock
    configure_power_settings
    organize_app_folders
    
    echo -e "${MAGENTA}========================================${NC}"
    print_status "success" "All appearance settings configured successfully!"
    print_status "info" "Changes should take effect immediately. If not, try logging out and back in."
    print_status "info" "Open 'Mostrar aplicativos' to see your organized folders!"
}

# Execute main function
main