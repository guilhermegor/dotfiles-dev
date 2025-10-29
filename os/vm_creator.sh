#!/bin/bash

# color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # no color

# vm configuration
RAM="8192" # 8GB ram for each vm
CORES="2"  # 2 CPU cores for each vm

print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success") echo -e "${GREEN}[✓]${NC} ${message}" ;;
        "error") echo -e "${RED}[✗]${NC} ${message}" >&2 ;;
        "warning") echo -e "${YELLOW}[!]${NC} ${message}" ;;
        "info") echo -e "${BLUE}[i]${NC} ${message}" ;;
        "config") echo -e "${CYAN}[→]${NC} ${message}" ;;
        *) echo -e "[ ] ${message}" ;;
    esac
}

choose_target_drive() {
    print_status "info" "Mounted file systems:"
    df -hT | grep '^/dev/' | awk '{print $1, "->", $7, "(" $2 ",", $6 " used)"}'

    echo
    read -rp "Enter the full path where VMs should be stored (e.g., /mnt/drive_1): " USER_MOUNT
    if [ ! -d "$USER_MOUNT" ]; then
        print_status "error" "Mount point '$USER_MOUNT' does not exist."
        exit 1
    fi

    VM_DIR="${USER_MOUNT}/vms"
    WIN11_VM="${VM_DIR}/win11_vm"
    UBUNTU_VM="${VM_DIR}/ubuntu_vm"
    mkdir -p "$VM_DIR"
    print_status "success" "Using '$VM_DIR' as the VM directory"
}

ask_for_iso_paths() {
    echo
    read -rp "Enter the full path to the Windows 11 ISO file: " WIN11_ISO
    if [ ! -f "$WIN11_ISO" ]; then
        print_status "error" "Windows 11 ISO not found at '$WIN11_ISO'"
        exit 1
    fi

    read -rp "Enter the full path to the Ubuntu ISO file: " UBUNTU_ISO
    if [ ! -f "$UBUNTU_ISO" ]; then
        print_status "error" "Ubuntu ISO not found at '$UBUNTU_ISO'"
        exit 1
    fi
}

check_dependencies() {
    print_status "info" "Checking dependencies..."
    if ! command -v virt-install &> /dev/null; then
        print_status "error" "virt-install not found. Installing libvirt and related tools..."
        sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager
        sudo systemctl enable --now libvirtd
    fi
    print_status "success" "Dependencies verified"
}

create_vm_disk() {
    local vm_name="$1"
    local size="$2"
    print_status "info" "Creating disk for ${vm_name} (${size}GB)..."
    qemu-img create -f qcow2 "${VM_DIR}/${vm_name}.qcow2" "${size}G"
    print_status "success" "Disk created at ${VM_DIR}/${vm_name}.qcow2"
}

create_windows_vm() {
    print_status "config" "Creating Windows 11 VM..."
    create_vm_disk "win11" 64

    virt-install \
        --name win11 \
        --ram $RAM \
        --vcpus $CORES \
        --disk path="${WIN11_VM}.qcow2",bus=virtio \
        --os-type windows \
        --os-variant win11 \
        --network bridge=virbr0,model=virtio \
        --graphics spice \
        --cdrom "$WIN11_ISO" \
        --boot uefi \
        --machine q35 \
        --tpm backend.type=emulator,backend.version=2.0 \
        --disk path=/usr/share/OVMF/OVMF_CODE.fd,device=floppy \
        --noautoconsole

    print_status "success" "Windows 11 VM created successfully"
}

create_ubuntu_vm() {
    print_status "config" "Creating Ubuntu VM..."
    create_vm_disk "ubuntu" 20

    virt-install \
        --name ubuntu \
        --ram $RAM \
        --vcpus $CORES \
        --disk path="${UBUNTU_VM}.qcow2",bus=virtio \
        --os-type linux \
        --os-variant ubuntu22.04 \
        --network bridge=virbr0,model=virtio \
        --graphics spice \
        --cdrom "$UBUNTU_ISO" \
        --boot uefi \
        --extra-args 'console=ttyS0,115200n8 serial' \
        --noautoconsole

    print_status "success" "Ubuntu VM created successfully"
}

main() {
    if [ "$(id -u)" -ne 0 ]; then
        print_status "error" "This script must be run as root"
        exit 1
    fi

    choose_target_drive
    ask_for_iso_paths
    check_dependencies
    create_windows_vm
    create_ubuntu_vm

    print_status "success" "Both VMs have been created successfully!"
    print_status "info" "You can manage them using:"
    print_status "info" "  sudo virsh list --all"
    print_status "info" "  sudo virt-manager"
}

main
