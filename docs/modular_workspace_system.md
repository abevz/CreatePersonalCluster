# Modular Workspace Environment System

This document explains the new modular workspace environment system implemented in CPC (Cluster Provisioning Control).

## Background

Previously, all workspace configurations were defined in a single `cpc.env` file using suffix-based variables (e.g., `TEMPLATE_VM_ID_UBUNTU`). This approach had several limitations:
- The `cpc.env` file became cluttered with workspace-specific variables
- Adding a new workspace required modifying multiple files
- It was difficult to track which variables belonged to which workspace
- Supporting different Kubernetes versions was challenging

## New Modular Approach

The new system uses separate environment files for each workspace, stored in the `envs/` directory:

```
envs/
  ├── debian.env
  ├── k8s129.env  
  ├── rocky.env
  ├── suse.env
  ├── ubuntu.env
  └── README.md
```

### Benefits

- **Cleaner organization**: Each workspace has its own isolated configuration file
- **Easy to create new workspaces**: Use the `clone-workspace` command to create new configurations
- **Better version management**: Support different Kubernetes versions in different workspaces
- **Simplified maintenance**: Changes to one workspace don't affect others
- **Improved documentation**: Each workspace file is self-contained with relevant comments

## How It Works

1. When you run `cpc ctx <workspace>`, the system loads:
   - Base variables from `cpc.env`
   - Workspace-specific variables from `envs/<workspace>.env`

2. The `load_env_vars()` function first attempts to load the workspace-specific file:
   ```bash
   local workspace_env_file="$repo_root/envs/$current_workspace.env"
   if [ -f "$workspace_env_file" ]; then
     source "$workspace_env_file"
   ```

3. If no workspace file exists, the system falls back to the legacy approach.

## Creating New Workspaces

You can create new workspaces using the `clone-workspace` command:

```bash
cpc clone-workspace <source_workspace> <destination_workspace>
```

This command:
1. Creates a new environment file by copying the source workspace's file
2. Creates a new Terraform/OpenTofu workspace
3. Sets up the necessary configuration for the new workspace

Example:
```bash
# Create a new workspace for Kubernetes 1.30 based on the ubuntu workspace
cpc clone-workspace ubuntu k8s130

# Edit the new workspace file to change the Kubernetes version
vi envs/k8s130.env

# Switch to the new workspace
cpc ctx k8s130
```

## Customizing a Workspace

Each workspace environment file contains several categories of variables:

### Template VM Configuration
```bash
TEMPLATE_VM_ID="9420"
TEMPLATE_VM_NAME="tpl-ubuntu-2404-k8s"
IMAGE_NAME="ubuntu-24.04-server-cloudimg-amd64.img"
IMAGE_LINK="https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
```

### Kubernetes Component Versions
```bash
KUBERNETES_SHORT_VERSION="1.29"
KUBERNETES_MEDIUM_VERSION="v1.29"
KUBERNETES_LONG_VERSION="1.29.8"
CNI_PLUGINS_VERSION="v1.4.0"
CALICO_VERSION="v3.26.4"
METALLB_VERSION="v0.13.12"
# ...and more version variables
```

### VM Specifications
```bash
VM_CPU_CORES="2"
VM_MEMORY_DEDICATED="2048"
VM_DISK_SIZE="20"
VM_STARTED="true"
VM_DOMAIN=".bevz.net"
```

### Hostname Generation
```bash
# Release letter used for hostname generation
# This single character is used to create unique hostnames for VMs
# Pattern: <role><release_letter><index>
# Examples: ck1, wk1, wk2 (for controlplane k 1, worker k 1, worker k 2)
RELEASE_LETTER="k"
```

## Best Practices

1. **Naming conventions**:
   - Use descriptive names for workspaces (e.g., `ubuntu`, `k8s129`)
   - Use lowercase letters and numbers, with hyphens for separators

2. **Version management**:
   - Create separate workspaces for different Kubernetes versions
   - Document version dependencies in comments

3. **Testing**:
   - Test new workspaces thoroughly before using in production
   - Verify that all addons work with your selected versions

4. **Documentation**:
   - Document any special considerations for specific workspaces
   - Add comments to explain non-standard configurations

## Migrating from Legacy Configuration

If you're using an older version of CPC with the legacy configuration approach:

1. Your existing workspaces will continue to work through the fallback mechanism
2. Create environment files for your existing workspaces:
   ```bash
   # For each workspace (e.g., ubuntu, debian, etc.)
   cpc ctx <workspace>
   # Note the variables displayed and create a corresponding .env file
   ```

3. Test each workspace to ensure it works with the new system
