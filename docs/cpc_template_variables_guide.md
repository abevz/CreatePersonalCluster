# CPC Template Creation Setup - Variables Guide

## Overview

The `my-kthw` project has been successfully adapted to use a centralized `cpc.env` configuration file with workspace-specific template variables. The system now supports creating different VM templates for **debian**, **ubuntu**, and **rocky** workspaces automatically.

## Required Variables in cpc.env

### Core Proxmox Configuration
```bash
# Proxmox connection
PROXMOX_HOST="10.10.10.187"
PROXMOX_USERNAME="abevz"
PROXMOX_NODE="homelab"

# Proxmox storage
PROXMOX_ISO_PATH="/var/lib/vz/template/iso"
PROXMOX_DISK_DATASTORE="local-lvm"
PROXMOX_BACKUPS_DATASTORE="local"

# Network settings
TEMPLATE_VM_BRIDGE="vmbr0"
TEMPLATE_VLAN_TAG=""
TWO_DNS_SERVERS="10.10.10.187 8.8.8.8"
TEMPLATE_VM_SEARCH_DOMAIN="bevz.net"
TEMPLATE_VM_GATEWAY="10.10.10.1"
```

### VM Credentials
```bash
VM_USERNAME="abevz"
VM_PASSWORD="your_secure_password"
NON_PASSWORD_PROTECTED_SSH_KEY="id_rsa"
```

### Hostname Generation
```bash
# Release letter used for VM hostname generation
# This letter is used as part of the hostname pattern: <role><release_letter><index>
# For example: ck1 (controlplane k 1), wk1 (worker k 1), wk2 (worker k 2)
RELEASE_LETTER="k"
```

### Template VM Specifications
```bash
TEMPLATE_VM_CPU="2"
TEMPLATE_VM_CPU_TYPE="x86-64-v3"
TEMPLATE_VM_MEM="2048"
TEMPLATE_DISK_SIZE="20G"
TEMPLATE_VM_IP="10.10.10.250/24"
```

### Workspace-Specific Template Variables

**For Debian workspace:**
```bash
TEMPLATE_VM_ID_DEBIAN="902"
TEMPLATE_VM_NAME_DEBIAN="tpl-debian-12-k8s"
IMAGE_NAME_DEBIAN="debian-12-genericcloud-amd64.qcow2"
IMAGE_LINK_DEBIAN="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
```

**For Ubuntu workspace:**
```bash
TEMPLATE_VM_ID_UBUNTU="912"
TEMPLATE_VM_NAME_UBUNTU="tpl-ubuntu-2404-k8s"
IMAGE_NAME_UBUNTU="ubuntu-24.04-server-cloudimg-amd64.img"
IMAGE_LINK_UBUNTU="https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
```

**For Rocky workspace:**
```bash
TEMPLATE_VM_ID_ROCKY="931"
TEMPLATE_VM_NAME_ROCKY="tpl-rocky-9-k8s"
IMAGE_NAME_ROCKY="Rocky-9-GenericCloud.latest.x86_64.qcow2"
IMAGE_LINK_ROCKY="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
```

### Kubernetes Configuration
```bash
KUBERNETES_SHORT_VERSION="1.30"
KUBERNETES_MEDIUM_VERSION="v1.30"
KUBERNETES_LONG_VERSION="1.30.0"

CNI_PLUGINS_VERSION="v1.5.0"
CILIUM_VERSION="v1.15.5"
METALLB_VERSION="v0.14.5"
METRICS_SERVER_VERSION="v0.7.1"
ETCD_VERSION="v3.5.12"
```

### Optional Features
```bash
NVIDIA_DRIVER_VERSION="none"  # or specific version like "550.54.15"
EXTRA_TEMPLATE_TAGS="kubernetes"
```

## How It Works

1. **Workspace-based Configuration**: The `cpc` script automatically sets the appropriate template variables (`TEMPLATE_VM_ID`, `TEMPLATE_VM_NAME`, `IMAGE_NAME`, `IMAGE_LINK`) based on the current Tofu workspace.

2. **Dynamic Variable Assignment**: When you run `cpc ctx <workspace>`, the system:
   - Switches the Tofu workspace 
   - Loads workspace-specific variables
   - Sets the current template configuration

3. **Template Creation**: When you run `cpc template`, the system:
   - Uses the workspace-specific variables
   - Copies the correct configuration to Proxmox
   - Creates a template with the appropriate OS image

## Usage Examples

### Setup
```bash
# Initial setup
./cpc setup-cpc

# Copy example config and customize
cp cpc.env.example cpc.env
# Edit cpc.env with your values
```

### Template Creation for Different OS
```bash
# Create Ubuntu template
./cpc ctx ubuntu
./cpc template

# Create Debian template  
./cpc ctx debian
./cpc template

# Create Rocky template
./cpc ctx rocky
./cpc template
```

### Check Current Configuration
```bash
# See current workspace and available options
./cpc ctx

# Check what template variables are set
./cpc template --help  # Shows current workspace template vars
```

## Key Benefits

1. **Centralized Configuration**: All settings in one `cpc.env` file
2. **Workspace Isolation**: Different templates for different OS distributions
3. **No Hardcoded Values**: All configurable through environment variables
4. **Easy Switching**: Change OS type with simple `cpc ctx <workspace>` command
5. **Tofu Integration**: Seamlessly works with Tofu workspaces

## Files Modified

- `cpc.env.example` - Comprehensive configuration template
- `cpc.env` - Your actual configuration file
- `cpc` - Enhanced with workspace-specific variable management
- `scripts/template.sh` - Adapted to use environment variables
- `scripts/vm_template/create_template_helper.sh` - Updated to source cpc.env

The system is now ready for template creation across different operating systems using workspace-specific configurations!
