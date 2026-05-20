#!/bin/bash
#
# distro_config/install_lib/browsers.sh
#
# Web browsers. Sourced by install_programs.sh after _common.sh.
# Depends on: print_status, command_exists, install_package, setup_flatpak,
#             $PACKAGE_MANAGER, $INSTALL_CMD, $DOWNLOADS_DIR

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "browsers.sh is meant to be sourced, not executed." >&2
    exit 1
fi

# ============================================================================
# INSTALL FUNCTIONS
# ============================================================================

install_chrome() {
    print_status "section" "GOOGLE CHROME"

    if command_exists google-chrome; then
        print_status "info" "Chrome already installed"
        return 0
    fi

    cd "$DOWNLOADS_DIR"

    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Downloading Google Chrome..."
            run_or_echo wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

            print_status "info" "Installing Google Chrome..."
            run_or_echo sudo dpkg -i google-chrome-stable_current_amd64.deb
            run_or_echo sudo apt-get install -f -y
            ;;
        dnf|yum)
            print_status "info" "Adding Google Chrome repository..."
            run_or_echo sudo dnf install -y fedora-workstation-repositories
            run_or_echo sudo dnf config-manager --set-enabled google-chrome
            $INSTALL_CMD google-chrome-stable
            ;;
        pacman)
            print_status "info" "Installing Google Chrome from AUR..."
            if command_exists yay; then
                run_or_echo yay -S --noconfirm google-chrome
            else
                print_status "warning" "Please install google-chrome from AUR manually or install yay first"
            fi
            ;;
        zypper)
            print_status "info" "Downloading Google Chrome..."
            run_or_echo wget https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
            $INSTALL_CMD google-chrome-stable_current_x86_64.rpm
            ;;
    esac

    print_status "success" "Google Chrome installed"
    cd - > /dev/null
}

install_opera() {
    print_status "section" "OPERA BROWSER"

    if flatpak list 2>/dev/null | grep -q com.opera.Opera; then
        print_status "info" "Opera already installed"
        return 0
    fi

    setup_flatpak
    run_or_echo flatpak install -y flathub com.opera.Opera
    print_status "success" "Opera installed"
}

install_vivaldi() {
    print_status "section" "VIVALDI BROWSER"

    if flatpak list 2>/dev/null | grep -q com.vivaldi.Vivaldi; then
        print_status "info" "Vivaldi already installed"
        return 0
    fi

    setup_flatpak
    run_or_echo flatpak install -y flathub com.vivaldi.Vivaldi
    print_status "success" "Vivaldi installed"
}

install_edge() {
    print_status "section" "MICROSOFT EDGE"

    if flatpak list 2>/dev/null | grep -q com.microsoft.Edge; then
        print_status "info" "Microsoft Edge already installed"
        return 0
    fi

    setup_flatpak
    run_or_echo flatpak install -y flathub com.microsoft.Edge
    print_status "success" "Microsoft Edge installed"
}

install_brave() {
    print_status "section" "BRAVE BROWSER"

    if command_exists brave-browser || command_exists brave; then
        print_status "info" "Brave already installed"
        return 0
    fi

    case "$PACKAGE_MANAGER" in
        apt)
            sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
                https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
https://brave-browser-apt-release.s3.brave.com/ stable main" \
                | sudo tee /etc/apt/sources.list.d/brave-browser.list
            sudo apt-get update -y
            $INSTALL_CMD brave-browser
            ;;
        dnf|yum)
            run_or_echo sudo dnf config-manager --add-repo \
                https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            $INSTALL_CMD brave-browser
            ;;
        pacman)
            if command_exists yay; then
                run_or_echo yay -S --noconfirm brave-bin
            else
                print_status "warning" "Install brave-bin from AUR manually or install yay first"
            fi
            ;;
        zypper)
            run_or_echo sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            run_or_echo sudo zypper addrepo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            $INSTALL_CMD brave-browser
            ;;
    esac

    print_status "success" "Brave installed"
}

# ============================================================================
# REGISTRY
# ============================================================================
# Schema: "func:label:gnome_folder:desktop_file"
# Empty gnome_folder = unpinned (orchestrator decides default). Browsers stay
# unfoldered today (some pinned to dock by ubuntu_workspace.sh), but the slot
# is reserved for future use.

INSTALL_REGISTRY+=(
    "install_chrome:Google Chrome::google-chrome.desktop"
    "install_opera:Opera Browser::com.opera.Opera.desktop"
    "install_vivaldi:Vivaldi Browser::com.vivaldi.Vivaldi.desktop"
    "install_edge:Microsoft Edge::com.microsoft.Edge.desktop"
    "install_brave:Brave Browser::brave-browser.desktop"
)
