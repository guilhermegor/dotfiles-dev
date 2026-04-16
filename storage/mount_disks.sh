#!/usr/bin/env bash

set -euo pipefail

MOUNT_BASE="/mnt/auto"

OS_LABEL_REGEX='(efi|esp|boot|system|microsoft|windows|ubuntu|debian|fedora|arch|manjaro|mint|pop|kali|root)'
OS_PARTTYPE_REGEX='^(c12a7328-f81f-11d2-ba4b-00a0c93ec93b|e3c9e316-0b5c-4db8-817d-f92df00215ae|21686148-6449-6e6f-744e-656564454649)$'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="$HOME/toolchains_installation_$(date +%Y%m%d_%H%M%S).log"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_status() {
  local status="$1"
  local message="$2"

  case "$status" in
    success) echo -e "${GREEN}[✓]${NC} ${message}" ;;
    error)   echo -e "${RED}[✗]${NC} ${message}" >&2 ;;
    warning) echo -e "${YELLOW}[!]${NC} ${message}" ;;
    info)    echo -e "${BLUE}[i]${NC} ${message}" ;;
    section)
      echo -e "\n${MAGENTA}========================================${NC}"
      echo -e "${MAGENTA} $message${NC}"
      echo -e "${MAGENTA}========================================${NC}\n"
      ;;
    *) echo -e "[ ] ${message}" ;;
  esac

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$status] $message" >> "$LOG_FILE"
}

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

declare -A OS_DISKS

create_mount_base() {
  sudo mkdir -p "$MOUNT_BASE"
  print_status success "Base mount directory ready: $MOUNT_BASE"
}

get_parent_disk() {
  local dev="$1"
  local pkname
  pkname=$(lsblk -no PKNAME "$dev" 2>/dev/null || true)
  [[ -n "$pkname" ]] && echo "/dev/$pkname" || echo "$dev"
}

is_os_disk() {
  local disk="$1"
  [[ -n "${OS_DISKS[$disk]:-}" ]]
}

detect_os_disks() {
  print_status section "Detecting disks with operating systems"

  while read -r dev type _ fstype mountpoint partlabel label parttype; do
    [[ "$type" != "part" ]] && continue

    local disk
    disk=$(get_parent_disk "$dev")

    # Mounted system paths
    if [[ "$mountpoint" =~ ^/(|boot|boot/efi)$ ]]; then
      OS_DISKS["$disk"]=1
      continue
    fi

    # Known OS partition types (EFI, Linux root, etc.)
    if [[ -n "$parttype" && "$parttype" =~ $OS_PARTTYPE_REGEX ]]; then
      OS_DISKS["$disk"]=1
      continue
    fi

    # Labels strongly indicating OS
    local combined_labels
    combined_labels="${partlabel,,} ${label,,}"
    if [[ "$combined_labels" =~ $OS_LABEL_REGEX ]]; then
      OS_DISKS["$disk"]=1
      continue
    fi

  done < <(lsblk -rpn -o NAME,TYPE,PKNAME,FSTYPE,MOUNTPOINT,PARTLABEL,LABEL,PARTTYPE)

  for disk in "${!OS_DISKS[@]}"; do
    print_status warning "Skipping OS disk: $disk"
  done
}

get_label() {
  local dev="$1"
  local label
  label=$(lsblk -no LABEL "$dev" | tr ' ' '_')
  [[ -z "$label" ]] && label=$(basename "$dev")
  echo "$label"
}

mount_partition() {
  local dev="$1"
  local fstype="$2"

  local label mount_point
  label=$(get_label "$dev")
  mount_point="$MOUNT_BASE/$label"

  print_status info "Mounting $dev ($fstype) at $mount_point"
  sudo mkdir -p "$mount_point"
  sudo mount "$dev" "$mount_point"
  print_status success "Mounted $dev"
}

scan_and_mount() {
  detect_os_disks
  print_status section "Mounting non-OS partitions"

  lsblk -rpn -o NAME,FSTYPE,MOUNTPOINT,SIZE -b | while read -r dev fstype mountpoint size; do
    [[ -n "$mountpoint" ]] && continue
    [[ -z "$fstype" ]] && continue
    [[ -z "$size" ]] && continue
    [[ ! "$size" =~ ^[0-9]+$ ]] && continue

    local disk
    disk=$(get_parent_disk "$dev")

    if is_os_disk "$disk"; then
      continue
    fi

    # Skip tiny partitions (<10 GiB)
    if (( size < 10 * 1024 * 1024 * 1024 )); then
      print_status warning "Skipping small partition ($(numfmt --to=iec "$size")): $dev"
      continue
    fi

    mount_partition "$dev" "$fstype"
  done

  print_status success "All eligible partitions processed"
}

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

main() {
  create_mount_base
  scan_and_mount
  print_status info "Opening $MOUNT_BASE in file manager"
  xdg-open "$MOUNT_BASE" >/dev/null 2>&1 || true
}

main "$@"
