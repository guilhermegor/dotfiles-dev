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
        *)
            echo -e "[ ] ${message}"
            ;;
    esac
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
    gsettings set org.gnome.shell.extensions.dash-to-dock autohide true
    gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
    
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
    
    # Set screen blank time when plugged in (optional - keeping default or set to never)
    # gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
    # gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    
    local BATTERY_TIMEOUT=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout)
    print_status "success" "Screen will turn off after $BATTERY_TIMEOUT seconds (30 min) on battery"
}

main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then 
        print_status "error" "This script should NOT be run with sudo!"
        print_status "info" "Please run as: bash $0"
        exit 1
    fi
    
    print_status "info" "Starting Ubuntu appearance configuration"
    echo -e "${MAGENTA}----------------------------------------${NC}"
    
    set_dark_mode
    configure_terminal
    configure_dock
    set_ubuntu_ui_interface
    configure_workspaces
    apply_additional_tweaks
    configure_inactivity_time_lock
    configure_power_settings
    
    echo -e "${MAGENTA}----------------------------------------${NC}"
    print_status "success" "All appearance settings configured successfully!"
    print_status "info" "Changes should take effect immediately. If not, try logging out and back in."
}

# Execute main function
main