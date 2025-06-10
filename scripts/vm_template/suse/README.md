# SUSE VM Template Creation

This directory contains SUSE/openSUSE-specific files and scripts for VM template creation.

## Files

- `create_suse_template.sh` - Main SUSE template creation script
- `suse-cloud-init-userdata.yaml` - SUSE-specific cloud-init configuration
- `cloud-init-config.yaml` - Additional cloud-init configuration

## Usage

The SUSE template creation script is automatically called by the main dispatcher when a SUSE/openSUSE image is detected based on the `IMAGE_NAME` variable.

### Manual execution:
```bash
cd /path/to/vm_template/suse
./create_suse_template.sh
```

## Features

- Zypper package management
- QEMU Guest Agent installation
- Kubernetes repository configuration
- Container runtime (containerd) setup
- SSH key injection
- Custom hostname configuration
- Automatic shutdown after configuration completion

## Cloud-init Configuration

SUSE uses standard cloud-init configuration with firstboot scripts for package installation due to libguestfs compatibility issues.

## Dependencies

- All variables from `cpc.env`
- All secrets from SOPS (loaded via environment variables)
- Shared functions from `../shared/common_functions.sh`
