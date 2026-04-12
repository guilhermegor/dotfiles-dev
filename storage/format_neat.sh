#!/bin/bash

# --- Color definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# --- Print colored status messages ---
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

# --- Functions ---

validate_label() {
    local label="$1"
    # remove any surrounding quotes if present
    label=$(echo "$label" | sed "s/^['\"]//;s/['\"]\$//")
    local length=$(echo -n "$label" | wc -c)
    if [ "$length" -gt 11 ]; then
        print_status "error" "Label '$label' is too long (max 11 characters)."
        exit 1
    fi
    if echo "$label" | grep -q '[^[:alnum:] _-]'; then
        print_status "warning" "Label '$label' contains special characters that might cause issues."
    fi
    echo "$label"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_status "error" "This script must be run as root (use sudo)."
        exit 1
    fi
}

validate_device() {
    local device="$1" 
    if [ ! -b "$device" ]; then
        print_status "error" "$device is not a valid block device."
        exit 1
    fi
    local is_removable=$(lsblk -dno HOTPLUG "$device")
    if [ "$is_removable" -ne 1 ]; then
        print_status "error" "$device is not a removable (external USB) drive."
        exit 1
    fi
}

check_mounted() {
    local device="$1"
    if findmnt "$device" >/dev/null || findmnt "${device}1" >/dev/null; then
        print_status "warning" "The following partitions are mounted:"
        lsblk -o NAME,MOUNTPOINT "$device" | grep -v "NAME\|MOUNTPOINT"
        return 1
    fi
    return 0
}

unmount_partitions() {
    local device="$1"
    print_status "info" "Attempting to unmount all partitions of $device..."
    local mounted_partitions=$(lsblk -lno NAME,MOUNTPOINT "$device" | awk '$2 != "" {print $1}')
    if [ -z "$mounted_partitions" ]; then
        print_status "success" "No partitions to unmount."
        return 0
    fi
    for partition in $mounted_partitions; do
        local mount_point=$(lsblk -lno MOUNTPOINT "/dev/$partition")
        print_status "info" "Unmounting /dev/$partition (mounted at $mount_point)..."
        umount "/dev/$partition" 2>/dev/null
        if [ $? -ne 0 ]; then
            print_status "warning" "Gentle unmount failed, attempting lazy unmount..."
            umount -l "/dev/$partition" 2>/dev/null
        fi
        if [ $? -ne 0 ]; then
            print_status "error" "Failed to unmount /dev/$partition"
            print_status "info" "This partition might be in use. Please:"
            print_status "info" "1. Close any applications using files on this drive"
            print_status "info" "2. Check for open terminals in the mount point"
            print_status "info" "3. Try manual unmount: sudo umount /dev/$partition"
            return 1
        fi
    done
    if check_mounted "$device"; then
        return 0
    else
        print_status "error" "Some partitions could not be unmounted, please do it manually."
        return 1
    fi
}

create_partition() {
    local device="$1"
    print_status "info" "Creating new partition on $device..."
    (
        echo 'o'  # New DOS partition table
        echo 'n'  # New partition
        echo 'p'  # Primary
        echo '1'  # Partition 1
        echo ''   # First sector (default)
        echo ''   # Last sector (default)
        echo 't'  # Change type
        echo 'c'  # FAT32 (LBA)
        echo 'w'  # Write changes
    ) | fdisk "$device" >/dev/null 2>&1 || {
        print_status "error" "Partitioning failed."
        exit 1
    }
}

format_partition() {
    local partition="$1"
    local label="$2"
    local fs_type="$3"
    local encrypt="$4"
    
    case "$fs_type" in
        "fat32")
            print_status "info" "Formatting $partition as FAT32 (label: '$label')..."
            mkfs.fat -F32 -n "$label" "$partition" || {
                print_status "error" "FAT32 formatting failed."
                exit 1
            }
            ;;
        "ntfs")
            print_status "info" "Formatting $partition as NTFS (label: '$label')..."
            mkfs.ntfs -Q -L "$label" "$partition" || {
                print_status "error" "NTFS formatting failed."
                exit 1
            }
            ;;
        "ext4")
            print_status "info" "Formatting $partition as ext4 (label: '$label')..."
            mkfs.ext4 -L "$label" "$partition" || {
                print_status "error" "ext4 formatting failed."
                exit 1
            }
            ;;
    esac
    
    if [ "$encrypt" = "yes" ]; then
        encrypt_partition "$partition" "$label"
    fi
}

encrypt_partition() {
    local partition="$1"
    local label="$2"
    
    print_status "info" "Setting up encryption for $partition..."
    
    # Check if cryptsetup is available
    if ! command -v cryptsetup >/dev/null; then
        print_status "error" "cryptsetup not found. Please install it first."
        exit 1
    fi
    
    # Setup LUKS encryption
    cryptsetup -q -y -v luksFormat "$partition" || {
        print_status "error" "LUKS encryption setup failed."
        exit 1
    }
    
    # Open the encrypted device
    cryptsetup open "$partition" "${label}_crypt" || {
        print_status "error" "Failed to open encrypted device."
        exit 1
    }
    
    # Create filesystem on the encrypted device
    mkfs.ext4 "/dev/mapper/${label}_crypt" || {
        print_status "error" "Failed to create filesystem on encrypted device."
        exit 1
    }
    
    print_status "success" "Encryption setup complete. Use 'cryptsetup open $partition ${label}_crypt' to access."
}

safe_eject() {
    local device="$1"
    print_status "info" "Preparing to safely eject $device..."
    print_status "info" "Syncing all filesystems..."
    sync
    if [ ! -b "$device" ]; then
        print_status "success" "Device $device not found - may already be ejected."
        return 0
    fi
    if command -v udisksctl >/dev/null 2>&1; then
        print_status "info" "Using udisksctl to power off..."
        udisksctl power-off -b "$device" && return 0
    fi
    print_status "warning" "Manual ejection required:"
    print_status "info" "1. Wait for all activity LEDs to stop blinking"
    print_status "info" "2. Physically disconnect the device"
}

show_filesystem_info() {
    echo -e "${CYAN}=== Filesystem Options ===${NC}"
    echo -e "${YELLOW}FAT32:${NC}"
    echo -e "  ${GREEN}✓${NC} Widely compatible (Windows, Mac, Linux, devices)"
    echo -e "  ${GREEN}✓${NC} Good for small files and flash drives"
    echo -e "  ${RED}✗${NC} 4GB file size limit"
    echo -e "  ${RED}✗${NC} No built-in encryption"
    echo
    echo -e "${YELLOW}NTFS:${NC}"
    echo -e "  ${GREEN}✓${NC} Good Windows compatibility"
    echo -e "  ${GREEN}✓${NC} No file size limits"
    echo -e "  ${RED}✗${NC} Mac (read-only without drivers)"
    echo -e "  ${RED}✗${NC} Limited Linux compatibility"
    echo
    echo -e "${YELLOW}ext4:${NC}"
    echo -e "  ${GREEN}✓${NC} Best for Linux systems"
    echo -e "  ${GREEN}✓${NC} Supports large files and permissions"
    echo -e "  ${RED}✗${NC} Windows requires additional software"
    echo -e "  ${RED}✗${NC} Mac requires additional software"
    echo
    echo -e "${MAGENTA}Encryption adds security but:${NC}"
    echo -e "  ${GREEN}✓${NC} Protects sensitive data"
    echo -e "  ${RED}✗${NC} Adds complexity to access"
    echo -e "  ${RED}✗${NC} May impact performance"
    echo
}

select_filesystem() {
    local device="$1"
    
    show_filesystem_info
    
    PS3="$(print_status "config" "Select filesystem type: ")"
    options=("FAT32 (recommended for compatibility)" "NTFS (recommended for Windows)" "ext4 (recommended for Linux)" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "FAT32 (recommended for compatibility)")
                FS_TYPE="fat32"
                break
                ;;
            "NTFS (recommended for Windows)")
                FS_TYPE="ntfs"
                break
                ;;
            "ext4 (recommended for Linux)")
                FS_TYPE="ext4"
                break
                ;;
            "Quit")
                print_status "info" "Operation cancelled by user."
                exit 0
                ;;
            *) 
                print_status "error" "Invalid option. Please try again."
                ;;
        esac
    done
    
    # Ask about encryption
    if [ "$FS_TYPE" != "fat32" ]; then
        read -p "$(print_status "config" "Enable encryption? (y/n): ")" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ENCRYPT="yes"
            print_status "info" "Encryption will be enabled. You'll need to set a password."
        else
            ENCRYPT="no"
            print_status "info" "Encryption will not be enabled."
        fi
    else
        print_status "warning" "FAT32 doesn't support native encryption. Consider NTFS or ext4 for encryption."
        ENCRYPT="no"
    fi
}

# --- Main script ---

check_root

# Validate arguments
if [ "$#" -lt 1 ]; then
    echo -e "${CYAN}Usage:${NC} sudo $0 <device> [label]"
    echo -e "${CYAN}Example:${NC} sudo $0 /dev/sdX \"MyDrive\""
    exit 1
fi

DEVICE="$1"
CURRENT_LABEL="${2:-USB_DRIVE}"
NEW_LABEL=$(validate_label "$CURRENT_LABEL")

validate_device "$DEVICE"

if ! check_mounted "$DEVICE"; then
    if ! unmount_partitions "$DEVICE"; then
        exit 1
    fi
fi

select_filesystem "$DEVICE"

create_partition "$DEVICE"
format_partition "${DEVICE}1" "$NEW_LABEL" "$FS_TYPE" "$ENCRYPT"

print_status "success" "External drive $DEVICE formatted with label '$NEW_LABEL' as $FS_TYPE."
if [ "$ENCRYPT" = "yes" ]; then
    print_status "success" "The drive is encrypted. Remember your password!"
fi

safe_eject "$DEVICE"