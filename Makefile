# ===========================================
# DOTFILES - MAKEFILE
# ===========================================

.DEFAULT_GOAL := help

# -------------------
# QUICK START
# -------------------
.PHONY: init

init: permissions install_programs install_toolchains vscode_setup irpf_download set_shortcuts ubuntu_workspace install_espanso_packages
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║                                                            ║"
	@echo "║  🎉 Initial System Setup Complete!                         ║"
	@echo "║                                                            ║"
	@echo "║  ✅ Permissions set for all scripts                        ║"
	@echo "║  ✅ Essential programs installed                           ║"
	@echo "║  ✅ Toolchains installed                                   ║"
	@echo "║  ✅ VS Code configured with extensions                     ║"
	@echo "║  ✅ IRPF (Brazilian tax software) downloaded               ║"
	@echo "║  ✅ Custom shortcuts configured                            ║"
	@echo "║  ✅ Ubuntu workspace configured                            ║"
	@echo "║                                                            ║"
	@echo "║  Next steps:                                               ║"
	@echo "║    • make setup_all_drivers  (configure hardware)          ║"
	@echo "║    • make storage_setup      (configure storage)           ║"
	@echo "║    • make vm_setup           (setup virtual machines)      ║"
	@echo "║    • make help               (see all commands)            ║"
	@echo "║                                                            ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""

# -------------------
# SYSTEM SETUP
# -------------------
.PHONY: install_programs irpf_download set_shortcuts ubuntu_workspace vscode_setup vscode_restore bash_profile

install_programs:
	@echo "Installing essential programs..."
	@bash distro_config/install_programs.sh

install_toolchains:
	@echo "Installing development toolchains..."
	@bash distro_config/install_toolchains.sh

vscode_setup:
	@echo "Configuring VS Code with extensions and shortcuts..."
	@bash code_editors/vscode.sh

vscode_restore:
	@echo "Restoring VS Code configurations..."
	@bash code_editors/vscode_restore.sh

irpf_download:
	@echo "Downloading IRPF (Brazilian tax software)..."
	@bash distro_config/irpf_download.sh

set_shortcuts:
	@echo "Setting custom shortcuts..."
	@bash distro_config/set_custom_shortcuts.sh

ubuntu_workspace:
	@echo "Configuring Ubuntu workspace..."
	@bash distro_config/ubuntu_workspace.sh

bash_profile:
	@echo "Ensuring ~/.bash_profile loads ~/.bashrc..."
	@bash distro_config/bash_profile_snippet.sh

# -------------------
# HARDWARE DRIVERS
# -------------------
.PHONY: setup_bluetooth setup_keyboard setup_mouse setup_wifi setup_all_drivers

setup_bluetooth:
	@echo "Setting up Bluetooth adapter..."
	@bash drivers/bluetooth_adapter.sh

setup_keyboard:
	@echo "Configuring keyboard..."
	@bash drivers/setup_keyboard.sh

setup_mouse:
	@echo "Configuring mouse..."
	@bash drivers/mouse.sh

setup_wifi:
	@echo "Setting up TP-Link WiFi adapter..."
	@bash drivers/tplink_wifi_adapter.sh

setup_all_drivers: setup_bluetooth setup_keyboard setup_mouse setup_wifi
	@echo "All drivers configured successfully!"

# -------------------
# STORAGE MANAGEMENT
# -------------------
.PHONY: check_drive_legitimacy data_recovery format_hard format_neat vault_setup mount_disks

check_drive_legitimacy:
	@echo "Checking drive legitimacy and integrity..."
	@bash drives/check_legitimity.sh

data_recovery:
	@echo "Running data recovery tools..."
	@bash drives/data_recovery.sh

format_hard:
	@echo "⚠️  WARNING: Performing hard format (complete drive formatting)..."
	@echo "This operation is IRREVERSIBLE. Press Ctrl+C to cancel."
	@sleep 3
	@bash drives/format_hard.sh

format_neat:
	@echo "Performing neat format (quick and clean)..."
	@bash drives/format_neat.sh

vault_setup:
	@echo "Setting up secure storage vault..."
	@bash drives/vault.sh

mount_disks:
	@echo "Mounting unmounted non-NTFS partitions..."
	@bash drives/mount_disks.sh

# -------------------
# OS MANAGEMENT
# -------------------
.PHONY: manage_isos create_vm launch_vm

manage_isos:
	@echo "Managing ISO files and operating systems..."
	@bash os/isos_os_manager.sh

create_vm:
	@echo "Creating virtual machine..."
	@bash os/vm_creator.sh

launch_vm:
	@echo "Launching virtual machine..."
	@bash os/vm_launcher.sh

# -------------------
# STORAGE ANALYTICS
# -------------------
.PHONY: storage_analysis

storage_analysis:
	@echo "Running storage gap analysis..."
	@bash storage/storage_hiato.sh

# -------------------
# BATCH OPERATIONS
# -------------------
.PHONY: full_setup install_espanso_packages hardware_setup storage_setup vm_setup permissions

full_setup: permissions install_programs install_toolchains vscode_setup setup_all_drivers
	@echo ""
	@echo "════════════════════════════════════════════"
	@echo "  ✅ Full system setup completed!"
	@echo "════════════════════════════════════════════"
	@echo ""

.PHONY: install_espanso_packages


install_espanso_packages:
	@echo "Installing Espanso packages from repo..."
	@PACK_DIR="$$HOME/.config/espanso/packages"; \
	mkdir -p "$$PACK_DIR"; \
	for d in espanso/*; do \
		if [ -d "$$d" ]; then \
			name=$$(basename "$$d"); \
			echo " - Installing $$d -> $$PACK_DIR/$$name"; \
			rm -rf "$$PACK_DIR/$$name" 2>/dev/null || true; \
			cp -a "$$d" "$$PACK_DIR/$$name"; \
			find "$$PACK_DIR/$$name" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true; \
		fi; \
	done; \
	echo "Espanso packages installed to $$PACK_DIR"; \
	if command -v espanso >/dev/null 2>&1; then \
		echo "Reloading espanso..."; \
		espanso restart >/dev/null 2>&1 || espanso start >/dev/null 2>&1 || true; \
	fi; \
	# Run per-package setup scripts (for terminal wrappers like :shortcuts) \
	for d in espanso/*; do \
		if [ -f "$$d/setup.sh" ]; then \
			echo "Running setup: $$d/setup.sh"; \
			bash "$$d/setup.sh"; \
		fi; \
	done; \
	echo "Note: to use new terminal wrappers in this session, run: source ~/.profile"

hardware_setup: setup_bluetooth setup_keyboard setup_mouse setup_wifi
	@echo ""
	@echo "════════════════════════════════════════════"
	@echo "  ✅ Hardware setup completed!"
	@echo "════════════════════════════════════════════"
	@echo ""

storage_setup: check_drive_legitimacy format_neat vault_setup storage_analysis
	@echo ""
	@echo "════════════════════════════════════════════"
	@echo "  ✅ Storage setup completed!"
	@echo "════════════════════════════════════════════"
	@echo ""

vm_setup: manage_isos create_vm
	@echo ""
	@echo "════════════════════════════════════════════"
	@echo "  ✅ Virtual machine setup completed!"
	@echo "════════════════════════════════════════════"
	@echo ""

permissions:
	@echo "Making all scripts executable..."
	@find distro_config -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
	@find drivers -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
	@find drives -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
	@find os -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
	@find storage -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
	@find code_editors -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
	@echo "✅ Permissions updated successfully!"

# -------------------
# CODE EDITORS
# -------------------
.PHONY: editors_setup

editors_setup: vscode_setup
	@echo ""
	@echo "════════════════════════════════════════════"
	@echo "  ✅ Code editors setup completed!"
	@echo "════════════════════════════════════════════"
	@echo ""

# -------------------
# UTILITIES
# -------------------
.PHONY: check_status list_scripts clean

check_status:
	@echo "Checking system status..."
	@echo ""
	@echo "=== Distribution Info ==="
	@lsb_release -a 2>/dev/null || cat /etc/os-release
	@echo ""
	@echo "=== Available Scripts ==="
	@find distro_config drivers drives os storage code_editors -name "*.sh" -type f 2>/dev/null | sort
	@echo ""
	@echo "=== Executable Scripts ==="
	@find distro_config drivers drives os storage code_editors -name "*.sh" -type f -executable 2>/dev/null | sort

list_scripts:
	@echo "Available bash scripts:"
	@echo ""
	@echo "Distro Config scripts:"
	@ls -1 distro_config/*.sh 2>/dev/null || echo "  No distro config scripts found"
	@echo ""
	@echo "Driver scripts:"
	@ls -1 drivers/*.sh 2>/dev/null || echo "  No driver scripts found"
	@echo ""
	@echo "Drive scripts:"
	@ls -1 drives/*.sh 2>/dev/null || echo "  No drive scripts found"
	@echo ""
	@echo "OS scripts:"
	@ls -1 os/*.sh 2>/dev/null || echo "  No OS scripts found"
	@echo ""
	@echo "Storage scripts:"
	@ls -1 storage/*.sh 2>/dev/null || echo "  No storage scripts found"
	@echo ""
	@echo "Code Editor scripts:"
	@ls -1 code_editors/*.sh 2>/dev/null || echo "  No code editor scripts found"

clean:
	@echo "Cleaning temporary files..."
	@find distro_config drivers drives os storage code_editors -name "*.log" -type f -delete 2>/dev/null || true
	@find distro_config drivers drives os storage code_editors -name "*.tmp" -type f -delete 2>/dev/null || true
	@find distro_config drivers drives os storage code_editors -name "*~" -type f -delete 2>/dev/null || true
	@echo "✅ Cleanup completed!"

# -------------------
# HELP
# -------------------
.PHONY: help

help:
	@echo "═══════════════════════════════════════════════════════════"
	@echo "  DOTFILES - Available Make Targets"
	@echo "═══════════════════════════════════════════════════════════"
	@echo ""
	@echo "🚀 Quick Start:"
	@echo "  init                 - Complete initial setup (RECOMMENDED)"
	@echo "                         Runs: permissions + all system config"
	@echo ""
	@echo "System Setup:"
	@echo "  install_programs     - Install essential programs"
	@echo "  install_toolchains   - Install development toolchains"
	@echo "  vscode_setup         - Configure VS Code with extensions"
	@echo "  irpf_download        - Download IRPF (Brazilian tax software)"
	@echo "  set_shortcuts        - Set custom keyboard shortcuts"
	@echo "  ubuntu_workspace     - Configure Ubuntu workspace"
	@echo ""
	@echo "Code Editors:"
	@echo "  editors_setup        - Setup all code editors (currently VS Code)"
	@echo ""
	@echo "Hardware Drivers:"
	@echo "  setup_bluetooth      - Setup Bluetooth adapter"
	@echo "  setup_keyboard       - Configure keyboard"
	@echo "  setup_mouse          - Configure mouse"
	@echo "  setup_wifi           - Setup TP-Link WiFi adapter"
	@echo "  setup_all_drivers    - Setup all hardware drivers"
	@echo ""
	@echo "Storage Management:"
	@echo "  check_drive_legitimacy - Check drive authenticity and integrity"
	@echo "  data_recovery        - Run data recovery tools"
	@echo "  format_hard          - Complete drive formatting (⚠️  DANGEROUS)"
	@echo "  format_neat          - Quick and clean formatting"
	@echo "  vault_setup          - Setup secure storage vault"
	@echo "  mount_disks          - Mount unmounted non-NTFS partitions"
	@echo ""
	@echo "OS Management:"
	@echo "  manage_isos          - Manage ISO files and operating systems"
	@echo "  create_vm            - Create virtual machine"
	@echo "  launch_vm            - Launch virtual machine"
	@echo ""
	@echo "Storage Analytics:"
	@echo "  storage_analysis     - Run storage gap analysis and monitoring"
	@echo ""
	@echo "Batch Operations:"
	@echo "  full_setup           - Complete system setup (programs + drivers)"
	@echo "  hardware_setup       - Setup all hardware drivers"
	@echo "  storage_setup        - Complete storage setup"
	@echo "  vm_setup             - Setup virtual machine environment"
	@echo "  editors_setup        - Setup code editors"
	@echo "  permissions          - Make all scripts executable"
	@echo ""
	@echo "Utilities:"
	@echo "  check_status         - Check system and scripts status"
	@echo "  list_scripts         - List all available bash scripts"
	@echo "  clean                - Clean temporary files"
	@echo "  help                 - Show this help message"
	@echo ""
	@echo "═══════════════════════════════════════════════════════════"
	@echo ""
	@echo "💡 Usage examples:"
	@echo "  make init            - First-time setup (recommended!)"
	@echo "  make full_setup      - Complete system setup"
	@echo "  make vscode_setup    - Configure VS Code only"
	@echo "  make editors_setup   - Setup all code editors"
	@echo "  make setup_wifi      - Setup WiFi adapter only"
	@echo "  make permissions     - Make all scripts executable"
	@echo ""
	@echo "⚠️  Warning: format_hard is IRREVERSIBLE - use with caution!"
	@echo ""