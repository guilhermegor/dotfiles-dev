#!/bin/bash

# colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # no color

# function to print colored text
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# check if veracrypt is installed
if ! command -v veracrypt &> /dev/null; then
    print_status $RED "VeraCrypt is not installed. Please install it first."
    print_status $BLUE "You can install it with: sudo apt-get install veracrypt"
    exit 1
else
    print_status $GREEN "VeraCrypt is installed. Proceeding..."
fi

# list all storage devices
print_status $YELLOW "Available storage devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v "loop" | grep -v "rom"

# ask user to select a device
read -p "$(print_status $BLUE "Enter the device name you want to encrypt (e.g. sdb): ")" device

# verify the device exists
if [ ! -e "/dev/$device" ]; then
    print_status $RED "Device /dev/$device does not exist. Exiting."
    exit 1
fi

# check if device is mounted
mounted=$(mount | grep "/dev/$device" | wc -l)
if [ $mounted -gt 0 ]; then
    print_status $YELLOW "The device is currently mounted. It will be unmounted."
    sudo umount "/dev/$device"*
fi

# warn about data loss
print_status $RED "WARNING: This will erase ALL data on /dev/$device!"
while true; do
    read -p "$(print_status $YELLOW "Are you sure you want to continue? (y/n): ")" confirm
    case $confirm in
        [Yy]* ) break;;
        [Nn]* ) 
            print_status $BLUE "Operation cancelled by user."
            exit 0;;
        * ) print_status $RED "Please answer y or n.";;
    esac
done

# create partition table and single partition
print_status $BLUE "Creating partition table..."
sudo parted "/dev/$device" --script mklabel msdos
print_status $BLUE "Creating single partition..."
sudo parted "/dev/$device" --script mkpart primary 0% 100%

# encrypt the partition
print_status $BLUE "Starting encryption process for /dev/${device}1..."
sudo veracrypt --text --create "/dev/${device}1" \
    --volume-type normal \
    --filesystem FAT \
    --encryption AES \
    --hash SHA-512 \
    --random-source /dev/urandom \
    --password "$(read -sp "$(print_status $BLUE "Enter password: ")" pass; echo $pass)" \
    --pim 0 \
    --keyfiles "" \
    --quick

if [ $? -eq 0 ]; then
    print_status $GREEN "Encryption completed successfully!"
    print_status $BLUE "You can now mount the encrypted volume with:"
    print_status $BLUE "veracrypt --text /dev/${device}1"
else
    print_status $RED "Encryption failed. Please check the device and try again."
fi