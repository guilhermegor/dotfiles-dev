#!/bin/bash

# Ventoy Automated Installer for Ubuntu (CLI)
# Author: Your Name
# Version: 1.1

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
VENTOY_VERSION="1.1.05"
VENTOY_URL="https://github.com/ventoy/Ventoy/releases/download/v$VENTOY_VERSION/ventoy-$VENTOY_VERSION-linux.tar.gz"
TEMP_DIR="$HOME/Download/ventoy_temp"

# Function: Print status messages
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

# Function: Check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_status "error" "Please run as root or with sudo."
        exit 1
    fi
}

# Function: Prepare temporary directory
prepare_temp_dir() {
    print_status "info" "Creating temporary directory..."
    mkdir -p "$TEMP_DIR" || {
        print_status "error" "Failed to create temp directory."
        exit 1
    }
    cd "$TEMP_DIR" || exit
}

# Function: Download Ventoy
download_ventoy() {
    print_status "info" "Downloading Ventoy $VENTOY_VERSION..."
    wget -q --show-progress "$VENTOY_URL" -O "ventoy-$VENTOY_VERSION-linux.tar.gz" || {
        print_status "error" "Failed to download Ventoy."
        exit 1
    }
    print_status "success" "Download completed."
}

# Function: Extract Ventoy
extract_ventoy() {
    print_status "info" "Extracting Ventoy..."
    tar -xzf "ventoy-$VENTOY_VERSION-linux.tar.gz" || {
        print_status "error" "Failed to extract Ventoy."
        exit 1
    }
    print_status "success" "Extraction completed."
}

# Function: List available disks
list_disks() {
    print_status "info" "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -v 'loop'
    echo ""
}

# Function: Get target disk from user
get_target_disk() {
    read -p "$(echo -e "${CYAN}[→]${NC} Enter the target disk (e.g., /dev/sdX): ")" TARGET_DISK
    
    # Verify disk exists
    if [ ! -b "$TARGET_DISK" ]; then
        print_status "error" "$TARGET_DISK does not exist or is not a block device."
        exit 1
    fi
}

# Function: Check and unmount partitions
unmount_partitions() {
    MOUNTED_PARTITIONS=$(mount | grep "$TARGET_DISK" | awk '{print $1}')
    
    if [ -n "$MOUNTED_PARTITIONS" ]; then
        print_status "warning" "The following partitions on $TARGET_DISK are mounted:"
        echo "$MOUNTED_PARTITIONS"
        
        read -p "$(echo -e "${YELLOW}[!]${NC} Unmount all partitions? (y/N): ")" CONFIRM_UNMOUNT
        
        if [[ "$CONFIRM_UNMOUNT" =~ [yY] ]]; then
            for PARTITION in $MOUNTED_PARTITIONS; do
                umount "$PARTITION" || {
                    print_status "error" "Failed to unmount $PARTITION."
                    exit 1
                }
            done
            print_status "success" "Unmounted all partitions."
        else
            print_status "error" "Aborting. Ventoy requires unmounted partitions."
            exit 1
        fi
    fi
}

# Function: Install Ventoy
install_ventoy() {
    print_status "info" "Installing Ventoy to $TARGET_DISK..."
    cd "ventoy-$VENTOY_VERSION" || exit
    ./Ventoy2Disk.sh -i "$TARGET_DISK" || {
        print_status "error" "Failed to install Ventoy."
        exit 1
    }
    print_status "success" "Ventoy installed successfully on $TARGET_DISK!"
}

# Function: Clean up
cleanup() {
    print_status "info" "Cleaning up..."
    cd "$HOME" || exit
    rm -rf "$TEMP_DIR"
    print_status "success" "Temporary files removed."
}

# Function: Main execution
main() {
    print_status "info" "Starting Ventoy installation..."
    check_root
    prepare_temp_dir
    download_ventoy
    extract_ventoy
    list_disks
    get_target_disk
    unmount_partitions
    install_ventoy
    cleanup
    
    print_status "success" "Process completed!"
    echo -e "${GREEN}Copy ISO files to the Ventoy partition and reboot to use.${NC}"
}

# Execute main function
main