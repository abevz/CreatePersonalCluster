# CPC Auto Environment Loading

## Overview
CPC now supports automatic loading of environment variables into your shell session. This allows you to access secrets and configuration variables in your terminal without running `cpc load_secrets` manually.

## Commands

### `cpc auto`
Loads all environment variables and outputs export commands for shell sourcing.

```bash
# View available variables
./cpc auto

# Load variables into current shell
eval "$(./cpc auto 2>/dev/null | grep -E '^export ')"

# Load variables into new shell
zsh -c 'eval "$(./cpc auto 2>/dev/null | grep -E \"^export \")" && ./cpc ctx'
```

### `cpc-auto` script
Simple wrapper script for loading environment variables.

```bash
# Load variables into current shell
./cpc-auto

# Use in new shell
zsh -c './cpc-auto && ./cpc ctx'
```

## What gets loaded

The auto-loading system loads variables from:

1. **Global configuration** (`cpc.env`):
   - Proxmox connection settings
   - General project configuration

2. **Workspace configuration** (`envs/{context}.env`):
   - Kubernetes versions
   - VM specifications
   - DNS settings
   - Template configurations

3. **Secrets** (`terraform/secrets.sops.yaml`):
   - Proxmox credentials
   - SSH keys
   - Cloud provider credentials
   - Docker registry credentials

## Usage Examples

```bash
# Load variables and run tofu
./cpc-auto && tofu plan

# Load variables and check cluster status
./cpc-auto && ./cpc cluster-info

# Use in scripts
#!/bin/bash
./cpc-auto
echo "Using TEMPLATE_VM_ID: $TEMPLATE_VM_ID"
echo "Using AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
```

## Troubleshooting

If you encounter AWS credential errors in tofu/OpenTofu, make sure to load the environment variables first:

```bash
./cpc-auto && tofu workspace select k8s133
```