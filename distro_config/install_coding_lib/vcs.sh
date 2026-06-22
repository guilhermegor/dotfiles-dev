#!/bin/bash
#
# distro_config/install_coding_lib/vcs.sh
#
# Version control + GitHub workflow tools. Sourced by install_coding.sh.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "vcs.sh is meant to be sourced, not executed." >&2
    exit 1
fi

install_github_cli() {
    print_status "section" "GITHUB CLI"

    if command_exists gh; then
        print_status "info" "GitHub CLI already installed"
        return 0
    fi

    print_status "info" "Adding GitHub CLI repository..."
    (type -p wget >/dev/null || (sudo apt update && run_or_echo sudo apt-get install -y wget)) \
        && sudo mkdir -p -m 755 /etc/apt/keyrings \
        && out=$(mktemp) && run_or_echo wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        && cat $out | run_or_echo sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
        && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | run_or_echo sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt update \
        && run_or_echo sudo apt install -y gh

    gh --version >> "$LOG_FILE"
    print_status "success" "GitHub CLI installed"
}

install_act() {
    print_status "section" "ACT (RUN GITHUB ACTIONS LOCALLY)"

    if command_exists act; then
        print_status "info" "act already installed"
        return 0
    fi

    if command_exists brew; then
        print_status "info" "Installing act via Homebrew..."
        if run_or_echo brew install act &>> "$LOG_FILE"; then
            print_status "success" "act installed via Homebrew"
            return 0
        fi
        print_status "warning" "Homebrew install failed, falling back to GitHub release..."
    fi

    local arch download_arch tmp_dir tarball_url

    arch=$(uname -m)
    case "$arch" in
        x86_64)  download_arch="x86_64" ;;
        aarch64) download_arch="arm64" ;;
        armv7l)  download_arch="armv7" ;;
        *)
            print_status "warning" "Unsupported architecture for act: $arch"
            return 1
            ;;
    esac

    tmp_dir=$(mktemp -d)
    tarball_url="https://github.com/nektos/act/releases/latest/download/act_Linux_${download_arch}.tar.gz"

    print_status "info" "Downloading act from GitHub releases..."
    if wget -O "$tmp_dir/act.tar.gz" "$tarball_url" 2>>"$LOG_FILE" || \
       run_or_echo curl -L -o "$tmp_dir/act.tar.gz" "$tarball_url" 2>>"$LOG_FILE"; then
        tar -xzf "$tmp_dir/act.tar.gz" -C "$tmp_dir"
        run_or_echo sudo mv "$tmp_dir/act" /usr/local/bin/act
        run_or_echo sudo chmod +x /usr/local/bin/act
    else
        print_status "error" "Failed to download act from GitHub releases"
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"

    if command_exists act; then
        act --version >> "$LOG_FILE"
        print_status "success" "act installed: $(act --version 2>/dev/null)"
    else
        print_status "error" "act installation failed — check $LOG_FILE"
        return 1
    fi
}

install_gitleaks() {
    print_status "section" "GITLEAKS (SECRET SCANNER)"

    if command_exists gitleaks; then
        print_status "info" "gitleaks already installed"
        return 0
    fi

    if command_exists brew; then
        print_status "info" "Installing gitleaks via Homebrew..."
        if run_or_echo brew install gitleaks &>> "$LOG_FILE"; then
            print_status "success" "gitleaks installed via Homebrew"
            return 0
        fi
        print_status "warning" "Homebrew install failed, falling back to GitHub release..."
    fi

    local arch download_arch tmp_dir latest_url latest_tag version tarball_url

    arch=$(uname -m)
    case "$arch" in
        x86_64)  download_arch="x64" ;;
        aarch64) download_arch="arm64" ;;
        armv7l)  download_arch="armv7" ;;
        *)
            print_status "warning" "Unsupported architecture for gitleaks: $arch"
            return 1
            ;;
    esac

    latest_url="https://github.com/gitleaks/gitleaks/releases/latest"
    latest_tag=$(curl -sLI -o /dev/null -w '%{url_effective}' "$latest_url" 2>>"$LOG_FILE" | sed 's|.*/tag/||')
    if [ -z "$latest_tag" ]; then
        print_status "error" "Could not resolve latest gitleaks version"
        return 1
    fi
    version="${latest_tag#v}"

    tmp_dir=$(mktemp -d)
    tarball_url="https://github.com/gitleaks/gitleaks/releases/download/${latest_tag}/gitleaks_${version}_linux_${download_arch}.tar.gz"

    print_status "info" "Downloading gitleaks ${latest_tag} from GitHub releases..."
    if wget -O "$tmp_dir/gitleaks.tar.gz" "$tarball_url" 2>>"$LOG_FILE" || \
       run_or_echo curl -L -o "$tmp_dir/gitleaks.tar.gz" "$tarball_url" 2>>"$LOG_FILE"; then
        tar -xzf "$tmp_dir/gitleaks.tar.gz" -C "$tmp_dir"
        run_or_echo sudo mv "$tmp_dir/gitleaks" /usr/local/bin/gitleaks
        run_or_echo sudo chmod +x /usr/local/bin/gitleaks
    else
        print_status "error" "Failed to download gitleaks from GitHub releases"
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"

    if command_exists gitleaks; then
        gitleaks version >> "$LOG_FILE"
        print_status "success" "gitleaks installed: $(gitleaks version 2>/dev/null)"
    else
        print_status "error" "gitleaks installation failed — check $LOG_FILE"
        return 1
    fi
}

install_shellcheck() {
    print_status "section" "SHELLCHECK (SHELL SCRIPT LINTER)"

    if command_exists shellcheck; then
        print_status "info" "shellcheck already installed"
        return 0
    fi

    if command_exists brew; then
        print_status "info" "Installing shellcheck via Homebrew..."
        if run_or_echo brew install shellcheck &>> "$LOG_FILE"; then
            print_status "success" "shellcheck installed via Homebrew"
            return 0
        fi
        print_status "warning" "Homebrew install failed, falling back to system package..."
    fi

    # Distro package names: apt/pacman/zypper use 'shellcheck'; Fedora uses 'ShellCheck'.
    print_status "info" "Installing shellcheck via system package manager..."
    install_package shellcheck shellcheck ShellCheck shellcheck &>> "$LOG_FILE"

    if command_exists shellcheck; then
        shellcheck --version >> "$LOG_FILE"
        print_status "success" "shellcheck installed: $(shellcheck --version 2>/dev/null | awk '/^version:/ {print $2}')"
    else
        print_status "error" "shellcheck installation failed — check $LOG_FILE"
        return 1
    fi
}

install_gitlint() {
    print_status "section" "GITLINT (COMMIT MESSAGE LINTER)"

    if command_exists gitlint; then
        print_status "info" "gitlint already installed"
        return 0
    fi

    if command_exists brew; then
        print_status "info" "Installing gitlint via Homebrew..."
        if run_or_echo brew install gitlint &>> "$LOG_FILE"; then
            print_status "success" "gitlint installed via Homebrew"
            return 0
        fi
        print_status "warning" "Homebrew install failed, falling back to pipx..."
    fi

    # pipx installs the CLI in an isolated venv — the correct path on PEP 668
    # distros (Ubuntu 24.04 blocks `pip install --user` and ships python3 with
    # no pip module). The install_pipx bootstrapper normally provides pipx
    # before this step runs.
    if command_exists pipx; then
        print_status "info" "Installing gitlint via pipx..."
        run_or_echo pipx install gitlint-core &>> "$LOG_FILE"
    else
        print_status "warning" "pipx not found — run the 'Python CLI tooling (pip + pipx)' step first"
    fi

    if command_exists gitlint; then
        gitlint --version >> "$LOG_FILE"
        print_status "success" "gitlint installed: $(gitlint --version 2>/dev/null)"
    else
        print_status "error" "gitlint install failed — try: brew install gitlint  OR  pipx install gitlint-core (ensure ~/.local/bin on PATH)"
        return 1
    fi
}

INSTALL_REGISTRY+=(
    "install_github_cli:GitHub CLI::"
    "install_act:act (Run GitHub Actions Locally)::"
    "install_gitleaks:Gitleaks (Secret Scanner)::"
    "install_shellcheck:shellcheck (Shell Script Linter)::"
    "install_gitlint:gitlint (Commit Message Linter)::"
)
