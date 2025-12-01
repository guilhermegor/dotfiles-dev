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

configure_keyboard_layouts() {
    print_status "info" "Configuring keyboard layouts..."
    
    # Define the three layouts
    local layouts="[('xkb', 'br'), ('xkb', 'us'), ('xkb', 'us+intl')]"
    
    # Set the keyboard layouts
    gsettings set org.gnome.desktop.input-sources sources "$layouts"
    
    if [ $? -eq 0 ]; then
        print_status "success" "Keyboard layouts configured:"
        print_status "config" "  1. Português (Brasil)"
        print_status "config" "  2. Inglês (EUA)"
        print_status "config" "  3. Inglês (EUA, intern. alt.)"
    else
        print_status "error" "Failed to configure keyboard layouts"
        return 1
    fi
}

configure_cedilla() {
    print_status "info" "Configuring cedilla support..."
    
    # Create backup of environment file
    if [ ! -f /etc/environment ]; then
        sudo touch /etc/environment
        print_status "config" "Created new /etc/environment file"
    else
        if [ ! -f /etc/environment.bak ]; then
            sudo cp /etc/environment /etc/environment.bak
            print_status "config" "Created backup at /etc/environment.bak"
        fi
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
}

configure_us_cedilla() {
    print_status "info" "Configuring US English layout with cedilla support..."
    
    # GTK configuration for cedilla in US layout
    local gtk_compose_dir="$HOME/.config/gtk-3.0"
    local gtk_compose_file="$gtk_compose_dir/Compose"
    
    # Create directory if it doesn't exist
    mkdir -p "$gtk_compose_dir"
    
    # Create Compose file for cedilla support
    cat > "$gtk_compose_file" << 'EOF'
# Custom Compose sequences for cedilla in US layout
include "%L"

# Cedilla support for US keyboard
<dead_acute> <C> : "Ç" Ccedilla
<dead_acute> <c> : "ç" ccedilla
<apostrophe> <C> : "Ç" Ccedilla
<apostrophe> <c> : "ç" ccedilla
EOF
    
    if [ $? -eq 0 ]; then
        print_status "success" "Created GTK Compose file for cedilla support"
    else
        print_status "error" "Failed to create GTK Compose file"
        return 1
    fi
    
    # Configure IBus settings for cedilla
    if command -v ibus &> /dev/null; then
        print_status "info" "Configuring IBus for cedilla support..."
        
        # Set compose key behavior
        gsettings set org.freedesktop.ibus.general use-system-keyboard-layout true 2>/dev/null || true
        
        print_status "success" "IBus configured for cedilla support"
    fi
}

verify_configuration() {
    print_status "info" "Verifying configuration..."
    
    # Check keyboard layouts
    local current_layouts=$(gsettings get org.gnome.desktop.input-sources sources)
    print_status "config" "Current keyboard layouts: $current_layouts"
    
    # Check environment configuration
    if [ -f /etc/environment ]; then
        print_status "config" "Environment file contents:"
        grep -E "GTK_IM_MODULE|QT_IM_MODULE" /etc/environment | while read -r line; do
            print_status "config" "  $line"
        done
    fi
    
    # Check Compose file
    if [ -f "$HOME/.config/gtk-3.0/Compose" ]; then
        print_status "success" "GTK Compose file exists"
    else
        print_status "warning" "GTK Compose file not found"
    fi
}

# Main execution
echo -e "${MAGENTA}========================================${NC}"
echo -e "${MAGENTA}  Ubuntu Keyboard Configuration Script  ${NC}"
echo -e "${MAGENTA}========================================${NC}"
echo ""

configure_keyboard_layouts

if [ $? -eq 0 ]; then
    configure_cedilla
    configure_us_cedilla
    verify_configuration
    
    echo ""
    echo -e "${MAGENTA}========================================${NC}"
    print_status "success" "Configuration completed successfully!"
    echo -e "${MAGENTA}========================================${NC}"
    echo ""
    print_status "info" "Next steps:"
    print_status "config" "1. Log out and log back in for changes to take full effect"
    print_status "config" "2. Use Super+Space to switch between keyboard layouts"
    print_status "config" "3. In US English layout, use ' + c to type ç (cedilla)"
    print_status "config" "4. You can also use Right Alt (AltGr) + , + c in some contexts"
    echo ""
else
    echo ""
    echo -e "${MAGENTA}========================================${NC}"
    print_status "error" "Configuration encountered errors"
    echo -e "${MAGENTA}========================================${NC}"
    exit 1
fi