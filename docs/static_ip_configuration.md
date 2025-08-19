# Static IP Address Configuration for the Cluster

This documentation describes how to configure static IP addresses for Kubernetes cluster nodes in the CPC project, taking into account different workspaces.

## Why Static IP Addresses are Needed

Static IP addresses are necessary to ensure the stable operation of a Kubernetes cluster. Without static IP addresses:

1. When virtual machines are restarted, they may receive new IP addresses via DHCP.
2. This leads to cluster failures as nodes lose communication with each other.
3. The cluster needs to be reconfigured or restored.

## Automatic IP Distribution Across Workspaces

CPC uses an intelligent IP address distribution system that:

1. Automatically allocates blocks of IP addresses for each workspace (ubuntu, debian, k8s133, etc.).
2. Considers the node's role (control plane or worker) when assigning addresses.
3. Prevents conflicts with existing static devices on your network.
4. **Automatically manages workspace indices** when creating or deleting workspaces.

## Global Network Parameter Configuration

Global network settings are defined in the `cpc.env` file and apply to all workspaces:

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

These global settings are automatically exported as Terraform variables when any `cpc` command is executed.

## Overriding Settings for a Specific Workspace

If necessary, you can override the global settings for a specific workspace in its environment file:

```bash
# Overriding global network settings
export TF_VAR_network_cidr="192.168.1.0/24"     # Different subnet for this workspace
export TF_VAR_network_gateway="192.168.1.1"     # Different gateway
export TF_VAR_ip_range_start=200                # Start with IP .200
export TF_VAR_dns_servers='["192.168.1.10"]'    # Custom DNS server
```

## IP Address Allocation Scheme

The system automatically assigns IP addresses according to the following formula:

```
IP = base_IP + (workspace_index * block_size) + node_offset
```

Where:
- `base_IP` - is the value of the `STATIC_IP_START` variable from `cpc.env` (default 110)
- `workspace_index` - is the position of the current workspace in the map (`ubuntu`=1, `debian`=2, ...)
- `block_size` - is the value of the `WORKSPACE_IP_BLOCK_SIZE` variable (default 10)
- `node_offset` - depends on the role and index of the node (control plane: 0-4, worker: 5-9)

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
   - and so on.

## Automatic Workspace Index Management

When creating and deleting workspaces via the `cpc clone-workspace` and `cpc delete-workspace` commands, the system automatically:

1. **When cloning a workspace**:
   - Finds the next available index in the `workspace_ip_map`
   - Adds the new workspace with this index
   - Calculates and displays the IP address range for the new workspace

2. **When deleting a workspace**:
   - Removes the entry from the `workspace_ip_map`
   - Frees up the index for reuse
   - The indices of other workspaces remain unchanged

**Important**: Workspace indices are not re-numbered when a workspace is deleted from the middle of the list, to maintain IP address stability for existing clusters.

## Accounting for Existing Devices

The system is designed to avoid conflicts with existing devices on your network:

1. Set the `STATIC_IP_START` value in `cpc.env` so that the allocated ranges do not overlap with:
   - The DHCP range (usually 10.10.10.2 - 10.10.10.99)
   - Existing devices with static IPs (e.g., DNS, Proxmox, and others)

2. Recommended strategy:
   - DHCP range: 10.10.10.2 - 10.10.10.99
   - Infrastructure devices: 10.10.10.100 - 10.10.10.109
   - Kubernetes clusters: starting from 10.10.10.110

## Usage Example

1. **Create a new workspace with automatic IP range allocation**:
   ```bash
   ./cpc clone-workspace ubuntu my-cluster m
   ```

2. **Check the allocated range**:
   ```bash
   grep "my-cluster" ./terraform/variables.tf
   # Example output: "my-cluster" = 7 // IP block #7: 10.10.10.170-179
   ```

3. **Delete a workspace**:
   ```bash
   ./cpc delete-workspace my-cluster
   ```

## Cautions and Recommendations

1. Do not edit the `workspace_ip_map` manually - use the `cpc clone-workspace` and `cpc delete-workspace` commands.
2. Ensure that the selected IP addresses do not conflict with other devices on your network.
3. If DHCP is used on the network, configure exclusions for the static IP ranges.
4. Changing the IP addresses of existing cluster nodes may require re-configuring the cluster.