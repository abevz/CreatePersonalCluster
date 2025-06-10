# Ansible Playbooks

This directory contains all Ansible playbooks for the **my-kthw** Kubernetes cluster deployment and management.

## Core Deployment Playbooks

### Primary Installation
- `install_kubernetes_cluster.yml` - Complete Kubernetes cluster installation (kubelet, kubeadm, kubectl, containerd)
- `initialize_kubernetes_cluster.yml` - Initialize cluster, setup CNI (Calico), join nodes
- `main.yml` - Main playbook that orchestrates the complete deployment

### Cluster Management
- `validate_cluster.yml` - Validate cluster health and configuration
- `pb_reset_all_nodes.yml` - Reset entire cluster to clean state
- `pb_reset_node.yml` - Reset specific node
- `pb_add_nodes.yml` - Add new nodes to existing cluster
- `pb_delete_node.yml` - Remove node from cluster
- `pb_drain_node.yml` - Safely drain node before maintenance

### Upgrades and Maintenance
- `pb_upgrade_k8s_control_plane.yml` - Upgrade Kubernetes control plane
- `pb_upgrade_node.yml` - Upgrade worker nodes
- `pb_upgrade_addons.yml` - Upgrade cluster addons (Calico, CoreDNS)
- `pb_upgrade_addons_extended.yml` - Extended addon upgrades with additional components

### Utilities
- `pb_run_command.yml` - Execute commands across cluster nodes
- `install_terraform_tools.yml` - Install Terraform/OpenTofu tools

## Usage Examples

### Complete Cluster Deployment
```bash
# Full cluster setup (recommended)
ansible-playbook -i inventory/tofu_inventory.py main.yml

# Step-by-step deployment
ansible-playbook -i inventory/tofu_inventory.py install_kubernetes_cluster.yml
ansible-playbook -i inventory/tofu_inventory.py initialize_kubernetes_cluster.yml
```

### Cluster Management
```bash
# Validate cluster
ansible-playbook -i inventory/tofu_inventory.py validate_cluster.yml

# Add new worker node
ansible-playbook -i inventory/tofu_inventory.py pb_add_nodes.yml -e target_node=wu3

# Reset entire cluster
ansible-playbook -i inventory/tofu_inventory.py pb_reset_all_nodes.yml
```

### Upgrades
```bash
# Upgrade control plane
ansible-playbook -i inventory/tofu_inventory.py pb_upgrade_k8s_control_plane.yml

# Upgrade all addons
ansible-playbook -i inventory/tofu_inventory.py pb_upgrade_addons_extended.yml
```

## Playbook Variables

Key variables used across playbooks (defined in group_vars or passed via `-e`):

```yaml
kubernetes_version: "1.31.9"
containerd_version: "1.7.27"
calico_version: "v3.28.0"
pod_cidr: "192.168.0.0/16"
service_cidr: "10.96.0.0/12"
```

## Prerequisites

- **Dynamic Inventory**: Functional `tofu_inventory.py` with Terraform outputs
- **SSH Access**: Key-based authentication to all nodes
- **SOPS**: For encrypted variable access
- **Target VMs**: VMs created and accessible via Terraform/Proxmox

## Supported Operating Systems

- **Ubuntu 24.04** ✅ - Fully tested and production ready
- **SUSE** ✅ - Production ready
- **Debian** 🚧 - In development
- **Rocky Linux** 🚧 - In development
