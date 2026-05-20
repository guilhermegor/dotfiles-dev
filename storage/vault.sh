#!/bin/bash

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# check if veracrypt is installed
if ! command -v veracrypt &> /dev/null; then
    print_status error "VeraCrypt is not installed. Please install it first."
    print_status info "You can install it with: sudo apt-get install veracrypt"
    exit 1
else
    print_status success "VeraCrypt is installed. Proceeding..."
fi

# list all storage devices
print_status warning "Available storage devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v "loop" | grep -v "rom"

# ask user to select a device
read -p "$(print_status info "Enter the device name you want to encrypt (e.g. sdb): ")" device

# verify the device exists
if [ ! -e "/dev/$device" ]; then
    print_status error "Device /dev/$device does not exist. Exiting."
    exit 1
fi

# check if device is mounted
mounted=$(mount | grep "/dev/$device" | wc -l)
if [ $mounted -gt 0 ]; then
    print_status warning "The device is currently mounted. It will be unmounted."
    sudo umount "/dev/$device"*
fi

# warn about data loss
print_status error "WARNING: This will erase ALL data on /dev/$device!"
while true; do
    read -p "$(print_status warning "Are you sure you want to continue? (y/n): ")" confirm
    case $confirm in
        [Yy]* ) break;;
        [Nn]* ) 
            print_status info "Operation cancelled by user."
            exit 0;;
        * ) print_status error "Please answer y or n.";;
    esac
done

# create partition table and single partition
print_status info "Creating partition table..."
sudo parted "/dev/$device" --script mklabel msdos
print_status info "Creating single partition..."
sudo parted "/dev/$device" --script mkpart primary 0% 100%

# encrypt the partition
print_status info "Starting encryption process for /dev/${device}1..."
sudo veracrypt --text --create "/dev/${device}1" \
    --volume-type normal \
    --filesystem FAT \
    --encryption AES \
    --hash SHA-512 \
    --random-source /dev/urandom \
    --password "$(read -sp "$(print_status info "Enter password: ")" pass; echo $pass)" \
    --pim 0 \
    --keyfiles "" \
    --quick

if [ $? -eq 0 ]; then
    print_status success "Encryption completed successfully!"
    print_status info "You can now mount the encrypted volume with:"
    print_status info "veracrypt --text /dev/${device}1"
else
    print_status error "Encryption failed. Please check the device and try again."
fi