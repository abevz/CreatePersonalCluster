# Scripts Directory

This directory contains utility scripts for the **my-kthw** project.

## Utility Scripts

### VM Management
- `fix_machine_id.sh` - Fix machine-id conflicts on cloned VMs
- `fix_machine_id_remote.sh` - Remote machine-id fix via SSH
- `fix_machine_id_ssh.sh` - SSH-based machine-id repair
- `fix_vm_hostname.sh` - Fix VM hostname configuration
- `verify_vm_hostname.sh` - Verify VM hostname settings

### Infrastructure
- `generate_node_hostnames.sh` - Generate Kubernetes node hostnames
- `add_pihole_dns.py` - Add DNS entries to Pi-hole server
- `test_terraform_outputs.py` - Test Terraform output parsing

### Template Management
- `template.sh` - VM template creation wrapper
- `vm_template/` - VM template creation and configuration scripts

## VM Template Directory

The `vm_template/` directory contains a **modular VM template creation system** with OS-specific implementations:

### New Modular Structure (Recommended)
- **Main dispatcher**: `create_template_dispatcher.sh` - Automatically detects OS type and routes to appropriate script
- **Shared functions**: `shared/common_functions.sh` - Reusable functions for all OS types
- **OS-specific modules**:
  - `ubuntu/` - Ubuntu template creation (`create_ubuntu_template.sh`, `ubuntu-cloud-init-userdata.yaml`)
  - `debian/` - Debian template creation (`create_debian_template.sh`, `debian-cloud-init-userdata.yaml`)
  - `rocky/` - Rocky Linux template creation (`create_rocky_template.sh`, `rocky-cloud-init-userdata.yaml`)
  - `suse/` - SUSE/openSUSE template creation (`create_suse_template.sh`, `suse-cloud-init-userdata.yaml`)

### Legacy (Maintained for Compatibility)
- `create_template_helper.sh` - Original monolithic script (522 lines, being phased out)

### Benefits of New Structure
- **Maintainability**: Each OS script is ~150-200 lines vs 522-line monolith
- **Scalability**: Easy to add new OS support by creating new directory
- **Readability**: Clear separation of concerns and OS-specific logic
- **Testing**: Each OS can be tested independently

### Usage
The system automatically detects OS type from `IMAGE_NAME` variable and calls the appropriate script:
- Ubuntu images: `*ubuntu*`, `*Ubuntu*` → `ubuntu/create_ubuntu_template.sh`  
- Debian images: `*debian*`, `*Debian*` → `debian/create_debian_template.sh`
- Rocky images: `*Rocky*`, `*rocky*` → `rocky/create_rocky_template.sh`
- SUSE images: `*suse*`, `*SUSE*`, `*openSUSE*` → `suse/create_suse_template.sh`
- **Maintenance scripts**: Scripts for fixing SSH, encoding, and user issues

## Usage

Most scripts are designed to be called from the project root or via the `cpc` command:

```bash
# From project root
./scripts/fix_vm_hostname.sh

# Via CPC command
./cpc template --os ubuntu --version 24.04
```

## Dependencies

- **Proxmox VE API** access
- **SSH keys** configured
- **SOPS** for secret management
- **Python 3** for Python scripts
- **jq** for JSON processing
