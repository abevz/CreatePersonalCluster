# Ubuntu VM Template Creation

This directory contains Ubuntu-specific files and scripts for VM template creation.

## Files

- `create_ubuntu_template.sh` - Main Ubuntu template creation script
- `ubuntu-cloud-init-userdata.yaml` - Ubuntu-specific cloud-init configuration
- `cloud-init-config.yaml` - Additional cloud-init configuration

## Usage

The Ubuntu template creation script is automatically called by the main dispatcher when an Ubuntu image is detected based on the `IMAGE_NAME` variable.

### Manual execution:
```bash
cd /path/to/vm_template/ubuntu
./create_ubuntu_template.sh
```

## Features

- Automatic QEMU Guest Agent installation via cloud-init
- Kubernetes-ready package installation
- Machine-ID cleanup for template cloning
- SSH key injection
- Custom hostname configuration
- Automatic shutdown after configuration completion

## Cloud-init Configuration

The `ubuntu-cloud-init-userdata.yaml` file is processed with variable substitution:
- `${VM_USERNAME}` - VM username from secrets
- `${VM_SSH_KEY}` - SSH public key from secrets  
- `${VM_HOSTNAME}` - Hostname set to ubuntu-template-${TEMPLATE_VM_ID}

## Dependencies

- All variables from `cpc.env`
- All secrets from SOPS (loaded via environment variables)
- Shared functions from `../shared/common_functions.sh`
