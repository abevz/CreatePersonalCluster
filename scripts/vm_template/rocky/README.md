# Rocky Linux VM Template Creation

This directory contains Rocky Linux-specific files and scripts for VM template creation.

## Files

- `create_rocky_template.sh` - Main Rocky Linux template creation script
- `rocky-cloud-init-userdata.yaml` - Rocky Linux-specific cloud-init configuration
- `cloud-init-config.yaml` - Additional cloud-init configuration

## Usage

The Rocky Linux template creation script is automatically called by the main dispatcher when a Rocky Linux image is detected based on the `IMAGE_NAME` variable.

### Manual execution:
```bash
cd /path/to/vm_template/rocky
./create_rocky_template.sh
```

## Features

- DNF/YUM package management
- QEMU Guest Agent installation
- Kubernetes repository configuration
- SELinux configuration for Kubernetes
- Firewall configuration
- Container runtime (containerd) setup
- SSH key injection
- Custom hostname configuration
- Automatic shutdown after configuration completion

## Cloud-init Configuration

Rocky Linux uses standard cloud-init configuration with firstboot scripts for package installation due to libguestfs compatibility issues.

## Dependencies

- All variables from `cpc.env`
- All secrets from SOPS (loaded via environment variables)
- Shared functions from `../shared/common_functions.sh`
