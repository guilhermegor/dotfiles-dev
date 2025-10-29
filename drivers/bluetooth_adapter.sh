#!/bin/bash

# Colors for status messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success") echo -e "${GREEN}[✓]${NC} ${message}" ;;
        "error") echo -e "${RED}[✗]${NC} ${message}" >&2 ;;
        "warning") echo -e "${YELLOW}[!]${NC} ${message}" ;;
        *) echo -e "[ ] ${message}" ;;
    esac
}

# Check USB Bluetooth adapter
print_status "info" "Checking Bluetooth adapter..."
lsusb | grep -i bluetooth
if [ $? -eq 0 ]; then
    print_status "success" "Bluetooth adapter detected"
else
    print_status "warning" "No Bluetooth adapter detected - continuing installation anyway"
fi

# Install Synaptic if not already installed
if ! command -v synaptic >/dev/null 2>&1; then
    print_status "info" "Installing Synaptic package manager..."
    sudo apt update
    sudo apt install -y synaptic
    if [ $? -eq 0 ]; then
        print_status "success" "Synaptic installed successfully"
    else
        print_status "error" "Failed to install Synaptic"
        exit 1
    fi
else
    print_status "success" "Synaptic is already installed"
fi

# List of Bluetooth packages to install
BLUETOOTH_PACKAGES=(
    bluez
    bluez-cups
    bluez-obexd
    bluez-tools
    libbluetooth3
    libkf5bluezqt-data
    libkf5bluezqt6
    python3-bluez
    qml-module-org-kde-bluezqt
)

# Install Bluetooth packages
print_status "info" "Installing Bluetooth packages..."
for pkg in "${BLUETOOTH_PACKAGES[@]}"; do
    print_status "info" "Installing $pkg..."
    sudo apt install -y "$pkg"
    if [ $? -eq 0 ]; then
        print_status "success" "$pkg installed successfully"
    else
        print_status "warning" "Failed to install $pkg - continuing anyway"
    fi
done

# Enable and start Bluetooth service
print_status "info" "Enabling Bluetooth service..."
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

# Verify Bluetooth service status
if systemctl is-active --quiet bluetooth; then
    print_status "success" "Bluetooth service is running"
else
    print_status "error" "Bluetooth service failed to start"
fi

# Final check
print_status "info" "Installation complete. Checking Bluetooth status..."
bluetoothctl show

print_status "success" "Bluetooth setup completed!"