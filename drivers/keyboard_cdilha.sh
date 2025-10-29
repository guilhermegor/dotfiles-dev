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

configure_keyboard() {
    print_status "info" "Starting keyboard configuration..."
    
    # 1. Check current keyboard layout
    print_status "info" "Checking current keyboard layout..."
    local current_layout=$(gsettings get org.gnome.desktop.input-sources sources | grep -oP "'[^']*'" | head -1 | tr -d "'")
    
    if [[ "$current_layout" == *"intl"* || "$current_layout" == *"intern"* ]]; then
        print_status "success" "International keyboard layout detected: $current_layout"
    else
        print_status "warning" "Non-international layout detected: $current_layout"
        print_status "info" "For proper cedilla support, please use a layout with 'intl.' or 'intern.' in its name"
    fi
    
    # 2. Configure cedilla fix
    print_status "info" "Configuring cedilla support..."
    
    # Create backup of environment file
    if [ ! -f /etc/environment ]; then
        sudo touch /etc/environment
        print_status "config" "Created new /etc/environment file"
    else
        sudo cp /etc/environment /etc/environment.bak
        print_status "config" "Created backup at /etc/environment.bak"
    fi
    
    # Check if configuration already exists
    if grep -q "GTK_IM_MODULE=cedilla" /etc/environment && grep -q "QT_IM_MODULE=cedilla" /etc/environment; then
        print_status "success" "Cedilla configuration already exists"
    else
        # Add cedilla configuration
        echo -e "\n# Cedilla fix configuration" | sudo tee -a /etc/environment >/dev/null
        echo "GTK_IM_MODULE=cedilla" | sudo tee -a /etc/environment >/dev/null
        echo "QT_IM_MODULE=cedilla" | sudo tee -a /etc/environment >/dev/null
        print_status "success" "Added cedilla configuration to /etc/environment"
    fi
    
    # 3. Verify configuration
    print_status "info" "Current configuration:"
    print_status "config" "Keyboard layout: $current_layout"
    print_status "config" "Environment file contents:"
    cat /etc/environment | while read -r line; do
        print_status "config" "$line"
    done
    
    print_status "success" "Keyboard configuration complete!"
    print_status "info" "Please log out and back in for changes to take effect"
}

# Main execution
echo -e "${MAGENTA}----------------------------------------${NC}"
print_status "info" "Starting Ubuntu Keyboard Configuration"
echo -e "${MAGENTA}----------------------------------------${NC}"

configure_keyboard

echo -e "${MAGENTA}----------------------------------------${NC}"
print_status "info" "Configuration finished"
print_status "info" "You may need to restart your session for changes to apply"
echo -e "${MAGENTA}----------------------------------------${NC}"