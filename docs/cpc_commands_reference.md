# CPC Commands Reference

This document provides a detailed reference for all commands available in the CPC (Cluster Provisioning Control) tool.

## Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `setup-cpc` | Initialize CPC and set repository path | `./cpc setup-cpc` |
| `ctx [<cluster_name>]` | Get or set the current cluster context (Tofu workspace) | `./cpc ctx ubuntu` |
| `clone-workspace <src> <dst>` | Clone a workspace environment to create a new one | `./cpc clone-workspace ubuntu k8s129` |
| `delete-workspace <n>` | Delete a workspace environment | `./cpc delete-workspace k8s129` |
| `template` | Creates a VM template for Kubernetes | `./cpc template` |
| `run-playbook <playbook>` | Run any Ansible playbook from ansible/playbooks/ | `./cpc run-playbook bootstrap.yml` |
| `run-command <target> "<cmd>"` | Run a shell command on target host(s) or group | `./cpc run-command control_plane "kubectl get nodes"` |
| `clear-ssh-hosts` | Clear VM IP addresses from ~/.ssh/known_hosts | `./cpc clear-ssh-hosts` |
| `clear-ssh-maps` | Clear SSH control sockets and connections for VMs | `./cpc clear-ssh-maps` |
| `load_secrets` | Load and display secrets from SOPS configuration | `./cpc load_secrets` |
| `dns-pihole <action>` | Manage Pi-hole DNS records (add/unregister-dns) | `./cpc dns-pihole add` |
| `generate-hostnames` | Generate hostname configurations for VMs in Proxmox | `./cpc generate-hostnames` |
| `scripts/<script_name>` | Run any script from the scripts directory | `./cpc scripts/test.sh` |
| `deploy <tofu_cmd> [opts]` | Run any 'tofu' command in context | `./cpc deploy apply` |

## VM Management

| Command | Description | Example |
|---------|-------------|---------|
| `add-vm` | Interactively add a new VM (worker or control plane) | `./cpc add-vm` |
| `remove-vm` | Interactively remove a VM and update configuration | `./cpc remove-vm` |
| `start-vms` | Start all VMs in the current context | `./cpc start-vms` |
| `stop-vms` | Stop all VMs in the current context | `./cpc stop-vms` |
| `vmctl` | (Placeholder) Suggests using Tofu for VM control | `./cpc vmctl` |

## Kubernetes Management

| Command | Description | Example |
|---------|-------------|---------|
| `bootstrap` | Bootstrap a complete Kubernetes cluster on deployed VMs | `./cpc bootstrap` |
| `get-kubeconfig` | Retrieve and merge Kubernetes cluster config into local kubeconfig | `./cpc get-kubeconfig` |
| `add-nodes` | Add new worker nodes to the cluster | `./cpc add-nodes` |
| `remove-nodes` | Remove nodes from the Kubernetes cluster | `./cpc remove-nodes` |
| `upgrade-addons` | Install/upgrade cluster addons with interactive menu | `./cpc upgrade-addons` |
| `configure-coredns` | Configure CoreDNS to forward local domain queries to Pi-hole | `./cpc configure-coredns` |
| `upgrade-k8s` | Upgrade Kubernetes control plane | `./cpc upgrade-k8s` |

## Node Management

| Command | Description | Example |
|---------|-------------|---------|
| `drain-node <node_name>` | Drain workloads from a node | `./cpc drain-node worker-1` |
| `upgrade-node <node_name>` | Upgrade Kubernetes on a specific node | `./cpc upgrade-node worker-1` |
| `reset-node <node_name>` | Reset Kubernetes on a specific node | `./cpc reset-node worker-1` |
| `reset-all-nodes` | Reset Kubernetes on all nodes in the current context | `./cpc reset-all-nodes` |

## Legacy Commands (Deprecated)

These commands are deprecated but still work with warnings and automatic redirection:

| Deprecated Command | Use Instead | Description |
|-------------------|-------------|-------------|
| `add-node` | `add-vm` | Legacy alias for adding VMs |
| `remove-node` | `remove-vm` | Legacy alias for removing VMs |
| `update-pihole` | `dns-pihole` | Legacy alias for Pi-hole DNS management |
| `delete-node` | `remove-nodes` | Legacy alias for removing nodes from cluster |

## Command Help

## Utility Commands

| Command | Description | Example |
|---------|-------------|---------|
| `update-pihole` | Manage Pi-hole DNS records | `./cpc update-pihole add` |
| `clear-ssh-hosts` | Clear VM IPs from SSH known hosts | `./cpc clear-ssh-hosts` |
| `clear-ssh-maps` | Clear SSH control sockets for VMs | `./cpc clear-ssh-maps` |
| `generate-hostnames` | Generate hostname configs for VMs | `./cpc generate-hostnames` |

## Node Naming Convention

CPC supports two formats for node naming in the `ADDITIONAL_WORKERS` and `ADDITIONAL_CONTROLPLANES` variables:

1. **Legacy Format**: Simple incremental names (`worker3`, `worker4`, `controlplane2`)
2. **Recommended Format**: Explicit index names (`worker-3`, `worker-4`, `controlplane-2`)

The explicit index format is recommended as it provides stable VM IDs and prevents unintended VM recreation when removing nodes. For more details, see [Node Naming Convention](node_naming_convention.md).

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

## Command Help

All commands support `--help` or `-h` for detailed usage information:

```bash
./cpc <command> --help
```

### Examples
```bash
./cpc bootstrap --help
./cpc get-kubeconfig --help
./cpc add-vm --help
```

## Command Categories Explanation

### Core Commands
Basic workspace and configuration management commands that are essential for initial setup and context management.

### VM Management  
Commands for managing virtual machine infrastructure, including creation, removal, and power management. These commands handle the underlying VM infrastructure without Kubernetes-specific operations.

### Kubernetes Management
Commands specifically for managing Kubernetes cluster operations, including bootstrapping, configuration, and cluster-level operations.

### Node Management
Commands for managing individual Kubernetes nodes, including lifecycle operations like draining, upgrading, and resetting specific nodes.

## Getting Started

1. **Initial Setup**: `./cpc setup-cpc`
2. **Set Context**: `./cpc ctx <workspace_name>`
3. **Create VMs**: `./cpc deploy apply`
4. **Bootstrap Cluster**: `./cpc bootstrap`
5. **Get Kubeconfig**: `./cpc get-kubeconfig`

For detailed workflow information, see [Complete Workflow Guide](complete_workflow_guide.md).
