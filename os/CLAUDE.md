# os/CLAUDE.md

## Purpose

OS-level tooling: ISO management and virtual machine creation / launching.

## Scripts

| File | What it does |
|------|-------------|
| `isos_os_manager.sh` | Download, verify, and organise OS ISO files |
| `vm_creator.sh` | Create KVM/QEMU VMs (Windows 11 + Ubuntu) on a chosen drive |
| `vm_launcher.sh` | Start an existing KVM VM with display/network options |

## Conventions

- **`print_status <level> <msg>`** with the standard color vars.
- Scripts that create or modify VMs **require root** — guard with `[ "$(id -u)" -ne 0 ]`.
- VM disks use `qcow2` format: `qemu-img create -f qcow2 <path>.qcow2 <size>G`.
- VM directories follow `<mount>/vms/<vm-name>/`.
- Always prompt the user for the target mount point; never hardcode paths.
- Use `virt-install` for VM creation; `virsh` for lifecycle management.
- Dependencies: `qemu-kvm libvirt-daemon-system virtinst virt-manager`.

## Adding a new VM type

1. Add a `create_<os>_vm()` function following the `create_windows_vm` / `create_ubuntu_vm`
   pattern in `vm_creator.sh`.
2. Call it from `main()` after the existing VM creation calls.
3. Add a `create_vm_disk "<name>" <size_gb>` call at the top of the function.
