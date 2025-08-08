# CPC Commands Reference

This document provides a detailed reference for all commands available in the CPC (Cluster Provisioning Control) tool.

## Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `setup-cpc` | Initialize CPC and set repository path | `./cpc setup-cpc` |
| `ctx` | Get or set cluster context (Tofu workspace) | `./cpc ctx ubuntu` |
| `clone-workspace` | Clone a workspace environment to create a new one | `./cpc clone-workspace ubuntu k8s129` |
| `delete-workspace` | Delete a workspace environment and its resources | `./cpc delete-workspace k8s129` |
| `load_secrets` | Load secrets from SOPS configuration | `./cpc load_secrets` |

## Infrastructure Management

| Command | Description | Example |
|---------|-------------|---------|
| `template` | Creates a VM template for Kubernetes | `./cpc template` |
| `deploy` | Run any Tofu command in context | `./cpc deploy apply` |
| `start-vms` | Start all VMs in the current context | `./cpc start-vms` |
| `stop-vms` | Stop all VMs in the current context | `./cpc stop-vms` |

## Cluster Management

| Command | Description | Example |
|---------|-------------|---------|
| `bootstrap` | Bootstrap a complete Kubernetes cluster on deployed VMs | `./cpc bootstrap` |
| `get-kubeconfig` | Retrieve and merge Kubernetes cluster config | `./cpc get-kubeconfig` |
| `add-nodes` | Add new worker nodes to the cluster | `./cpc add-nodes` |
| `upgrade-addons` | Install/upgrade cluster addons | `./cpc upgrade-addons` |
| `upgrade-k8s` | Upgrade Kubernetes control plane | `./cpc upgrade-k8s` |
| `configure-coredns` | Configure CoreDNS for local domain queries | `./cpc configure-coredns` |

## Node Management

| Command | Description | Example |
|---------|-------------|---------|
| `drain-node` | Drain workloads from a node | `./cpc drain-node worker-1` |
| `delete-node` | Delete a node from the Kubernetes cluster | `./cpc delete-node worker-1` |
| `upgrade-node` | Upgrade Kubernetes on a specific node | `./cpc upgrade-node worker-1` |
| `reset-node` | Reset Kubernetes on a specific node | `./cpc reset-node worker-1` |
| `reset-all-nodes` | Reset Kubernetes on all nodes | `./cpc reset-all-nodes` |

## Remote Execution

| Command | Description | Example |
|---------|-------------|---------|
| `run-ansible` | Run Ansible playbook with proper inventory | `./cpc run-ansible playbooks/bootstrap.yml` |
| `run-command` | Run shell command on target host(s) | `./cpc run-command control_plane "kubectl get nodes"` |

## Utility Commands

| Command | Description | Example |
|---------|-------------|---------|
| `update-pihole` | Manage Pi-hole DNS records | `./cpc update-pihole add` |
| `clear-ssh-hosts` | Clear VM IPs from SSH known hosts | `./cpc clear-ssh-hosts` |
| `clear-ssh-maps` | Clear SSH control sockets for VMs | `./cpc clear-ssh-maps` |
| `generate-hostnames` | Generate hostname configs for VMs | `./cpc generate-hostnames` |

## Hostname Generation System

CPC uses a structured hostname generation system for Kubernetes cluster VMs. All hostnames follow the pattern:
```
<role><release_letter><index>.<domain>
```

Where:
- **role**: `c` (controlplane) or `w` (worker)
- **release_letter**: Single character from workspace's `RELEASE_LETTER` variable
- **index**: Sequential number starting from 1
- **domain**: From `VM_DOMAIN` variable (e.g., `.bevz.net`)

### Examples
For `RELEASE_LETTER=k` and `VM_DOMAIN=".bevz.net"`:
- Controlplane: `ck1.bevz.net`
- Workers: `wk1.bevz.net`, `wk2.bevz.net`

The `RELEASE_LETTER` variable is defined in each workspace's environment file (`envs/<workspace>.env`) and can be customized when creating new workspaces with the `clone-workspace` command.

For detailed information, see [Hostname Generation System](hostname_generation_system.md).

## New Command: clone-workspace

The `clone-workspace` command is a recent addition that allows you to create new workspace environments based on existing ones. This is particularly useful when you want to experiment with different Kubernetes versions or configurations without modifying your existing workspaces.

### Usage
```bash
./cpc clone-workspace <source_workspace> <destination_workspace> [release_letter]
```

### Parameters
- `source_workspace`: The existing workspace to copy from (e.g., ubuntu, debian, rocky, suse)
- `destination_workspace`: The name for the new workspace
- `release_letter`: Optional single character for VM hostname generation (defaults to first letter of destination workspace)

### Examples
```bash
# Create a new workspace based on Ubuntu for Kubernetes 1.29
./cpc clone-workspace ubuntu k8s129

# Create a new workspace with a specific release letter
./cpc clone-workspace ubuntu k8s129 k

# Create a test environment
./cpc clone-workspace ubuntu testing t

# Edit the new workspace file
vi ./envs/k8s129.env

# Switch to the new workspace
./cpc ctx k8s129
```

### What it Does
1. Creates a new environment file in the `envs/` directory by copying the source workspace's file
2. Adds the `RELEASE_LETTER` variable to the new environment file
3. Creates a new Terraform/OpenTofu workspace with the same name
4. Updates Terraform locals.tf with the new workspace mappings (template_vm_ids, release_letters_map, vm_id_ranges)
5. Sets up the necessary configuration for the new workspace

### Release Letter
The `release_letter` parameter controls the hostname generation for VMs in the workspace. VM hostnames follow the pattern: `<role><release_letter><index>.<domain>`

Examples with different release letters:
- `RELEASE_LETTER=k`: ck1.bevz.net, wk1.bevz.net, wk2.bevz.net
- `RELEASE_LETTER=t`: ct1.bevz.net, wt1.bevz.net, wt2.bevz.net

For more details on hostname generation, see [Hostname Generation System](hostname_generation_system.md).

This command is part of the new modular workspace system. For more details, see [Modular Workspace System](modular_workspace_system.md).

## New Command: delete-workspace

The `delete-workspace` command allows you to safely remove workspace environments that are no longer needed. This command performs a comprehensive cleanup of all workspace-related resources.

### Usage
```bash
./cpc delete-workspace <workspace_name>
```

### Parameters
- `workspace_name`: The name of the workspace to delete (must not be the currently active workspace)

### Examples
```bash
# Delete a test workspace
./cpc delete-workspace testing

# Delete an old Kubernetes version workspace
./cpc delete-workspace k8s128
```

### What it Does
1. **Safety checks**: Prevents deletion of predefined base workspaces (debian, ubuntu, rocky, suse)
2. **Resource state checking**: Intelligently checks if workspace has any existing resources before attempting cleanup
3. **DNS cleanup**: Removes Pi-hole DNS records for workspace VMs (if they exist)
4. **Infrastructure cleanup**: Destroys all Terraform/OpenTofu managed resources only if they exist (VMs, networks, etc.)
5. **Workspace removal**: Deletes the Terraform/OpenTofu workspace
6. **Configuration cleanup**: Removes entries from Terraform locals.tf and validations.tf
7. **Snippet cleanup**: Removes cloud-init snippet files associated with the workspace's release letter
8. **Environment file deletion**: Removes the workspace's `.env` file from the `envs/` directory

### Optimized Performance
The delete command is optimized to avoid unnecessary operations:
- **Smart resource detection**: Checks workspace state before attempting any resource operations
- **No unnecessary VM creation**: Does not create resources just to destroy them
- **Selective cleanup**: Only performs cleanup operations for resources that actually exist

### Safety Features
- Cannot delete predefined base workspaces (debian, ubuntu, rocky, suse) which serve as templates
- Requires confirmation before destructive operations (use `--force` to skip)
- Performs intelligent resource state checking before cleanup operations
- Provides detailed feedback about each cleanup step
- Gracefully handles empty workspaces without unnecessary operations

### Warning
This command is **destructive** and will:
- Permanently delete all VMs and infrastructure associated with the workspace
- Remove all configuration files and mappings
- Cannot be undone

Always ensure you have backups of any important data before running this command.

This command complements the `clone-workspace` functionality and is part of the modular workspace system. For more details, see [Modular Workspace System](modular_workspace_system.md).
