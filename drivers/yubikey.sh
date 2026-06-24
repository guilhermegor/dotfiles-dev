#!/bin/bash
#
# drivers/yubikey.sh
#
# YubiKey support for Ubuntu/Debian. Covers four use cases the user opted into:
#   1. 2FA / TOTP codes   → Yubico Authenticator (Flatpak) + pcscd
#   2. Manage the key     → ykman CLI (yubikey-manager) + ykpersonalize udev rules
#   3. GPG / SSH signing  → gnupg + scdaemon + pcscd (smart-card / CCID)
#   4. Login / sudo 2FA   → libpam-yubico (installed only — NOT auto-wired; see note)
#
# Design notes:
#   - PAM is intentionally install-only. Misconfiguring /etc/pam.d can lock you
#     out of login and sudo, so configure_pam_guidance() only prints the manual
#     steps and the lockout warning — it never edits PAM files.
#   - scdaemon (GnuPG) and pcscd both arbitrate the smart-card interface and can
#     conflict. We surface this as guidance rather than editing scdaemon.conf.
#   - State-mutating commands go through run_or_echo so DRY_RUN=1 previews them.

# Source shared print_status + color vars + command_exists + run_or_echo.
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# --- Constants ---
YUBICO_VENDOR_ID="1050"                       # Yubico USB vendor id (lsusb)
AUTHENTICATOR_APP_ID="com.yubico.yubioath"    # Yubico Authenticator on Flathub
FLATHUB_REPO_URL="https://flathub.org/repo/flathub.flatpakrepo"

# Core packages installed via apt (one per line for readable diffs).
APT_PACKAGES=(
    pcscd                  # PC/SC smart-card daemon (OATH, PIV, FIDO over CCID)
    pcsc-tools             # pcsc_scan and friends — handy for verification
    scdaemon               # GnuPG smart-card daemon (GPG/SSH on the key)
    gnupg                  # gpg itself (usually present; pinned for completeness)
    yubikey-manager        # ykman CLI — configure FIDO2/PIV/OATH/firmware
    yubikey-personalization # ykpersonalize + 69-yubikey.rules udev rules
    libpam-yubico          # pam_yubico.so — login/sudo 2FA (install only)
)

# --- Helpers ---

# Package-level idempotency check. command_exists is unreliable for daemons and
# libraries (pcscd lives in /usr/sbin, libpam-yubico ships no binary), so query
# dpkg's database directly.
is_pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# --- Core Functions ---

# Warn (do not fail) when no YubiKey is on the USB bus — software installs fine
# without the key present; the user just can't test until it is.
detect_yubikey() {
    print_status "info" "Looking for a connected YubiKey on the USB bus..."
    if lsusb | grep -qi "${YUBICO_VENDOR_ID}:"; then
        print_status "success" "YubiKey detected on the USB bus"
        return 0
    fi
    print_status "warning" "No YubiKey detected (vendor ${YUBICO_VENDOR_ID}) — continuing anyway"
    print_status "info" "Reseat the key into a working USB port before testing below."
}

# Install the apt package set, one at a time so a single bad package degrades to
# a warning instead of aborting the whole transaction.
install_apt_packages() {
    print_status "config" "Installing YubiKey apt packages..."
    run_or_echo sudo apt-get update || {
        print_status "error" "apt-get update failed"
        return 1
    }

    local pkg
    for pkg in "${APT_PACKAGES[@]}"; do
        if is_pkg_installed "$pkg"; then
            print_status "info" "$pkg already installed"
            continue
        fi
        print_status "info" "Installing $pkg..."
        if run_or_echo sudo apt-get install -y "$pkg"; then
            print_status "success" "$pkg installed"
        else
            print_status "warning" "Failed to install $pkg — continuing"
        fi
    done
}

# Enable and start the PC/SC daemon, which mediates OATH/PIV/FIDO access for
# ykman and Yubico Authenticator. Verify it actually came up.
enable_pcscd() {
    print_status "config" "Enabling the pcscd smart-card service..."
    run_or_echo sudo systemctl enable --now pcscd || {
        print_status "warning" "Could not enable pcscd via systemd"
        return 0
    }

    if systemctl is-active --quiet pcscd; then
        print_status "success" "pcscd is running"
    else
        print_status "warning" "pcscd is not active — OATH/PIV features may not work"
    fi
}

# Yubico Authenticator (GUI) has no official .deb; Flatpak is the vendor-blessed
# Linux package and our preferred method after .deb. Ensure flatpak + flathub,
# then install the app idempotently.
install_yubico_authenticator() {
    print_status "config" "Installing Yubico Authenticator (Flatpak)..."

    if ! command_exists flatpak; then
        print_status "info" "flatpak not present — installing it..."
        run_or_echo sudo apt-get install -y flatpak || {
            print_status "warning" "Could not install flatpak — skipping Yubico Authenticator"
            return 0
        }
    fi

    run_or_echo sudo flatpak remote-add --if-not-exists flathub "$FLATHUB_REPO_URL" || {
        print_status "warning" "Could not add the flathub remote — skipping Yubico Authenticator"
        return 0
    }

    if flatpak info "$AUTHENTICATOR_APP_ID" >/dev/null 2>&1; then
        print_status "info" "Yubico Authenticator already installed"
        return 0
    fi

    if run_or_echo sudo flatpak install -y flathub "$AUTHENTICATOR_APP_ID"; then
        print_status "success" "Yubico Authenticator installed ($AUTHENTICATOR_APP_ID)"
    else
        print_status "warning" "Failed to install Yubico Authenticator via Flatpak"
    fi
}

# yubikey-personalization ships /lib/udev/rules.d/69-yubikey.rules granting the
# logged-in user non-root access to the device. Reload so it applies without a
# reboot.
reload_udev_rules() {
    print_status "config" "Reloading udev rules for device access..."
    run_or_echo sudo udevadm control --reload-rules || {
        print_status "warning" "Could not reload udev rules"
        return 0
    }
    run_or_echo sudo udevadm trigger || print_status "warning" "udevadm trigger failed"
    print_status "success" "udev rules reloaded"
}

# A YubiKey's USB product id is a firmware-reported bitmask of the enabled
# interfaces (a hub cannot alter it): the low hex digit is OTP(1) | FIDO(2) |
# CCID(4). CCID is the smart-card interface that OATH (Authenticator), PIV and
# OpenPGP all ride on, so three of the four use cases need it. 1050:0402 is
# FIDO-only (CCID off); 1050:0407 is OTP+FIDO+CCID (all on). Detect a limited
# key and offer to enable everything via ykman.
configure_yubikey_interfaces() {
    print_status "section" "YUBIKEY USB INTERFACES (CCID)"

    local pid
    pid="$(lsusb | grep -oiE "${YUBICO_VENDOR_ID}:04[0-9a-f]{2}" | head -n1 | cut -d: -f2)"
    if [ -z "$pid" ]; then
        print_status "warning" "No YubiKey on the bus — skipping interface check"
        print_status "info" "After plugging it in, run: ykman config usb --enable-all"
        return 0
    fi

    case "${pid: -1}" in
        4|5|6|7)
            print_status "success" "CCID (smart card) already enabled (PID ${YUBICO_VENDOR_ID}:$pid)"
            return 0
            ;;
        1|2|3)
            print_status "warning" "Key is in limited mode (PID ${YUBICO_VENDOR_ID}:$pid) — CCID is DISABLED"
            print_status "info" "OATH 2FA, GPG/SSH and PIV need CCID; only FIDO/U2F works right now."
            ;;
        *)
            print_status "warning" "Unrecognised YubiKey PID ${YUBICO_VENDOR_ID}:$pid — check 'ykman info' manually"
            return 0
            ;;
    esac

    if ! command_exists ykman; then
        print_status "warning" "ykman not installed — cannot enable interfaces automatically"
        print_status "info" "Install it without sudo: pipx install yubikey-manager"
        print_status "info" "Then run: ykman config usb --enable-all   (and replug the key)"
        return 0
    fi

    if [ ! -t 0 ]; then
        print_status "info" "Non-interactive run — not changing interfaces automatically."
        print_status "info" "Run manually: ykman config usb --enable-all"
        return 0
    fi

    local answer
    read -r -p "Enable all USB interfaces (OTP+FIDO+CCID) now? [Y/n] " answer
    case "$answer" in
        [nN]*)
            print_status "info" "Left unchanged. Run later: ykman config usb --enable-all"
            return 0
            ;;
    esac

    print_status "config" "Enabling all USB interfaces (touch the key if it blinks)..."
    if run_or_echo ykman config usb --enable-all --force; then
        print_status "success" "Interfaces enabled — UNPLUG and REPLUG the key to apply"
        print_status "info" "Verify: lsusb | grep ${YUBICO_VENDOR_ID}  → expect ...:0407"
    else
        print_status "warning" "ykman config failed — try manually: ykman config usb --enable-all"
    fi
}

# PAM is install-only. Wiring pam_yubico into /etc/pam.d incorrectly locks you
# out of login and sudo, so we print the steps instead of editing anything.
configure_pam_guidance() {
    print_status "section" "LOGIN / SUDO 2FA (libpam-yubico) — MANUAL STEP"
    print_status "warning" "PAM is NOT auto-configured — a mistake here can lock you out of login and sudo."
    echo -e "${YELLOW}Configure it only with a root shell open as a safety net:${NC}"
    echo -e "  1. Open a separate ${CYAN}sudo -s${NC} root shell and keep it open until you've verified login."
    echo -e "  2. Register the key (challenge-response, offline):"
    echo -e "       ${CYAN}ykman otp chalresp --generate 2${NC}        # program slot 2"
    echo -e "       ${CYAN}pamu2fcfg > ~/.config/Yubico/u2f_keys${NC}  # for FIDO/U2F-based PAM"
    echo -e "  3. Add ${CYAN}auth required pam_yubico.so mode=challenge-response${NC} to the"
    echo -e "     relevant file in ${CYAN}/etc/pam.d/${NC} (e.g. sudo, login, or common-auth)."
    echo -e "  4. Test ${CYAN}sudo true${NC} in a NEW terminal before closing the root shell."
    echo -e "${BLUE}Docs:${NC} https://developers.yubico.com/yubico-pam/"
}

verify_installation() {
    print_status "info" "Verifying installation..."
    local verification_passed=true

    if command_exists ykman; then
        local ykman_version
        ykman_version="$(ykman --version 2>/dev/null)"
        print_status "success" "ykman available: ${ykman_version:-unknown version}"
    else
        print_status "error" "ykman not found"
        verification_passed=false
    fi

    if systemctl is-active --quiet pcscd; then
        print_status "success" "pcscd service active"
    else
        print_status "warning" "pcscd service not active"
    fi

    if flatpak info "$AUTHENTICATOR_APP_ID" >/dev/null 2>&1; then
        print_status "success" "Yubico Authenticator present"
    else
        print_status "warning" "Yubico Authenticator not present"
    fi

    if command_exists ykman; then
        print_status "info" "Connected keys (empty if none plugged in):"
        ykman list 2>/dev/null || print_status "info" "No YubiKey currently connected"
    fi

    if $verification_passed; then
        print_status "success" "Verification complete"
        return 0
    fi
    print_status "warning" "Verification completed with issues"
    return 1
}

display_summary() {
    print_status "section" "YUBIKEY SETUP SUMMARY"
    echo -e "  • ${CYAN}2FA / TOTP${NC}     → launch ${GREEN}Yubico Authenticator${NC} (flatpak: ${AUTHENTICATOR_APP_ID})"
    echo -e "  • ${CYAN}Manage key${NC}     → ${GREEN}ykman info${NC}, ${GREEN}ykman list${NC}, ${GREEN}ykman fido info${NC}"
    echo -e "  • ${CYAN}GPG / SSH${NC}      → ${GREEN}gpg --card-status${NC} (scdaemon + pcscd)"
    echo -e "  • ${CYAN}Login / sudo${NC}   → libpam-yubico installed; see the manual step above"
    echo
    echo -e "${YELLOW}Heads-up — scdaemon vs pcscd:${NC} both can claim the smart-card interface."
    echo -e "  If ${CYAN}gpg --card-status${NC} fails while pcscd runs, add ${CYAN}disable-ccid${NC} to"
    echo -e "  ${CYAN}~/.gnupg/scdaemon.conf${NC} (use GnuPG's own driver), then ${CYAN}gpgconf --kill scdaemon${NC}."
    echo
    echo -e "${BLUE}Note:${NC} Yubico Authenticator was installed as a Flatpak and is NOT placed in a"
    echo -e "  GNOME app-folder (this is a drivers/ script, not the install_lib registry)."
    echo -e "  Ask if you want a registry entry so it lands in a folder automatically."
}

# --- Main Execution ---
main() {
    print_status "info" "Starting YubiKey setup"

    detect_yubikey
    install_apt_packages || exit 1
    enable_pcscd
    install_yubico_authenticator
    reload_udev_rules
    configure_yubikey_interfaces
    configure_pam_guidance
    verify_installation || true

    print_status "success" "YubiKey setup completed"
    display_summary
}

main "$@"
