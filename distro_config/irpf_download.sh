#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Print colored status messages
print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "success") echo -e "${GREEN}[✓]${NC} ${message}" ;;
        "error") echo -e "${RED}[✗]${NC} ${message}" >&2 ;;
        "warning") echo -e "${YELLOW}[!]${NC} ${message}" ;;
        "info") echo -e "${BLUE}[i]${NC} ${message}" ;;
        "config") echo -e "${CYAN}[→]${NC} ${message}" ;;
        "debug") echo -e "${MAGENTA}[»]${NC} ${message}" ;;
        *) echo -e "[ ] ${message}" ;;
    esac
}

# Get the actual user's home directory (even when run with sudo)
get_user_home() {
    local user=$(whoami)
    if [ "$user" == "root" ]; then
        # If running with sudo, get the original user from SUDO_USER
        if [ -n "$SUDO_USER" ]; then
            user="$SUDO_USER"
        else
            # If actually root, use /root
            echo "/root"
            return
        fi
    fi
    eval echo ~"$user"
}

# Get current year and calculate previous two years
current_year=$(date +%Y)
prev_year=$((current_year - 1))
prev_prev_year=$((current_year - 2))

print_status "info" "Preparing to download and install IRPF programs for ${current_year}, ${prev_year}, and ${prev_prev_year}"

# Get the correct user's home directory
user_home=$(get_user_home)
downloads_dir="$user_home/Downloads"

if [ ! -d "$downloads_dir" ]; then
    print_status "warning" "Downloads directory doesn't exist, creating it..."
    if ! mkdir -p "$downloads_dir"; then
        print_status "error" "Failed to create Downloads directory"
        exit 1
    fi
    # Ensure the directory has the correct ownership
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:" "$downloads_dir"
    fi
fi

print_status "debug" "Attempting to change to: $downloads_dir"
if cd "$downloads_dir" 2>/dev/null; then
    print_status "success" "Changed to Downloads directory ($(pwd))"
else
    print_status "error" "Could not change to Downloads directory ($downloads_dir)"
    print_status "debug" "Current directory: $(pwd)"
    exit 1
fi

# Base URL for the downloads
base_url="https://downloadirpf.receita.fazenda.gov.br/irpf"

# Download and install function
download_and_install_irpf() {
    local year=$1
    print_status "config" "Processing IRPF for year ${year}..."
    
    # Construct the download URL
    download_url="${base_url}/${year}/irpf/arquivos/IRPF${year}Linux-x86_64v1.3.sh.bin"
    print_status "debug" "Download URL: ${download_url}"
    
    # Download the file
    if wget -q --show-progress "$download_url" -O "IRPF${year}.bin"; then
        print_status "success" "Downloaded IRPF ${year}"
        
        # Make it executable
        if chmod +x "IRPF${year}.bin"; then
            print_status "success" "Made IRPF${year}.bin executable"
            
            # Run the installer automatically (non-interactive)
            print_status "info" "Starting installation for IRPF ${year}..."
            if ./IRPF${year}.bin --mode unattended; then
                print_status "success" "Successfully installed IRPF ${year}"
                # Ensure installed files have correct ownership
                if [ -n "$SUDO_USER" ]; then
                    chown -R "$SUDO_USER:" "$user_home/Programas RFB/IRPF${year}"
                fi
            else
                print_status "error" "Installation failed for IRPF ${year}"
            fi
        else
            print_status "error" "Failed to make IRPF${year}.bin executable"
        fi
    else
        print_status "error" "Failed to download IRPF for ${year}"
        print_status "debug" "The program might not be available yet or the URL has changed"
    fi
}

# Process all three years
print_status "info" "Starting automated download and installation..."
download_and_install_irpf "$current_year"
download_and_install_irpf "$prev_year"
download_and_install_irpf "$prev_prev_year"

print_status "success" "Process completed"
echo -e "${YELLOW}Note:${NC} IRPF programs are typically installed in $user_home/Programas RFB/"