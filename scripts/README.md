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

The `vm_template/` directory contains scripts and configurations for creating Proxmox VM templates:

- **OS-specific configurations**: `ubuntu/`, `debian/`, `rocky/`, `suse/`
- **Cloud-init templates**: 
  - `ubuntu-cloud-init-userdata.yaml` - Ubuntu cloud-init configuration
  - `debian-cloud-init-userdata.yaml` - Debian cloud-init configuration
- **Creation scripts**: `create_template.sh`, `create_template_helper.sh`
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
