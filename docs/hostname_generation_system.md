# Hostname Generation System

## Overview

The CPC system uses a structured approach to generate hostnames for Kubernetes cluster nodes. This document explains how the hostname generation works and the role of the `RELEASE_LETTER` variable.

## Hostname Pattern

All VM hostnames follow this pattern:
```
<role><release_letter><index>.<domain>
```

Where:
- **role**: Single character representing the node role
  - `c` = controlplane (master) node
  - `w` = worker node
- **release_letter**: Single character from the workspace's `RELEASE_LETTER` variable
- **index**: Sequential number starting from 1
- **domain**: Domain suffix from `VM_DOMAIN` variable

## Examples

For a workspace with `RELEASE_LETTER=k` and `VM_DOMAIN=".bevz.net"`:

| Node Type | Hostname | Full FQDN |
|-----------|----------|-----------|
| Controlplane 1 | ck1 | ck1.bevz.net |
| Worker 1 | wk1 | wk1.bevz.net |
| Worker 2 | wk2 | wk2.bevz.net |

For a workspace with `RELEASE_LETTER=u` and `VM_DOMAIN=".bevz.net"`:

| Node Type | Hostname | Full FQDN |
|-----------|----------|-----------|
| Controlplane 1 | cu1 | cu1.bevz.net |
| Worker 1 | wu1 | wu1.bevz.net |
| Worker 2 | wu2 | wu2.bevz.net |

## RELEASE_LETTER Configuration

### In Workspace Environment Files

The `RELEASE_LETTER` variable is defined in each workspace's `.env` file:

```bash
# In envs/k8s129.env
RELEASE_LETTER=k

# In envs/ubuntu.env  
RELEASE_LETTER=u

# In envs/debian.env
RELEASE_LETTER=d
```

### Automatic Assignment

When creating a new workspace using `clone-workspace`, the release letter can be:

1. **Explicitly specified**:
   ```bash
   cpc clone-workspace ubuntu k8s130 t
   # Creates workspace k8s130 with RELEASE_LETTER=t
   ```

2. **Auto-generated** from the first letter of the workspace name:
   ```bash
   cpc clone-workspace ubuntu testing
   # Creates workspace testing with RELEASE_LETTER=t
   ```

### Fallback Mechanism

If `RELEASE_LETTER` is not found in the workspace file, the system falls back to a predefined mapping:

| Workspace | Default Letter |
|-----------|----------------|
| debian | d |
| ubuntu | u |
| rocky | r |
| suse | s |
| others | x |

## Implementation Details

### Script Location

The hostname generation logic is implemented in:
- `scripts/generate_node_hostnames.sh` - Main generation script
- `terraform/locals.tf` - Terraform variable mapping

### Generation Process

1. **Environment Loading**: The script loads the workspace's `.env` file
2. **Letter Resolution**: Determines the release letter using the priority:
   - Environment variable `RELEASE_LETTER`
   - Value from workspace `.env` file
   - Fallback mapping based on workspace name
3. **Hostname Creation**: Generates hostnames using the pattern
4. **Cloud-init Generation**: Creates cloud-init snippets with the correct hostnames

### Terraform Integration

The release letter is also mapped in Terraform's `locals.tf`:

```hcl
locals {
  release_letters_map = {
    "debian"  = "d"
    "ubuntu"  = "u"
    "rocky"   = "r"
    "suse"    = "s"
    "k8s129"  = "k"
    # Additional workspaces added via clone-workspace
  }
  
  release_letter = var.release_letter != "" ? var.release_letter : lookup(local.release_letters_map, local.effective_os_type, "x")
}
```

## Best Practices

### Choosing Release Letters

1. **Use meaningful letters**: Choose letters that relate to the workspace purpose
   - `k` for Kubernetes version-specific workspaces (k8s129)
   - `t` for testing environments
   - `p` for production environments

2. **Avoid conflicts**: Ensure each workspace has a unique release letter to prevent hostname collisions

3. **Keep it simple**: Use single lowercase letters for consistency

### Workspace Naming

When creating workspaces, consider both the workspace name and the desired release letter:

```bash
# Good examples
cpc clone-workspace ubuntu k8s129 k    # Clear version indication
cpc clone-workspace ubuntu prod p      # Clear environment indication
cpc clone-workspace ubuntu test t      # Clear purpose indication

# Less ideal (but functional)
cpc clone-workspace ubuntu random-name x  # Generic letter
```

## Troubleshooting

### Common Issues

1. **Duplicate release letters**: Multiple workspaces using the same letter
   - **Solution**: Update `RELEASE_LETTER` in the workspace's `.env` file

2. **Missing release letter**: Workspace file without `RELEASE_LETTER` defined
   - **Solution**: Add `RELEASE_LETTER=<letter>` to the workspace's `.env` file

3. **Hostname conflicts**: VMs with identical hostnames
   - **Solution**: Ensure unique release letters across active workspaces

### Debugging

To check the current release letter resolution:

```bash
# Switch to workspace
cpc ctx <workspace>

# Check what release letter will be used
./cpc deploy plan | grep "Using RELEASE_LETTER"

# Manually run hostname generation to see the process
cd scripts
./generate_node_hostnames.sh
```

## Migration Notes

For existing workspaces that don't have `RELEASE_LETTER` defined:

1. **Add the variable** to the workspace's `.env` file:
   ```bash
   echo "RELEASE_LETTER=<desired_letter>" >> envs/<workspace>.env
   ```

2. **Update Terraform mapping** in `terraform/locals.tf` if needed:
   ```hcl
   # Add entry to release_letters_map
   "<workspace>" = "<letter>"
   ```

3. **Regenerate hostnames** if necessary:
   ```bash
   cpc ctx <workspace>
   cpc deploy plan  # This will regenerate with the new letter
   ```
