# SSH Management Commands

This document covers the SSH management commands available in the CPC (Cluster Provisioning Control) system for handling SSH connection issues when working with VMs.

## Overview

When working with dynamically provisioned VMs, SSH connection issues can occur due to:
- VMs being recreated with the same IP addresses but new SSH keys
- Stale SSH control sockets preventing new connections
- SSH known_hosts entries causing key conflicts

The CPC system provides two commands to handle these issues:

## Commands

### `cpc clear-ssh-hosts`

Clears VM IP addresses from `~/.ssh/known_hosts` to resolve SSH key conflicts when VMs are recreated.

#### Usage
```bash
cpc clear-ssh-hosts [--all] [--dry-run]
```

#### Options
- `--all`: Clear all VM IPs from all contexts (not just current)
- `--dry-run`: Show what would be removed without actually removing

#### Examples
```bash
# Clear IPs from current context
cpc clear-ssh-hosts

# Clear IPs from all contexts
cpc clear-ssh-hosts --all

# Preview what would be removed
cpc clear-ssh-hosts --dry-run
```

### `cpc clear-ssh-maps`

Clears SSH control sockets and active connections for VMs to resolve SSH connection issues when VMs are recreated or SSH configurations change.

#### Usage
```bash
cpc clear-ssh-maps [--all] [--dry-run]
```

#### Options
- `--all`: Clear SSH connections for all contexts (not just current)
- `--dry-run`: Show what would be cleared without actually clearing

#### What It Does
1. Gets VM IP addresses from current Terraform/Tofu outputs
2. Closes active SSH connections to those IPs
3. Removes SSH control sockets (if ControlMaster is enabled)
4. Attempts to close SSH master connections using `ssh -O exit`
5. Displays summary of cleared connections

#### Examples
```bash
# Clear SSH connections for current context
cpc clear-ssh-maps

# Clear SSH connections for all contexts
cpc clear-ssh-maps --all

# Preview what would be cleared
cpc clear-ssh-maps --dry-run
```

## When to Use These Commands

### Use `clear-ssh-hosts` when:
- You get "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!" errors
- SSH connections are rejected due to key mismatches
- You've recreated VMs with the same IP addresses

### Use `clear-ssh-maps` when:
- SSH connections hang or timeout
- You get "ControlSocket already exists" errors
- You need to force new SSH connections after VM changes
- SSH multiplexing is causing connection issues

## Common SSH Issues and Solutions

### Issue 1: SSH Key Verification Failed
```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
```

**Solution:**
```bash
cpc clear-ssh-hosts
```

### Issue 2: SSH Connection Hangs
```
ssh: connect to host 10.10.10.61 port 22: Connection timed out
```

**Solution:**
```bash
cpc clear-ssh-maps
```

### Issue 3: ControlMaster Socket Issues
```
ControlSocket /home/user/.ssh/master-user@10.10.10.61:22 already exists, disabling multiplexing
```

**Solution:**
```bash
cpc clear-ssh-maps
```

### Issue 4: After VM Recreation
When you recreate VMs and need to clear both SSH artifacts:

```bash
# Clear both known_hosts and control sockets
cpc clear-ssh-hosts
cpc clear-ssh-maps
```

## SSH Control Socket Locations

The `clear-ssh-maps` command searches for SSH control sockets in these common locations:

- `$HOME/.ssh/sockets/`
- `$HOME/.ssh/connections/`
- `$HOME/.ssh/master/`
- `/tmp/`

## Safety Features

### Backup Creation
The `clear-ssh-hosts` command automatically creates a backup of your `known_hosts` file:
```
~/.ssh/known_hosts.backup.20250610_143022
```

### Dry Run Mode
Both commands support `--dry-run` to preview changes without applying them.

### Context Awareness
Both commands automatically detect VM IPs from your current Terraform/Tofu workspace context.

## Integration with CPC Workflow

These commands integrate seamlessly with the CPC deployment workflow:

### Typical Workflow with SSH Cleanup
```bash
# Deploy infrastructure
cpc deploy apply

# Clear any stale SSH artifacts (recommended after VM recreation)
cpc clear-ssh-hosts
cpc clear-ssh-maps

# Bootstrap cluster
cpc bootstrap

# Get cluster access
cpc get-kubeconfig
```

### Automated Cleanup
For convenience, you can combine commands:
```bash
# Clear both SSH artifacts in one go
cpc clear-ssh-hosts && cpc clear-ssh-maps
```

## Automatic SSH Host Key Handling

### Bootstrap Command Integration

As of the latest version, the `cpc bootstrap` command automatically handles SSH host key verification to prevent interactive prompts during cluster deployment. The bootstrap process uses the following SSH options:

- `StrictHostKeyChecking=no` - Automatically accepts new host keys
- `UserKnownHostsFile=/dev/null` - Doesn't save host keys to known_hosts

This means you no longer need to manually clear SSH host keys before running bootstrap on freshly created VMs.

### When Manual SSH Management is Still Needed

While bootstrap handles SSH automatically, you may still need manual SSH management in these scenarios:

- **Interactive SSH sessions**: When manually connecting to VMs
- **Custom Ansible playbooks**: When running your own playbooks outside of CPC
- **Troubleshooting**: When SSH connections are hung or corrupted
- **Development workflow**: When frequently recreating VMs for testing

## Troubleshooting

### No VMs Found
If the commands report "No VMs found":
1. Ensure VMs are deployed: `cpc deploy apply`
2. Check current context: `cpc ctx`
3. Verify Terraform outputs: `cpc deploy output`

### Permission Issues
If you get permission errors:
1. Check SSH key permissions: `ls -la ~/.ssh/`
2. Ensure your user owns the SSH files
3. Verify SSH agent is running: `ssh-add -l`

### Multiple Contexts
When working with multiple contexts:
```bash
# List all contexts
cpc ctx

# Clear SSH artifacts for all contexts
cpc clear-ssh-hosts --all
cpc clear-ssh-maps --all
```

## Best Practices

1. **Run after VM recreation**: Always clear SSH artifacts when recreating VMs
2. **Use dry-run first**: Preview changes before applying them
3. **Clear both commands**: Use both commands when troubleshooting SSH issues
4. **Regular maintenance**: Clear SSH artifacts periodically during development
5. **Context awareness**: Be aware of which context you're working in

## See Also

- [Bootstrap Command Guide](bootstrap_command_guide.md) - For cluster deployment
- [Complete Workflow Guide](complete_workflow_guide.md) - For end-to-end process
- [SSH Key Troubleshooting](ssh_key_troubleshooting.md) - For SSH key issues

## Bug Fixes

### SSH Commands Workspace Context Preservation

**Fixed**: SSH management commands (`clear-ssh-hosts` and `clear-ssh-maps`) now properly preserve the current Tofu workspace context when using the `--all` option.

**Problem**: When using `--all` option, these commands would switch through different Tofu workspaces to collect VM IPs but wouldn't restore the original workspace, causing the context to "drift" to the last workspace checked.

**Solution**: Both commands now save and restore the original Tofu workspace context after checking all workspaces.
