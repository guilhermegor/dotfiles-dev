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

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_status "error" "This script must be run as root"
    exit 1
fi

# Main recovery function
recover_data() {
    local device="$1"
    local output_dir="$2"

    # Verify device exists
    if [ ! -e "$device" ]; then
        print_status "error" "Device $device does not exist"
        return 1
    fi

    # Create output directory
    mkdir -p "$output_dir" || {
        print_status "error" "Failed to create output directory $output_dir"
        return 1
    }

    print_status "info" "Starting data recovery from $device to $output_dir"

    # Step 1: Create disk image
    local image_file="$output_dir/disk_image.img"
    print_status "config" "Creating disk image for safer recovery..."
    
    if dd if="$device" of="$image_file" bs=4M status=progress; then
        print_status "success" "Disk image created successfully"
    else
        print_status "error" "Failed to create disk image"
        return 1
    fi

    # Step 2: Try mounting first
    local mount_point="$output_dir/mount"
    mkdir -p "$mount_point"
    
    print_status "config" "Attempting to mount partitions..."
    
    # Try kpartx first
    if command -v kpartx >/dev/null; then
        kpartx -av "$image_file"
        local loop_device=$(losetup --list | grep "$image_file" | awk '{print $1}')
        
        if [ -n "$loop_device" ]; then
            local partitions=($(ls ${loop_device}p* 2>/dev/null))
            
            if [ ${#partitions[@]} -gt 0 ]; then
                for part in "${partitions[@]}"; do
                    print_status "info" "Found partition $part"
                    fs_type=$(blkid -o value -s TYPE "$part" 2>/dev/null)
                    
                    if [ -n "$fs_type" ]; then
                        print_status "config" "Attempting to mount $part (filesystem: $fs_type)"
                        if mount -o ro "$part" "$mount_point" 2>/dev/null; then
                            print_status "success" "Mounted $part successfully"
                            # Copy files
                            print_status "info" "Copying files from $part..."
                            mkdir -p "$output_dir/recovered_${part##*/}"
                            cp -r "$mount_point"/* "$output_dir/recovered_${part##*/}/"
                            umount "$mount_point"
                            break
                        fi
                    fi
                done
            fi
            kpartx -d "$image_file"
        fi
    fi

    # Step 3: Use photorec for deep recovery
    print_status "info" "Starting deep file recovery with photorec..."
    
    if command -v photorec >/dev/null; then
        print_status "config" "Launching photorec (follow the prompts)"
        photorec "$image_file"
        
        # Photorec saves to current directory by default
        if [ -d "recup_dir" ]; then
            mv "recup_dir" "$output_dir/photorec_recovery"
            print_status "success" "Photorec recovery completed"
        else
            print_status "warning" "Photorec didn't recover any files"
        fi
    else
        print_status "error" "photorec not found. Install testdisk package."
    fi

    # Step 4: Clean up
    print_status "info" "Cleaning up..."
    rm -f "$image_file"
    
    print_status "success" "Recovery process completed. Check $output_dir for recovered files."
}

# Main script execution
print_status "info" "Data Recovery Tool"
print_status "warning" "WARNING: Do NOT save recovered files back to the same drive!"

# List available drives
print_status "config" "Available storage devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v 'loop'

# Get user input
read -p "$(echo -e ${BLUE}"[i] Enter the device to recover from (e.g., /dev/sdb): "${NC})" device
read -p "$(echo -e ${BLUE}"[i] Enter output directory for recovered files: "${NC})" output_dir

# Validate input
if [ ! -b "$device" ]; then
    print_status "error" "$device is not a valid block device"
    exit 1
fi

# Check if device is mounted
if mount | grep -q "$device"; then
    print_status "warning" "$device is currently mounted"
    read -p "$(echo -e ${YELLOW}"[!] Unmount $device before proceeding? (y/n): "${NC})" unmount_choice
    if [ "$unmount_choice" = "y" ]; then
        umount "$device"* 2>/dev/null
        print_status "success" "Unmounted $device"
    else
        print_status "error" "Cannot proceed with mounted device"
        exit 1
    fi
fi

# Start recovery
recover_data "$device" "$output_dir"