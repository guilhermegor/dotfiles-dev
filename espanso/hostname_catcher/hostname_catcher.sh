#!/usr/bin/env bash
# hostname_catcher.sh - Get and display hostname information

set -e

echo "Hostname Information:"
echo "===================="

# Short hostname
short_hostname=$(hostname -s 2>/dev/null || hostname)
echo "Short hostname: $short_hostname"

# FQDN (fully qualified domain name)
fqdn=$(hostname -f 2>/dev/null || hostname)
echo "FQDN: $fqdn"

# Domain name
domain=$(hostname -d 2>/dev/null || echo "N/A")
echo "Domain: $domain"

# All hostnames/aliases
echo ""
echo "All hostnames:"
hostname -A 2>/dev/null | tr ' ' '\n' | grep -v '^$' | sed 's/^/  /' || echo "  $short_hostname"

echo ""
