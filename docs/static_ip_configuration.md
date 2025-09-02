# Static IP Configuration for the Cluster

This documentation describes how to configure static IP addresses for Kubernetes cluster nodes in the CPC project, taking into account different workspaces.

## Why Static IP Addresses Are Needed

Static IP addresses are necessary to ensure stable operation of the Kubernetes cluster. Without static IP addresses:

1. When virtual machines are restarted, they may receive new IP addresses via DHCP
2. This leads to cluster failures as nodes lose connection with each other
3. Reconfiguration or cluster recovery is required

## Automatic IP Distribution by Workspaces

CPC uses a smart IP address distribution system that:

1. Automatically allocates IP address blocks for each workspace (ubuntu, debian, k8s133, etc.)
2. Takes into account the node role (control plane or worker) when assigning addresses
3. Prevents conflicts with existing static devices on your network
4. **Automatically manages workspace indexes** when creating or deleting workspaces

## Global Network Parameters Configuration

Global network settings are specified in the `cpc.env` file and apply to all workspaces:

```bash
# Network addressing and IP allocation
NETWORK_CIDR="10.10.10.0/24"            # Base network CIDR
NETWORK_GATEWAY="10.10.10.1"            # Network gateway (router)
STATIC_IP_START="110"                   # Starting IP for clusters (e.g., 110 for 10.10.10.110)
WORKSPACE_IP_BLOCK_SIZE="10"            # Number of IPs per workspace/cluster

# DNS settings
PRIMARY_DNS_SERVER="10.10.10.100"       # Primary DNS server (e.g. Pi-hole)
SECONDARY_DNS_SERVER="8.8.8.8"          # Secondary DNS server
```

These global settings are automatically exported as Terraform variables when executing any `cpc` command.

## Overriding Settings for a Specific Workspace

If necessary, you can override global settings for a specific workspace in its environment file:

```bash
# Override global network settings
export TF_VAR_network_cidr="192.168.1.0/24"     # Different subnet for this workspace
export TF_VAR_network_gateway="192.168.1.1"     # Different gateway
export TF_VAR_ip_range_start=200                # Start with IP .200
export TF_VAR_dns_servers='["192.168.1.10"]'    # Custom DNS server
```

## IP Address Distribution Scheme

The system automatically assigns IP addresses using the following formula:

```
IP = base_IP + (workspace_index * block_size) + node_offset
```

Where:
- `base_IP` - value of the `STATIC_IP_START` variable from `cpc.env` (default 110)
- `workspace_index` - position of the current workspace in the map (`ubuntu`=1, `debian`=2, ...)
- `block_size` - value of the `WORKSPACE_IP_BLOCK_SIZE` variable (default 10)
- `node_offset` - depends on the role and node index (control plane: 0-4, worker: 5-9)

### IP Distribution Examples (with ip_range_start=110, block_size=10)

1. **Ubuntu workspace (index 1)**:
   - Control Plane 1: `10.10.10.110`
   - Worker 1: `10.10.10.115`
   - Worker 2: `10.10.10.116`

2. **Debian workspace (index 2)**:
   - Control Plane 1: `10.10.10.120`
   - Worker 1: `10.10.10.125`
   - Worker 2: `10.10.10.126`

3. **k8s129-test workspace (index 3)**:
   - Control Plane 1: `10.10.10.130`
   - Worker 1: `10.10.10.135`
   - etc.

## Automatic Workspace Index Management

When creating and deleting workspaces through the `cpc clone-workspace` and `cpc delete-workspace` commands, the system automatically:

1. **When cloning a workspace**:
   - Finds the next available index in the `workspace_ip_map`
   - Adds a new workspace with this index
   - Calculates and displays the IP address range for the new workspace

2. **When deleting a workspace**:
   - Removes the entry from the `workspace_ip_map`
   - Frees the index for reuse
   - Other workspace indexes remain unchanged

**Important**: Workspace indexes are not renumbered when deleting a workspace from the middle of the list to maintain IP address stability for existing clusters.

## Accounting for Existing Devices

The system is designed to avoid conflicts with existing devices on your network:

1. Set the `STATIC_IP_START` value in `cpc.env` so that allocated ranges do not overlap with:
   - DHCP range (usually 10.10.10.2 - 10.10.10.99)
   - Existing devices with static IP (e.g., DNS, Proxmox, and others)

2. Recommended strategy:
   - DHCP range: 10.10.10.2 - 10.10.10.99
   - Infrastructure devices: 10.10.10.100 - 10.10.10.109
   - Kubernetes clusters: starting from 10.10.10.110

## Usage Example

1. **Creating a new workspace with automatic IP range allocation**:
   ```bash
   ./cpc clone-workspace ubuntu my-cluster m
   ```

2. **Checking the allocated range**:
   ```bash
   grep "my-cluster" ./terraform/variables.tf
   # Example output: "my-cluster" = 7 // IP-block #7: 10.10.10.170-179
   ```

3. **Deleting a workspace**:
   ```bash
   ./cpc delete-workspace my-cluster
   ```

## Precautions and Recommendations

1. Do not edit the `workspace_ip_map` manually - use the `cpc clone-workspace` and `cpc delete-workspace` commands
2. Make sure the selected IP addresses do not conflict with other devices on your network
3. If DHCP is used on the network, configure exceptions for static IP ranges
4. Changing IP addresses of existing cluster nodes may require cluster reconfiguration
