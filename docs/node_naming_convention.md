# Node Naming Convention

## Overview

This document describes the node naming convention used in the CPC (Cluster Provisioning Control) system for identifying and managing Kubernetes nodes.

## Background

Previously, CPC used a simple incremental naming system for worker nodes (`worker1`, `worker2`, `worker3`, etc.) and control plane nodes (`controlplane`, `controlplane2`, etc.). While this approach was simple, it created problems when removing nodes from a cluster:

- When a node (e.g., `worker3`) was removed, Terraform/OpenTofu would reindex all subsequent nodes
- This reindexing would cause all nodes after the removed one to be recreated
- For example, removing `worker3` would also affect `worker4`, requiring it to be recreated with a new VM ID
- This behavior could lead to unexpected data loss if important data was stored on affected nodes

## Current Solution: Explicit Index Node Naming

To solve this problem, we've implemented an explicit index naming convention:

### Format

- Worker nodes: `worker-N` (e.g., `worker-3`, `worker-5`)
- Control plane nodes: `controlplane-N` (e.g., `controlplane-2`, `controlplane-3`)

### Advantages

- Each node has a stable, explicit index that doesn't depend on its position in the list
- Removing a node doesn't affect other nodes with different indices
- VMs maintain their identity and VM ID across cluster operations
- Prevents unexpected data loss when modifying the cluster

### Examples

```
# Old Format (position-based)
ADDITIONAL_WORKERS="worker3,worker4,worker5"

# New Format (explicit indices)
ADDITIONAL_WORKERS="worker-3,worker-4,worker-5"
```

## Backward Compatibility

The system maintains backward compatibility with the old naming format:

- Both formats (`worker3` and `worker-3`) are recognized and supported
- For new nodes, the explicit index format (`worker-N`) is recommended
- When using the `add-vm` command, nodes are automatically created with the new format

## Implementation Details

The node naming system is implemented across several components:

### In Terraform (`locals.tf`)

The system uses regular expressions to extract the node index from both formats:
```terraform
# Extract index from name if it matches worker{NUMBER} pattern
node_index = can(regex("^worker(\\d+)$", worker_name)) ? tonumber(regex("^worker(\\d+)$", worker_name)[0]) : (
  # If name has format worker-N, extract N
  can(regex("^worker-(\\d+)$", worker_name)) ? tonumber(regex("^worker-(\\d+)$", worker_name)[0]) : (3 + i)
)
```

### In the CPC Script

- The `add-vm` function creates nodes with the new explicit index format
- The `remove-vm` function handles both formats for backward compatibility

## Best Practices

1. **Use the new format for all new nodes**:
   ```
   ADDITIONAL_WORKERS="worker-3,worker-4,worker-5"
   ```

2. **Consider migrating existing clusters** to the new naming format:
   - Remove nodes one by one using the old format
   - Add them back using the new format
   - This prevents any disruption to the cluster

3. **Avoid mixing formats** within the same node type:
   ```
   # Not recommended
   ADDITIONAL_WORKERS="worker-3,worker4,worker-5"
   
   # Better
   ADDITIONAL_WORKERS="worker-3,worker-4,worker-5"
   ```

## Technical Notes

- In Proxmox tags, we use a dash (`-`) as the separator because colons (`:`) are not allowed in Proxmox tags
- The explicit index is used to determine VM IDs and ensure they remain stable
