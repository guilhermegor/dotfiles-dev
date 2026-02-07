#!/usr/bin/env bash
# ipv4_catcher.sh - Get and display local IPv4 addresses

set -e

echo "Local IPv4 Addresses:"
echo "===================="

# Get all IPv4 addresses (exclude loopback)
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | while read -r ipv4; do
    echo "  $ipv4"
done

# Try to get the primary/default route IP
default_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' || echo "")
if [ -n "$default_ip" ]; then
    echo ""
    echo "Primary IP (default route): $default_ip"
fi

# Try to get public IP (optional)
if command -v curl >/dev/null 2>&1; then
    echo ""
    echo -n "Public IP (via ifconfig.me): "
    curl -s --max-time 2 ifconfig.me || echo "Unable to fetch"
fi

echo ""
