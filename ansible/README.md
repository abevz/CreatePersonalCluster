# Ansible Configuration

This directory contains Ansible playbooks, roles, and inventory configurations for the **my-kthw** Kubernetes cluster deployment.

## Structure

```
ansible/
├── ansible.cfg          # Ansible configuration file
├── inventory/           # Dynamic and static inventory
├── playbooks/          # Ansible playbooks
└── roles/              # Custom Ansible roles
```

## Key Files

### Configuration
- `ansible.cfg` - Ansible configuration with optimized settings for Kubernetes deployment

### Inventory
- `inventory/tofu_inventory.py` - Dynamic inventory script that reads Terraform/OpenTofu outputs
- `inventory/static_inventory.yml` - Static inventory file (if needed)

### Main Playbooks
- `playbooks/install_kubernetes_cluster.yml` - Complete Kubernetes cluster installation
- `playbooks/initialize_kubernetes_cluster.yml` - Cluster initialization and CNI setup
- `playbooks/reset_kubernetes_cluster.yml` - Reset cluster to clean state

## Usage

### Full Cluster Deployment
```bash
# Install Kubernetes components on all nodes
ansible-playbook -i ansible/inventory/tofu_inventory.py ansible/playbooks/install_kubernetes_cluster.yml

# Initialize cluster and install CNI
ansible-playbook -i ansible/inventory/tofu_inventory.py ansible/playbooks/initialize_kubernetes_cluster.yml
```

### Individual Operations
```bash
# Check connectivity to all nodes
ansible all -i ansible/inventory/tofu_inventory.py -m ping

# Run specific playbook
ansible-playbook -i ansible/inventory/tofu_inventory.py ansible/playbooks/specific_playbook.yml
```

## Supported Workspaces

- **Ubuntu 24.04** ✅ - Fully tested and supported
- **SUSE** ✅ - Production ready
- **Debian** 🚧 - In development
- **Rocky Linux** 🚧 - In development

## Configuration

### Key Variables
```yaml
kubernetes_version: "1.31.9"
containerd_version: "1.7.27"
calico_version: "v3.28.0"
pod_cidr: "192.168.0.0/16"
service_cidr: "10.96.0.0/12"
```

### Inventory Requirements
The dynamic inventory script requires:
- Terraform/OpenTofu state with VM outputs
- SSH key access to all nodes
- Proper DNS resolution for hostnames

## Dependencies

- **Ansible** 2.15+
- **Python 3** with required modules
- **SSH access** to all target nodes
- **Terraform/OpenTofu** state files
- **SOPS** for encrypted variables
