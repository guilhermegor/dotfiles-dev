# Linux Distro Init <img src="https://upload.wikimedia.org/wikipedia/commons/3/35/Tux.svg" align="right" width="120" style="border-radius: 15px;" alt="Linux Penguin">

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
![Shell Version](https://img.shields.io/badge/shell-Bash%20%7C%20Zsh-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Open Issues](https://img.shields.io/github/issues/guilhermegor/linux-distro-init)
![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-darkgreen.svg)

**Linux Distro Init** is a comprehensive initialization and configuration toolkit for Linux distributions. It provides automated setup scripts for system configuration, driver installation, storage management, and development environment setup.

**🎯 Features a powerful Makefile** for easy command execution and workflow automation - no need to remember complex script paths!

## ✨ Key Features

### 🛠️ System Configuration

#### **Distribution Setup**
- [Install Programs](distro_config/install_programs.sh) - Automated installation of essential programs (`make install_programs`)
- [Ubuntu Workspace Setup](distro_config/ubuntu_workspace.sh) - Ubuntu-specific workspace configuration (`make ubuntu_workspace`)
- [Custom Shortcuts](distro_config/set_custom_shortcuts.sh) - Custom keyboard and application shortcuts (`make set_shortcuts`)
- [IRPF Download Utility](distro_config/irpf_download.sh) - Brazilian tax software downloader (`make irpf_download`)

### 🔧 Hardware Drivers

#### **Peripheral Configuration**
- [Bluetooth Adapter](drivers/bluetooth_adapter.sh) - Bluetooth driver setup and configuration (`make setup_bluetooth`)
- [Keyboard Configuration](drivers/keyboard_cdllha.sh) - Custom keyboard layout and settings (`make setup_keyboard`)
- [Mouse Configuration](drivers/mouse.sh) - Mouse driver and sensitivity settings (`make setup_mouse`)
- [WiFi Adapter](drivers/tplink_wifi_adapter.sh) - TP-Link WiFi adapter driver installation (`make setup_wifi`)

**Quick setup:** Run `make setup_all_drivers` to configure all hardware at once.

### 💾 Storage Management

#### **Drive Operations**
- [Legitimacy Check](drives/check_legitimity.sh) - Drive authenticity and integrity verification (`make check_drive_legitimacy`)
- [Data Recovery](drives/data_recovery.sh) - Data recovery tools and procedures (`make data_recovery`)
- [Hard Format](drives/format_hard.sh) - Complete drive formatting (`make format_hard`)
- [Neat Format](drives/format_neat.sh) - Quick and clean formatting (`make format_neat`)
- [Vault Management](drives/vault.sh) - Secure storage vault setup (`make vault_setup`)

**Quick setup:** Run `make storage_setup` for complete storage configuration.

### 🖥️ Operating System Management

#### **Virtualization & OS Tools**
- [ISO OS Manager](os/isos_os_manager.sh) - ISO file and operating system management (`make manage_isos`)
- [VM Creator](os/vm_creator.sh) - Virtual machine creation utility (`make create_vm`)
- [VM Launcher](os/vm_launcher.sh) - Virtual machine management and launch (`make launch_vm`)

**Quick setup:** Run `make vm_setup` to configure the complete VM environment.

### 📊 Storage Analytics

#### **Storage Monitoring**
- [Storage Hiato](storage/storage_hiato.sh) - Storage gap analysis and monitoring (`make storage_analysis`)

## 🚀 Getting Started

### Prerequisites

- **Linux Distribution** (Ubuntu, Debian, or compatible)
- **Bash Shell** 4.0+
- **Sudo Privileges** for system-wide installations

### ⚡ Quick Start (Recommended)

Get your Linux system configured in seconds:
```bash
sudo apt update && sudo apt upgrade -y && sudo apt-get update
sudo apt install dkms git -y

mkdir ~/github
cd ~/github
git clone https://github.com/guilhermegor/linux-distro-init.git
cd linux-distro-init

make init
```

### 📋 Important Notes

**⚠️ Administrator Privileges Required**

During the setup process, you will be prompted to enter your system password multiple times. This is necessary to execute commands with administrator privileges (sudo) for system-wide configurations and installations.

**⌨️ Navigation Tips**

- Use **Tab** key to navigate between options in interactive menus
- Use **Arrow keys** (↑/↓) to move through selection lists
- Press **Enter** to confirm your selection
- Press **Spacebar** to toggle checkboxes (when applicable)

**💡 Setup Tips**

- Ensure you have a **stable internet connection** before starting
- The initial setup may take **10-20 minutes** depending on your system
- It's recommended to **close unnecessary applications** during installation
- If prompted to restart any services, choose **Yes** to ensure proper configuration

**🔄 What to Expect**

The `make init` command will:
- ✅ Set executable permissions for all scripts
- ✅ Install essential programs
- ✅ Download IRPF (Brazilian tax software)
- ✅ Configure custom shortcuts
- ✅ Set up Ubuntu workspace

**Estimated time:** 10-20 minutes

After `make init` completes, you can optionally run:
```bash
make setup_all_drivers    # Configure all hardware
make storage_setup        # Setup storage management
make vm_setup            # Configure virtual machines
```

### Alternative Installation Methods

**Option 1: Step-by-Step with Makefile**
```bash
git clone https://github.com/guilhermegor/linux-distro-init.git
cd linux-distro-init

# Make all scripts executable
make permissions

# Run complete system setup
make full_setup

# Or view all available commands
make help
```

**Option 2: Direct Script Execution**
```bash
# Install specific components
chmod +x distro_config/install_programs.sh
bash distro_config/install_programs.sh

# Configure hardware
chmod +x drivers/*.sh
bash drivers/tplink_wifi_adapter.sh
```

## 🧪 Running Configuration

### Using Makefile (Recommended)

View all available commands:
```bash
make help
```

Run complete initial setup:
```bash
make init
```

Run full system setup:
```bash
make full_setup
```

Run individual components:
```bash
# Hardware setup
make setup_wifi
make setup_bluetooth
make setup_keyboard

# Storage setup
make format_neat
make storage_analysis

# System setup
make ubuntu_workspace
make install_programs
```

### Direct Script Execution

Alternatively, execute scripts directly:
```bash
# Hardware setup
bash drivers/bluetooth_adapter.sh
bash drivers/keyboard_cdllha.sh

# Storage setup
bash drives/format_neat.sh
bash storage/storage_hiato.sh
```

## 📂 Project Structure
```
linux-distro-init/
│
├── 📋 Makefile                   # Automation recipes for all scripts
│
├── 📁 distro_config/             # Distribution configuration
│   ├── 📦 install_programs.sh    # Program installation script
│   ├── 📥 irpf_download.sh       # Tax software downloader
│   ├── ⌨️ set_custom_shortcuts.sh # Custom shortcuts configuration
│   └── 🖥️ ubuntu_workspace.sh    # Ubuntu workspace setup
│
├── 📁 drivers/                   # Hardware driver configurations
│   ├── 📡 bluetooth_adapter.sh   # Bluetooth setup
│   ├── ⌨️ keyboard_cdllha.sh     # Keyboard configuration
│   ├── 🖱️ mouse.sh               # Mouse settings
│   └── 📶 tplink_wifi_adapter.sh # WiFi adapter setup
│
├── 📁 drives/                    # Storage management
│   ├── 🔍 check_legitimity.sh    # Drive legitimacy verification
│   ├── 💾 data_recovery.sh       # Data recovery tools
│   ├── 🗑️ format_hard.sh         # Complete formatting
│   ├── 🧹 format_neat.sh         # Quick formatting
│   └── 🔒 vault.sh               # Secure vault management
│
├── 📁 os/                        # OS management tools
│   ├── 💿 isos_os_manager.sh     # ISO file management
│   ├── 🖥️ vm_creator.sh          # VM creation utility
│   └── 🚀 vm_launcher.sh         # VM management
│
├── 📁 storage/                   # Storage analytics
│   └── 📊 storage_hiato.sh       # Storage monitoring
│
└── 📖 README.md                  # Project documentation
```

## ⚙️ Configuration Workflow

### Recommended Workflow (Using `make init`)

1. **Clone and Initialize (One Command)**
```bash
   git clone https://github.com/guilhermegor/linux-distro-init.git
   cd linux-distro-init
   make init
```

2. **Optional: Additional Configuration**
   
   After `make init` completes, optionally configure:

   **Hardware Configuration**
```bash
   make setup_all_drivers
   # Or individually:
   make setup_wifi
   make setup_bluetooth
   make setup_keyboard
   make setup_mouse
```

   **Storage Setup**
```bash
   make storage_setup
   # Or individually:
   make format_neat
   make vault_setup
   make storage_analysis
```

   **Virtualization Environment**
```bash
   make vm_setup
   # Or individually:
   make manage_isos
   make create_vm
   make launch_vm
```

### Alternative: Step-by-Step Configuration

1. **Setup Permissions**
```bash
   make permissions
```

2. **Complete System Setup (All-in-One)**
```bash
   make full_setup
```

3. **Or Individual Configuration:**

   **Software Installation**
```bash
   make install_programs
   make ubuntu_workspace
   make set_shortcuts
   make irpf_download
```

   **Hardware Configuration**
```bash
   make setup_all_drivers
```

   **Storage Setup**
```bash
   make storage_setup
```

   **Virtualization Environment**
```bash
   make vm_setup
```

## 🎯 Available Make Commands

Run `make help` to see all available commands, or check these common recipes:

### Quick Start
- `make init` - **Complete initial setup (RECOMMENDED)** - Sets permissions and configures all system essentials

### System Setup
- `make install_programs` - Install essential programs
- `make ubuntu_workspace` - Configure Ubuntu workspace
- `make set_shortcuts` - Set custom keyboard shortcuts
- `make irpf_download` - Download Brazilian tax software

### Hardware Drivers
- `make setup_all_drivers` - Setup all hardware drivers at once
- `make setup_bluetooth` - Setup Bluetooth adapter
- `make setup_keyboard` - Configure keyboard
- `make setup_mouse` - Configure mouse
- `make setup_wifi` - Setup TP-Link WiFi adapter

### Storage Management
- `make storage_setup` - Complete storage setup
- `make check_drive_legitimacy` - Check drive authenticity
- `make data_recovery` - Run data recovery tools
- `make format_hard` - Complete drive formatting
- `make format_neat` - Quick formatting
- `make vault_setup` - Setup secure vault
- `make storage_analysis` - Storage monitoring

### OS Management
- `make vm_setup` - Complete VM setup
- `make manage_isos` - Manage ISO files
- `make create_vm` - Create virtual machine
- `make launch_vm` - Launch virtual machine

### Batch Operations
- `make full_setup` - Complete system setup (programs + drivers)
- `make hardware_setup` - Setup all hardware drivers
- `make storage_setup` - Complete storage configuration
- `make vm_setup` - Setup virtual machine environment

### Utilities
- `make permissions` - Make all scripts executable
- `make check_status` - Check system and scripts status
- `make list_scripts` - List all available bash scripts
- `make clean` - Clean temporary files
- `make help` - Show all available commands

## 👨‍💻 Authors

**Guilherme Rodrigues**  
[![GitHub](https://img.shields.io/badge/GitHub-guilhermegor-181717?style=flat&logo=github)](https://github.com/guilhermegor)  
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Guilherme_Rodrigues-0077B5?style=flat&logo=linkedin)](https://www.linkedin.com/in/guilhermegor/)

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙌 Acknowledgments

- Inspired by various Linux distribution setup scripts and automation tools
- Thanks to the Linux community for best practices and configuration examples

## 🔗 Useful Links

- [GitHub Repository](https://github.com/guilhermegor/linux-distro-init)
- [Issue Tracker](https://github.com/guilhermegor/linux-distro-init/issues)