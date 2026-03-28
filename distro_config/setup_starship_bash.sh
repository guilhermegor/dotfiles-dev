#!/bin/bash

set -e
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="$HOME/starship_bash_setup_$(date +%Y%m%d_%H%M%S).log"
DISTRO=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""

STARSHIP_CONFIG_FILE="$HOME/.config/starship.toml"
STARSHIP_COMPLETION_FILE="$HOME/.local/share/bash-completion/completions/starship.bash"
STARSHIP_STATE_DIR="$HOME/.local/share/dotfiles-dev/starship-bash"
STARSHIP_BACKUP_DIR="$STARSHIP_STATE_DIR/backups"
CURRENT_BACKUP_DIR=""
ACTIVE_BACKUP_CREATED=false

STARSHIP_BASH_BEGIN="# >>> dotfiles-dev starship bash >>>"
STARSHIP_BASH_END="# <<< dotfiles-dev starship bash <<<"
INPUTRC_BEGIN="# >>> dotfiles-dev bash autocomplete >>>"
INPUTRC_END="# <<< dotfiles-dev bash autocomplete <<<"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_status() {
    local status="$1"
    local message="$2"

    case "$status" in
        "success")
            echo -e "${GREEN}[✓]${NC} ${message}"
            ;;
        "error")
            echo -e "${RED}[✗]${NC} ${message}" >&2
            ;;
        "warning")
            echo -e "${YELLOW}[!]${NC} ${message}"
            ;;
        "info")
            echo -e "${BLUE}[i]${NC} ${message}"
            ;;
        "config")
            echo -e "${CYAN}[→]${NC} ${message}"
            ;;
        "section")
            echo -e "\n${MAGENTA}========================================${NC}"
            echo -e "${MAGENTA} $message${NC}"
            echo -e "${MAGENTA}========================================${NC}\n"
            ;;
        *)
            echo -e "[ ] ${message}"
            ;;
    esac

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$status] $message" >> "$LOG_FILE"
}

command_exists() {
    command -v "$1" &> /dev/null
}

check_internet() {
    print_status "info" "Checking internet connectivity..."

    if ping -c 1 google.com &> /dev/null; then
        print_status "success" "Internet connection verified"
        return 0
    fi

    print_status "error" "No internet connection detected"
    return 1
}

ensure_file_exists() {
    local file_path="$1"

    mkdir -p "$(dirname "$file_path")"
    touch "$file_path"
}

remove_managed_block() {
    local file_path="$1"
    local begin_marker="$2"
    local end_marker="$3"
    local temp_file

    if [ ! -f "$file_path" ]; then
        return 0
    fi

    temp_file=$(mktemp)
    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { skip = 1; next }
        $0 == end { skip = 0; next }
        skip != 1 { print }
    ' "$file_path" > "$temp_file"
    mv "$temp_file" "$file_path"
}

append_managed_block() {
    local file_path="$1"
    local begin_marker="$2"
    local end_marker="$3"
    local block_content="$4"

    ensure_file_exists "$file_path"
    remove_managed_block "$file_path" "$begin_marker" "$end_marker"

    {
        echo ""
        echo "$begin_marker"
        printf '%s\n' "$block_content"
        echo "$end_marker"
    } >> "$file_path"
}

# ============================================================================
# DISTRO DETECTION
# ============================================================================

detect_distro() {
    print_status "info" "Detecting Linux distribution..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID

        case "$DISTRO" in
            ubuntu|debian|pop|linuxmint)
                PACKAGE_MANAGER="apt"
                INSTALL_CMD="sudo apt-get install -y"
                UPDATE_CMD="sudo apt update"
                ;;
            fedora|rhel|centos|rocky|almalinux)
                PACKAGE_MANAGER="dnf"
                INSTALL_CMD="sudo dnf install -y"
                UPDATE_CMD="sudo dnf check-update || true"
                ;;
            arch|manjaro|endeavouros)
                PACKAGE_MANAGER="pacman"
                INSTALL_CMD="sudo pacman -S --noconfirm"
                UPDATE_CMD="sudo pacman -Sy"
                ;;
            opensuse*|sles)
                PACKAGE_MANAGER="zypper"
                INSTALL_CMD="sudo zypper install -y"
                UPDATE_CMD="sudo zypper refresh"
                ;;
            *)
                print_status "warning" "Unknown distribution: $DISTRO"
                detect_package_manager_fallback
                return
                ;;
        esac

        print_status "success" "Detected system: ${PRETTY_NAME:-$DISTRO}"
        print_status "info" "Using package manager: $PACKAGE_MANAGER"
    else
        print_status "warning" "/etc/os-release not found"
        detect_package_manager_fallback
    fi
}

detect_package_manager_fallback() {
    if command_exists apt-get; then
        PACKAGE_MANAGER="apt"
        INSTALL_CMD="sudo apt-get install -y"
        UPDATE_CMD="sudo apt update"
    elif command_exists dnf; then
        PACKAGE_MANAGER="dnf"
        INSTALL_CMD="sudo dnf install -y"
        UPDATE_CMD="sudo dnf check-update || true"
    elif command_exists pacman; then
        PACKAGE_MANAGER="pacman"
        INSTALL_CMD="sudo pacman -S --noconfirm"
        UPDATE_CMD="sudo pacman -Sy"
    elif command_exists zypper; then
        PACKAGE_MANAGER="zypper"
        INSTALL_CMD="sudo zypper install -y"
        UPDATE_CMD="sudo zypper refresh"
    else
        print_status "error" "No supported package manager found"
        exit 1
    fi

    print_status "info" "Using package manager fallback: $PACKAGE_MANAGER"
}

install_package() {
    local package_name="$1"
    local debian_name="${2:-$package_name}"
    local fedora_name="${3:-$package_name}"
    local arch_name="${4:-$package_name}"
    local opensuse_name="${5:-$debian_name}"

    case "$PACKAGE_MANAGER" in
        apt)
            $INSTALL_CMD "$debian_name"
            ;;
        dnf)
            $INSTALL_CMD "$fedora_name"
            ;;
        pacman)
            $INSTALL_CMD "$arch_name"
            ;;
        zypper)
            $INSTALL_CMD "$opensuse_name"
            ;;
        *)
            print_status "error" "Unsupported package manager: $PACKAGE_MANAGER"
            return 1
            ;;
    esac
}

# ============================================================================
# BACKUP AND RESTORE
# ============================================================================

get_backup_key() {
    local file_path="$1"

    case "$file_path" in
        "$HOME/.bashrc")
            echo "bashrc"
            ;;
        "$HOME/.inputrc")
            echo "inputrc"
            ;;
        "$STARSHIP_CONFIG_FILE")
            echo "starship.toml"
            ;;
        "$STARSHIP_COMPLETION_FILE")
            echo "starship.bash"
            ;;
        *)
            basename "$file_path"
            ;;
    esac
}

backup_target_file() {
    local file_path="$1"
    local backup_dir="$2"
    local key

    key=$(get_backup_key "$file_path")
    mkdir -p "$backup_dir"
    rm -f "$backup_dir/$key" "$backup_dir/$key.absent"

    if [ -f "$file_path" ]; then
        cp -a "$file_path" "$backup_dir/$key"
    else
        touch "$backup_dir/$key.absent"
    fi
}

restore_target_file() {
    local file_path="$1"
    local backup_dir="$2"
    local key

    key=$(get_backup_key "$file_path")

    if [ -f "$backup_dir/$key" ]; then
        mkdir -p "$(dirname "$file_path")"
        cp -a "$backup_dir/$key" "$file_path"
    elif [ -f "$backup_dir/$key.absent" ]; then
        rm -f "$file_path"
    else
        print_status "warning" "No backup entry found for $file_path"
    fi
}

create_state_directories() {
    mkdir -p "$STARSHIP_BACKUP_DIR"
}

create_original_backup_if_needed() {
    local original_dir="$STARSHIP_BACKUP_DIR/original"

    create_state_directories

    if [ -d "$original_dir" ]; then
        return 0
    fi

    mkdir -p "$original_dir"
    backup_target_file "$HOME/.bashrc" "$original_dir"
    backup_target_file "$HOME/.inputrc" "$original_dir"
    backup_target_file "$STARSHIP_CONFIG_FILE" "$original_dir"
    backup_target_file "$STARSHIP_COMPLETION_FILE" "$original_dir"
    print_status "success" "Original shell configuration backup created"
}

create_backup_set() {
    local timestamp
    local counter=0

    if [ "$ACTIVE_BACKUP_CREATED" = true ]; then
        return 0
    fi

    create_original_backup_if_needed

    timestamp=$(date +%Y%m%d_%H%M%S)
    CURRENT_BACKUP_DIR="$STARSHIP_BACKUP_DIR/$timestamp"
    while [ -d "$CURRENT_BACKUP_DIR" ]; do
        counter=$((counter + 1))
        CURRENT_BACKUP_DIR="$STARSHIP_BACKUP_DIR/${timestamp}_$counter"
    done
    mkdir -p "$CURRENT_BACKUP_DIR"

    backup_target_file "$HOME/.bashrc" "$CURRENT_BACKUP_DIR"
    backup_target_file "$HOME/.inputrc" "$CURRENT_BACKUP_DIR"
    backup_target_file "$STARSHIP_CONFIG_FILE" "$CURRENT_BACKUP_DIR"
    backup_target_file "$STARSHIP_COMPLETION_FILE" "$CURRENT_BACKUP_DIR"

    ACTIVE_BACKUP_CREATED=true
    print_status "success" "Current shell configuration backed up to $CURRENT_BACKUP_DIR"
}

get_latest_backup_dir() {
    if [ ! -d "$STARSHIP_BACKUP_DIR" ]; then
        return 1
    fi

    find "$STARSHIP_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d ! -name original | sort | tail -n1
}

restore_from_backup_dir() {
    local backup_dir="$1"

    if [ ! -d "$backup_dir" ]; then
        print_status "error" "Backup directory not found: $backup_dir"
        return 1
    fi

    restore_target_file "$HOME/.bashrc" "$backup_dir"
    restore_target_file "$HOME/.inputrc" "$backup_dir"
    restore_target_file "$STARSHIP_CONFIG_FILE" "$backup_dir"
    restore_target_file "$STARSHIP_COMPLETION_FILE" "$backup_dir"
}

restore_previous_configuration() {
    print_status "section" "ROLLBACK TO PREVIOUS CONFIGURATION"

    local previous_backup

    previous_backup=$(get_latest_backup_dir || true)
    if [ -z "$previous_backup" ]; then
        print_status "error" "No previous backup found"
        return 1
    fi

    ACTIVE_BACKUP_CREATED=false
    create_backup_set
    restore_from_backup_dir "$previous_backup"
    print_status "success" "Rolled back to previous shell configuration"
    print_status "info" "Restored snapshot: $previous_backup"
    print_status "config" "Reload your shell with: source ~/.bashrc"
}

restore_original_configuration() {
    print_status "section" "ROLLBACK TO ORIGINAL CONFIGURATION"

    local original_dir="$STARSHIP_BACKUP_DIR/original"

    if [ ! -d "$original_dir" ]; then
        print_status "error" "No original backup found"
        return 1
    fi

    ACTIVE_BACKUP_CREATED=false
    create_backup_set
    restore_from_backup_dir "$original_dir"
    print_status "success" "Rolled back to original shell configuration"
    print_status "config" "Reload your shell with: source ~/.bashrc"
}

# ============================================================================
# STARSHIP AND AUTOCOMPLETE SETUP
# ============================================================================

install_starship() {
    print_status "section" "STARSHIP INSTALLATION"

    if command_exists starship; then
        print_status "info" "Starship already installed ($(starship --version | head -n1))"
        return 0
    fi

    check_internet

    print_status "info" "Installing Starship prompt..."

    if install_package "starship" "starship" "starship" "starship" "starship" 2>&1 | tee -a "$LOG_FILE"; then
        print_status "success" "Starship installed via package manager"
    else
        print_status "warning" "Package manager installation failed, using official installer"

        if ! command_exists curl; then
            print_status "info" "Installing curl for Starship installer..."
            install_package "curl" "curl" "curl" "curl" "curl" 2>&1 | tee -a "$LOG_FILE"
        fi

        mkdir -p "$HOME/.local/bin"
        if curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin" 2>&1 | tee -a "$LOG_FILE"; then
            print_status "success" "Starship installed to $HOME/.local/bin"
        else
            print_status "error" "Failed to install Starship"
            return 1
        fi
    fi

    if command_exists starship || [ -x "$HOME/.local/bin/starship" ]; then
        print_status "success" "Starship installation verified"
    else
        print_status "error" "Starship binary not found after installation"
        return 1
    fi
}

install_bash_completion() {
    print_status "section" "BASH AUTOCOMPLETE"

    if [ -f /usr/share/bash-completion/bash_completion ] || [ -f /etc/bash_completion ]; then
        print_status "info" "bash-completion is already available"
        return 0
    fi

    check_internet

    print_status "info" "Installing bash-completion package..."
    if install_package "bash-completion" "bash-completion" "bash-completion" "bash-completion" "bash-completion" 2>&1 | tee -a "$LOG_FILE"; then
        print_status "success" "bash-completion installed successfully"
    else
        print_status "error" "Failed to install bash-completion"
        return 1
    fi
}

write_starship_plain_text_config() {
    print_status "section" "STARSHIP CONFIGURATION"

    create_backup_set
    mkdir -p "$(dirname "$STARSHIP_CONFIG_FILE")"

    cat > "$STARSHIP_CONFIG_FILE" << 'EOF'
"$schema" = 'https://starship.rs/config-schema.json'

continuation_prompt = "[.](bright-black) "

[character]
success_symbol = "[>](bold green)"
error_symbol = "[x](bold red)"
vimcmd_symbol = "[<](bold green)"
vimcmd_visual_symbol = "[<](bold yellow)"
vimcmd_replace_symbol = "[<](bold purple)"
vimcmd_replace_one_symbol = "[<](bold purple)"

[git_commit]
tag_symbol = " tag "

[git_status]
ahead = ">"
behind = "<"
diverged = "<>"
renamed = "r"
deleted = "x"

[aws]
symbol = "aws "

[azure]
symbol = "az "

[battery]
full_symbol = "full "
charging_symbol = "charging "
discharging_symbol = "discharging "
unknown_symbol = "unknown "
empty_symbol = "empty "

[buf]
symbol = "buf "

[bun]
symbol = "bun "

[c]
symbol = "C "

[cpp]
symbol = "C++ "

[cobol]
symbol = "cobol "

[conda]
symbol = "conda "

[container]
symbol = "container "

[crystal]
symbol = "cr "

[cmake]
symbol = "cmake "

[daml]
symbol = "daml "

[dart]
symbol = "dart "

[deno]
symbol = "deno "

[dotnet]
format = "via [$symbol($version )(target $tfm )]($style)"
symbol = ".NET "

[directory]
read_only = " ro"

[docker_context]
symbol = "docker "

[elixir]
symbol = "exs "

[elm]
symbol = "elm "

[erlang]
symbol = "erl "

[fennel]
symbol = "fnl "

[fortran]
symbol = "fortran "

[fossil_branch]
symbol = "fossil "
truncation_symbol = "..."

[gcloud]
symbol = "gcp "

[git_branch]
symbol = "git "
truncation_symbol = "..."

[gleam]
symbol = "gleam "

[golang]
symbol = "go "

[gradle]
symbol = "gradle "

[guix_shell]
symbol = "guix "

[haskell]
symbol = "haskell "

[haxe]
symbol = "hx "

[helm]
symbol = "helm "

[hg_branch]
symbol = "hg "
truncation_symbol = "..."

[hostname]
ssh_symbol = "ssh "

[java]
symbol = "java "

[jobs]
symbol = "*"

[julia]
symbol = "jl "

[kotlin]
symbol = "kt "

[kubernetes]
symbol = "kubernetes "

[lua]
symbol = "lua "

[nodejs]
symbol = "nodejs "

[memory_usage]
symbol = "memory "

[meson]
symbol = "meson "
truncation_symbol = "..."

[mojo]
symbol = "mojo "

[nats]
symbol = "nats "

[netns]
symbol = "netns "

[nim]
symbol = "nim "

[nix_shell]
symbol = "nix "

[ocaml]
symbol = "ml "

[odin]
symbol = "odin "

[opa]
symbol = "opa "

[openstack]
symbol = "openstack "

[os.symbols]
AIX = "aix "
Alpaquita = "alq "
AlmaLinux = "alma "
Alpine = "alp "
ALTLinux = "alt "
Amazon = "amz "
Android = "andr "
AOSC = "aosc "
Arch = "rch "
Artix = "atx "
Bluefin = "blfn "
CachyOS = "cach "
CentOS = "cent "
Debian = "deb "
DragonFly = "dfbsd "
Elementary = "elem "
Emscripten = "emsc "
EndeavourOS = "ndev "
Fedora = "fed "
FreeBSD = "fbsd "
Garuda = "garu "
Gentoo = "gent "
HardenedBSD = "hbsd "
Illumos = "lum "
Ios = "ios "
InstantOS = "inst "
Kali = "kali "
Linux = "lnx "
Mabox = "mbox "
Macos = "mac "
Manjaro = "mjo "
Mariner = "mrn "
MidnightBSD = "mid "
Mint = "mint "
NetBSD = "nbsd "
NixOS = "nix "
Nobara = "nbra "
OpenBSD = "obsd "
OpenCloudOS = "ocos "
openEuler = "oeul "
openSUSE = "osuse "
OracleLinux = "orac "
PikaOS = "pika "
Pop = "pop "
Raspbian = "rasp "
Redhat = "rhl "
RedHatEnterprise = "rhel "
RockyLinux = "rky "
Redox = "redox "
Solus = "sol "
SUSE = "suse "
Ubuntu = "ubnt "
Ultramarine = "ultm "
Unknown = "unk "
Uos = "uos "
Void = "void "
Windows = "win "
Zorin = "zorn "

[package]
symbol = "pkg "

[perl]
symbol = "pl "

[php]
symbol = "php "

[pijul_channel]
symbol = "pijul "
truncation_symbol = "..."

[pixi]
symbol = "pixi "

[pulumi]
symbol = "pulumi "

[purescript]
symbol = "purs "

[python]
symbol = "py "

[quarto]
symbol = "quarto "

[raku]
symbol = "raku "

[red]
symbol = "red "

[rlang]
symbol = "r "

[ruby]
symbol = "rb "

[rust]
symbol = "rs "

[scala]
symbol = "scala "

[shlvl]
symbol = "shlvl "

[spack]
symbol = "spack "

[solidity]
symbol = "solidity "

[status]
symbol = "[x](bold red) "
not_executable_symbol = "noexec"
not_found_symbol = "notfound"
sigint_symbol = "sigint"
signal_symbol = "sig"

[sudo]
symbol = "sudo "

[swift]
symbol = "swift "

[typst]
symbol = "typst "

[vagrant]
symbol = "vagrant "

[terraform]
symbol = "terraform "

[xmake]
symbol = "xmake "

[zig]
symbol = "zig "
EOF

    print_status "success" "Plain text Starship preset written to $STARSHIP_CONFIG_FILE"
}

configure_bash_for_starship() {
    print_status "section" "BASH PROMPT INTEGRATION"

    create_backup_set

    local bash_block
    bash_block=$(cat << 'EOF'
export PATH="$HOME/.local/bin:$PATH"
eval "$(starship init bash)"

if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

if [ -f "$HOME/.local/share/bash-completion/completions/starship.bash" ]; then
    . "$HOME/.local/share/bash-completion/completions/starship.bash"
fi
EOF
)

    append_managed_block "$HOME/.bashrc" "$STARSHIP_BASH_BEGIN" "$STARSHIP_BASH_END" "$bash_block"
    print_status "success" "Starship added to ~/.bashrc"
}

configure_bash_autocomplete() {
    print_status "section" "AUTOCOMPLETE CONFIGURATION"

    create_backup_set
    mkdir -p "$(dirname "$STARSHIP_COMPLETION_FILE")"

    if command_exists starship; then
        starship completions bash > "$STARSHIP_COMPLETION_FILE"
    elif [ -x "$HOME/.local/bin/starship" ]; then
        "$HOME/.local/bin/starship" completions bash > "$STARSHIP_COMPLETION_FILE"
    else
        print_status "error" "Starship binary not found for completion generation"
        return 1
    fi

    local inputrc_block
    inputrc_block=$(cat << 'EOF'
set show-all-if-ambiguous on
set completion-ignore-case on
set completion-map-case on
set mark-symlinked-directories on
EOF
)

    append_managed_block "$HOME/.inputrc" "$INPUTRC_BEGIN" "$INPUTRC_END" "$inputrc_block"
    print_status "success" "Bash autocomplete configured"
}

verify_setup() {
    print_status "section" "VERIFICATION"

    local starship_binary="starship"
    if ! command_exists starship && [ -x "$HOME/.local/bin/starship" ]; then
        starship_binary="$HOME/.local/bin/starship"
    fi

    if command_exists starship || [ -x "$HOME/.local/bin/starship" ]; then
        print_status "config" "  Starship: $($starship_binary --version | head -n1)"
    else
        print_status "warning" "Starship command is not available in the current shell yet"
    fi

    if grep -qF "$STARSHIP_BASH_BEGIN" "$HOME/.bashrc" 2>/dev/null; then
        print_status "success" "Bash integration block found in ~/.bashrc"
    else
        print_status "warning" "Bash integration block not found in ~/.bashrc"
    fi

    if [ -f "$STARSHIP_CONFIG_FILE" ]; then
        print_status "success" "Starship config found at $STARSHIP_CONFIG_FILE"
    else
        print_status "warning" "Starship config file missing"
    fi

    if [ -f "$STARSHIP_COMPLETION_FILE" ]; then
        print_status "success" "Starship completion file generated"
    else
        print_status "warning" "Starship completion file missing"
    fi

    if [ -f /usr/share/bash-completion/bash_completion ] || [ -f /etc/bash_completion ]; then
        print_status "success" "bash-completion runtime is available"
    else
        print_status "warning" "bash-completion runtime not found"
    fi

    print_status "info" "Reload Bash to apply changes: source ~/.bashrc"
}

# ============================================================================
# MENU AND MAIN EXECUTION
# ============================================================================

run_full_setup() {
    install_starship
    install_bash_completion
    write_starship_plain_text_config
    configure_bash_for_starship
    configure_bash_autocomplete
    verify_setup
}

run_custom_setup() {
    print_status "section" "CUSTOM STARSHIP/BASH SETUP"

    local components=(
        "install_starship:Install Starship"
        "install_bash_completion:Install bash-completion"
        "write_starship_plain_text_config:Write plain text Starship preset"
        "configure_bash_for_starship:Attach Starship to Bash"
        "configure_bash_autocomplete:Enable Bash autocomplete"
        "verify_setup:Verify setup"
    )
    local selection
    local func_name
    local display_name
    local num

    echo -e "\n${YELLOW}Select steps to run (space-separated numbers, or 'all'):${NC}"
    for i in "${!components[@]}"; do
        IFS=':' read -r func_name display_name <<< "${components[$i]}"
        echo -e "  ${GREEN}$((i+1)))${NC} $display_name"
    done
    echo -e "\n${CYAN}Selection:${NC} "
    read -r selection

    if [[ "$selection" == "all" ]]; then
        run_full_setup
        return 0
    fi

    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#components[@]}" ]; then
            IFS=':' read -r func_name display_name <<< "${components[$((num-1))]}"
            $func_name
        else
            print_status "warning" "Ignoring invalid selection: $num"
        fi
    done
}

show_menu() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}      ${MAGENTA}Starship Prompt and Bash Autocomplete Setup${NC}      ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

    echo -e "${GREEN}Detected System:${NC} $DISTRO"
    echo -e "${GREEN}Package Manager:${NC} $PACKAGE_MANAGER"
    echo -e ""
    echo -e "${YELLOW}Select mode:${NC}"
    echo -e "  ${GREEN}1)${NC} Full setup"
    echo -e "  ${GREEN}2)${NC} Custom setup"
    echo -e "  ${GREEN}3)${NC} Rollback to previous configuration"
    echo -e "  ${GREEN}4)${NC} Rollback to original configuration"
    echo -e "  ${GREEN}5)${NC} Verify current setup"
    echo -e "  ${GREEN}6)${NC} Exit"
    echo -e "\n${CYAN}Choice:${NC} "
}

print_usage() {
    echo "Usage: bash $0 [all|custom|undo-previous|undo-original|verify]"
}

main() {
    if [ "$EUID" -eq 0 ]; then
        print_status "error" "This script should NOT be run with sudo"
        print_status "info" "Please run as: bash $0"
        exit 1
    fi

    detect_distro

    case "${1:-}" in
        all)
            run_full_setup
            ;;
        custom)
            run_custom_setup
            ;;
        undo-previous)
            restore_previous_configuration
            ;;
        undo-original)
            restore_original_configuration
            ;;
        verify)
            verify_setup
            ;;
        "")
            while true; do
                show_menu
                read -r choice

                case "$choice" in
                    1)
                        run_full_setup
                        break
                        ;;
                    2)
                        run_custom_setup
                        break
                        ;;
                    3)
                        restore_previous_configuration
                        break
                        ;;
                    4)
                        restore_original_configuration
                        break
                        ;;
                    5)
                        verify_setup
                        break
                        ;;
                    6)
                        print_status "info" "Setup cancelled"
                        exit 0
                        ;;
                    *)
                        print_status "error" "Invalid option. Please select 1-6."
                        ;;
                esac
            done
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac

    print_status "section" "STARSHIP/BASH SETUP COMPLETE"
    print_status "info" "Log file: $LOG_FILE"
    print_status "config" "Reload Bash with: source ~/.bashrc"
}

main "$@"