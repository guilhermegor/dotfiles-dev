#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No color

# VM storage directory (update this if needed)
VM_DIR="/mnt/drive_1/vms"

# Function to print status messages
print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success") echo -e "${GREEN}[✓]${NC} ${message}" ;;
        "error") echo -e "${RED}[✗]${NC} ${message}" >&2 ;;
        "warning") echo -e "${YELLOW}[!]${NC} ${message}" ;;
        "info") echo -e "${BLUE}[i]${NC} ${message}" ;;
        *) echo -e "[ ] ${message}" ;;
    esac
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_status "error" "This script must be run as root (use sudo)."
    exit 1
fi

# List available VMs (checks both libvirt and VM_DIR)
list_vms() {
    print_status "info" "Checking for VMs in libvirt and $VM_DIR..."
    
    # Check libvirt-registered VMs
    print_status "info" "Libvirt-registered VMs:"
    virsh list --all | awk 'NR>2 && !/^$/ {print $2}' | while read -r vm; do
        print_status "info" "  - $vm (registered in libvirt)"
    done

    # Check unregistered VMs in VM_DIR
    print_status "info" "Unregistered VMs (in $VM_DIR):"
    find "$VM_DIR" -name "*.qcow2" -exec basename {} .qcow2 \; | while read -r vm; do
        if ! virsh list --all --name | grep -q "^${vm}$"; then
            print_status "warning" "  - $vm (not registered in libvirt)"
        fi
    done
}

# Register and start a VM
start_vm() {
    local vm_name="$1"
    local vm_disk="${VM_DIR}/${vm_name}.qcow2"

    # Check if disk exists
    if [ ! -f "$vm_disk" ]; then
        print_status "error" "VM disk '$vm_disk' not found."
        exit 1
    fi

    # Check if VM is registered in libvirt
    if ! virsh list --all --name | grep -q "^${vm_name}$"; then
        print_status "warning" "VM '$vm_name' is not registered in libvirt. Registering now..."
        
        # Define a basic XML config (adjust as needed)
        tmp_xml=$(mktemp)
        cat > "$tmp_xml" <<EOF
<domain type='kvm'>
  <name>$vm_name</name>
  <memory unit='KiB'>$(( 8 * 1024 * 1024 ))</memory> <!-- 8GB RAM -->
  <vcpu placement='static'>4</vcpu> <!-- 4 CPU cores -->
  <os>
    <type arch='x86_64'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$vm_disk'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <graphics type='spice'/>
    <video>
      <model type='virtio'/>
    </video>
  </devices>
</domain>
EOF
        # Register the VM
        virsh define "$tmp_xml"
        rm "$tmp_xml"
        print_status "success" "VM '$vm_name' registered in libvirt."
    fi

    # Start the VM
    print_status "info" "Starting $vm_name..."
    virsh start "$vm_name"
    
    if [ $? -eq 0 ]; then
        print_status "success" "$vm_name started successfully."
        print_status "info" "To open the VM GUI, run: ${CYAN}virt-manager${NC}"
    else
        print_status "error" "Failed to start $vm_name."
    fi
}

# Main function
main() {
    list_vms
    
    read -rp "Enter the name of the VM you want to start (e.g., 'win11' or 'ubuntu'): " vm_choice
    
    case "$vm_choice" in
        win11|ubuntu)
            start_vm "$vm_choice"
            ;;
        *)
            print_status "error" "Invalid VM name. Choose either 'win11' or 'ubuntu'."
            exit 1
            ;;
    esac
}

main