# Debian VM Template Creation

This directory contains Debian-specific files and scripts for VM template creation.

## Files

- `create_debian_template.sh` - Main Debian template creation script
- `debian-cloud-init-userdata.yaml` - Debian-specific cloud-init configuration
- `cloud-init-config.yaml` - Additional cloud-init configuration
- Various other cloud-init variants for testing and specific use cases

## Usage

The Debian template creation script is automatically called by the main dispatcher when a Debian image is detected based on the `IMAGE_NAME` variable.

### Manual execution:
```bash
cd /path/to/vm_template/debian
./create_debian_template.sh
```

## Features

- Custom cloud-init user-data with Debian-specific package management
- QEMU Guest Agent installation via cloud-init
- Kubernetes-ready package installation
- APT repository configuration
- SSH key injection
- Custom hostname configuration
- Automatic shutdown after configuration completion

## Cloud-init Configuration

The `debian-cloud-init-userdata.yaml` file is processed with variable substitution:
- `${VM_USERNAME}` - VM username from secrets
- `${VM_SSH_KEY}` - SSH public key from secrets  
- `${VM_HOSTNAME}` - Hostname set to debian-template-${TEMPLATE_VM_ID}

## Dependencies

- All variables from `cpc.env`
- All secrets from SOPS (loaded via environment variables)
- Shared functions from `../shared/common_functions.sh`
