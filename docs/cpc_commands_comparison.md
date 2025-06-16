# CPC Commands Comparison: run-ansible vs run-command

## Overview

The CPC tool provides two different ways to execute operations on remote hosts:
- `./cpc run-ansible` - Runs complete Ansible playbooks
- `./cpc run-command` - Runs single shell commands

## Key Differences

| Feature | `run-ansible` | `run-command` |
|---------|---------------|---------------|
| **Purpose** | Execute complex Ansible playbooks | Execute simple shell commands |
| **Complexity** | High - full automation workflows | Low - single commands |
| **Input** | Ansible playbook file (.yml) | Shell command string |
| **Use Cases** | Cluster deployment, configuration management | Quick diagnostics, simple tasks |
| **Error Handling** | Advanced Ansible error handling | Basic command success/failure |
| **Idempotency** | Yes (Ansible ensures idempotency) | No (commands run every time) |
| **Variables** | Full Ansible variable support | Limited to command_to_run |
| **Templating** | Full Jinja2 templating support | None |

## Usage Examples

### `./cpc run-ansible`
```bash
# Deploy entire Kubernetes cluster with DNS support
./cpc run-ansible initialize_kubernetes_cluster_with_dns.yml

# Regenerate certificates for existing cluster
./cpc run-ansible regenerate_certificates_with_dns.yml

# Add worker nodes with complex logic
./cpc run-ansible pb_add_nodes.yml -l workers -e "node_type=worker"

# Run with Ansible options
./cpc run-ansible validate_cluster.yml --check --diff
```

### `./cpc run-command`
```bash
# Check hostname on control plane
./cpc run-command control_plane "hostname -f"

# Update packages on all nodes
./cpc run-command all "sudo apt update"

# Check kubelet status on workers
./cpc run-command workers "systemctl status kubelet"

# Get Kubernetes nodes from control plane
./cpc run-command control_plane "kubectl get nodes"
```

## When to Use Each

### Use `./cpc run-ansible` when:
- ✅ Deploying or configuring complex services
- ✅ Need idempotent operations
- ✅ Require conditional logic and templating
- ✅ Managing cluster lifecycle (bootstrap, upgrade, etc.)
- ✅ Need structured error handling and rollback
- ✅ Working with Ansible variables and facts

**Examples:**
- Initializing Kubernetes clusters
- Installing and configuring addons
- Certificate management
- Node lifecycle management
- Backup and restore operations

### Use `./cpc run-command` when:
- ✅ Quick diagnostics and troubleshooting
- ✅ Simple one-off commands
- ✅ Checking status or gathering information
- ✅ Running ad-hoc administrative tasks
- ✅ Testing connectivity or services

**Examples:**
- Checking service status
- Gathering system information
- Quick fixes or restarts
- Log collection
- Network diagnostics

## Command Structure

### `./cpc run-ansible`
```bash
./cpc run-ansible <playbook_name> [ansible_options]
```

**Features:**
- Automatically uses Tofu inventory
- Sets ansible_user from ansible.cfg
- Passes cluster context and Kubernetes version
- Supports all ansible-playbook options (-l, -e, --check, --diff, etc.)

### `./cpc run-command`
```bash
./cpc run-command <target_group> "<command>"
```

**Features:**
- Simple target group selection
- Direct command execution
- Basic output display
- Uses pb_run_command.yml playbook internally

## Available Targets

Both commands support these target groups:

| Target | Description |
|--------|-------------|
| `all` | All nodes in the cluster |
| `control_plane` | Control plane nodes only |
| `workers` | Worker nodes only |
| `<specific_ip>` | Target specific node by IP |

## Behind the Scenes

### `./cpc run-ansible`
1. Loads CPC environment and secrets
2. Calls `run_ansible_playbook()` function
3. Executes full Ansible playbook with:
   - Tofu inventory
   - Cluster context variables
   - SSH configuration
   - User arguments

### `./cpc run-command`
1. Loads CPC environment and secrets
2. Calls `run_ansible_playbook("pb_run_command.yml")` 
3. Passes command as `command_to_run` variable
4. Uses simple command execution playbook

## Best Practices

### For `./cpc run-ansible`:
- Use for complex, repeatable operations
- Leverage existing playbooks when possible
- Create new playbooks for complex workflows
- Use Ansible best practices (idempotency, error handling)

### For `./cpc run-command`:
- Use for quick diagnostics and information gathering
- Keep commands simple and safe
- Use quotes around commands with spaces or special characters
- Be cautious with destructive operations

## Real-World Workflow

```bash
# 1. Use run-ansible for major operations
./cpc run-ansible initialize_kubernetes_cluster_with_dns.yml

# 2. Use run-command for quick checks
./cpc run-command control_plane "kubectl get nodes"

# 3. Use run-ansible for adding complexity
./cpc run-ansible pb_add_nodes.yml -l workers

# 4. Use run-command for verification
./cpc run-command all "systemctl status kubelet"

# 5. Use run-ansible for maintenance
./cpc run-ansible pb_upgrade_addons_extended.yml -e "addon_name=calico"
```

This combination provides both powerful automation and quick diagnostic capabilities for efficient cluster management.
