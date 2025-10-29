#!/bin/bash

# SSD Detection and Motherboard Capacity Analysis Script

echo "SSD and Storage Capacity Detection Script"
echo "----------------------------------------"

# Check if script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges. Please run with sudo."
    exit 1
fi

# Function to display human-readable sizes
human_readable() {
    local size=$1
    local units=('B' 'KB' 'MB' 'GB' 'TB' 'PB')
    local unit=0
    while ((size > 1024 && unit < ${#units[@]}-1)); do
        size=$(echo "scale=2; $size/1024" | bc)
        ((unit++))
    done
    echo "$size ${units[$unit]}"
}

# 1. Detect available SATA ports
echo -e "\n[1] SATA Controller Information:"
sata_ports=$(lspci | grep -i 'sata' | head -n 1)
if [ -z "$sata_ports" ]; then
    echo "No SATA controllers found."
else
    echo "SATA Controller: $sata_ports"
    max_sata=$(dmesg | grep -i 'ahci.*ports' | grep -oP '\d+(?= ports)' | head -n 1)
    if [ -n "$max_sata" ]; then
        echo "Maximum SATA ports supported: $max_sata"
    else
        echo "Could not determine exact number of SATA ports."
    fi
fi

# 2. Detect available M.2/NVMe slots
echo -e "\n[2] NVMe/M.2 Slot Information:"
nvme_slots=$(lspci | grep -i 'nvme' | wc -l)
if [ "$nvme_slots" -gt 0 ]; then
    echo "Detected $nvme_slots NVMe devices currently connected."
    echo "Note: This shows connected devices, not total available slots."
fi

# Check for M.2 slots in dmidecode (may not be accurate on all systems)
m2_slots=$(dmidecode -t slot | grep -i 'M.2' | wc -l)
if [ "$m2_slots" -gt 0 ]; then
    echo "Motherboard appears to have $m2_slots M.2 slots (from dmidecode)."
else
    echo "No M.2 slots detected (or information not available)."
fi

# 3. Check maximum drive size support
echo -e "\n[3] Maximum Drive Size Support:"

# Check kernel block layer limits
max_kernel_size=$(cat /proc/sys/dev/block/*/queue/max_hw_sectors_kb 2>/dev/null | sort -nr | head -n 1)
if [ -n "$max_kernel_size" ]; then
    max_kernel_size_bytes=$((max_kernel_size * 1024))
    echo "Kernel block layer supports at least: $(human_readable $max_kernel_size_bytes)"
else
    echo "Could not determine kernel block layer limits."
fi

# Check filesystem limits (ext4 example)
echo "Common filesystem limits:"
echo "  - ext4: ~16 TB (theoretical 1 EB)"
echo "  - XFS: ~8 EB"
echo "  - NTFS: ~256 TB"
echo "  - FAT32: ~2 TB (for bootable drives)"

# 4. Check currently connected storage devices
echo -e "\n[4] Currently Connected Storage Devices:"
lsblk -d -o NAME,MODEL,SIZE,ROTA,TRAN | grep -v '^loop'

# 5. Calculate theoretical total capacity
echo -e "\n[5] Theoretical Total Capacity:"

# Estimate based on SATA ports
if [ -n "$max_sata" ]; then
    # Assuming 16TB per SATA port (common maximum for consumer boards)
    sata_total=$((max_sata * 16 * 1024 * 1024 * 1024 * 1024))  # 16TB in bytes
    echo "Estimated SATA total capacity: $(human_readable $sata_total) (assuming $max_sata ports at 16TB each)"
fi

# Estimate based on NVMe
if [ "$m2_slots" -gt 0 ]; then
    # Assuming 4TB per NVMe drive (common large capacity)
    nvme_total=$((m2_slots * 4 * 1024 * 1024 * 1024 * 1024))  # 4TB in bytes
    echo "Estimated NVMe total capacity: $(human_readable $nvme_total) (assuming $m2_slots slots at 4TB each)"
fi

# Final notes
echo -e "\nNotes:"
echo "- These are theoretical maximums. Actual limits depend on:"
echo "  * Motherboard chipset and BIOS limitations"
echo "  * Operating system and filesystem used"
echo "  * Drive availability in the market"
echo "- For accurate slot information, consult your motherboard manual"
echo "- Modern motherboards typically support:"
echo "  * Per drive: Up to 16TB for SATA, 4-8TB for NVMe (consumer models)"
echo "  * Total: Often limited by chipset (e.g., Z690 supports ~6 SATA + 3-4 NVMe)"

exit 0