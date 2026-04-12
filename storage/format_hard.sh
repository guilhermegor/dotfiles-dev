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
    print_status "error" "This script must be run as root. Please use sudo."
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}         USB Format Tool                ${NC}"
echo -e "${BLUE}========================================${NC}"
print_status "warning" "Warning: This will erase all data on the selected drive!"
echo ""

# List available disks
print_status "info" "Available block devices:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
echo ""

# Get device
read -rp "Enter the USB device to format (e.g. sdc): " DEVICE
TARGET="/dev/$DEVICE"

# Verify device
if [ ! -b "$TARGET" ]; then
    print_status "error" "$TARGET does not exist or is not a block device."
    exit 1
fi

# Confirm action
print_status "warning" "You are about to format $TARGET"
lsblk -o NAME,SIZE,MODEL "$TARGET"
echo ""
read -rp "Are you absolutely sure? (y/n): " -n 1 CONFIRM
echo ""
if [[ ! "${CONFIRM,,}" =~ ^[y]$ ]]; then
    print_status "success" "Operation cancelled."
    exit 0
fi

# Unmount any mounted partitions
print_status "info" "Unmounting partitions..."
for PART in $(ls "${TARGET}"* | grep -v "$TARGET$"); do
    umount "$PART" 2>/dev/null && print_status "success" "Unmounted $PART" || print_status "warning" "$PART was not mounted"
done

# Wipe first 10MB
print_status "info" "Wiping partition table..."
dd if=/dev/zero of="$TARGET" bs=1M count=10 status=progress

# Ask for filesystem type
echo ""
print_status "config" "Choose filesystem type:"
echo "  1) EXT4  - Linux only (recommended for Ubuntu and other Linux distros)"
echo "  2) FAT32 - Compatible with Linux, Windows, and macOS (limited to 4GB max file size)"
echo "  3) NTFS  - Compatible with Windows and Linux (good for large files)"
read -rp "Enter choice [1-3]: " FORMAT_OPTION

# Create partition and format
case "$FORMAT_OPTION" in
    1)
        print_status "config" "Creating 1 EXT4 partition for Linux systems..."
        {
            echo o
            echo n
            echo p
            echo 1
            echo
            echo
            echo w
        } | fdisk "$TARGET"
        partprobe "$TARGET"
        print_status "info" "Formatting as EXT4..."
        mkfs.ext4 "${TARGET}1"
        ;;
    2)
        print_status "config" "Creating 1 FAT32 partition for cross-platform compatibility..."
        {
            echo o
            echo n
            echo p
            echo 1
            echo
            echo
            echo t
            echo c
            echo w
        } | fdisk "$TARGET"
        partprobe "$TARGET"
        print_status "info" "Formatting as FAT32..."
        mkfs.vfat -F 32 "${TARGET}1"
        ;;
    3)
        print_status "config" "Creating 1 NTFS partition for Windows and Linux systems..."
        {
            echo o
            echo n
            echo p
            echo 1
            echo
            echo
            echo t
            echo 7
            echo w
        } | fdisk "$TARGET"
        partprobe "$TARGET"
        print_status "info" "Formatting as NTFS..."
        mkfs.ntfs -f "${TARGET}1"
        ;;
    *)
        print_status "error" "Invalid option selected."
        exit 1
        ;;
esac

# Verify filesystem
print_status "info" "Verifying filesystem..."
fsck -p "${TARGET}1" && print_status "success" "Filesystem verified" || print_status "warning" "Filesystem verification warning"

echo ""
print_status "success" "Format complete. ${TARGET}1 is ready for use."
print_status "info" "You may now safely remove the USB drive."
