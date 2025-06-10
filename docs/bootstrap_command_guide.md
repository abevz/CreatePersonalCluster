# CPC Bootstrap Command Guide

## Overview

The `cpc bootstrap` command provides a streamlined way to deploy a complete Kubernetes cluster on VMs provisioned through Proxmox. This command automates the entire cluster setup process from component installation to cluster validation.

## Command Syntax

```bash
cpc bootstrap [--skip-check] [--force]
```

## Options

- `--skip-check`: Skip VM connectivity verification before starting bootstrap
- `--force`: Force bootstrap even if a cluster appears to already be initialized
- `--help`: Display detailed help information

## Prerequisites

### Infrastructure Requirements
1. **VMs Deployed**: VMs must be created and accessible via `cpc deploy apply`
2. **SSH Access**: Key-based SSH authentication configured to all nodes
3. **SOPS Secrets**: Sensitive data loaded via `cpc load_secrets` or automatic loading
4. **Network Connectivity**: All VMs must be reachable and have internet access

### Context Setup
```bash
# Set the cluster context (workspace)
cpc ctx ubuntu              # or: suse, rocky, debian

# Verify context is set
cpc ctx
```

## Bootstrap Process

The bootstrap command executes the following steps automatically:

### Step 1: Pre-flight Checks
- Verifies VM connectivity via Terraform outputs
- Tests Ansible connectivity to all nodes (with automatic SSH host key acceptance)
- Checks if cluster is already initialized (unless `--force` is used)

**Note**: The bootstrap process automatically handles SSH host key verification, so you won't be prompted to accept new SSH keys during deployment.

### Step 2: Component Installation
- Installs container runtime (containerd)
- Installs Kubernetes components (kubelet, kubeadm, kubectl)
- Configures system settings and networking
- Enables required kernel modules

### Step 3: Cluster Initialization
- Initializes control plane with `kubeadm init`
- Installs Calico CNI plugin for pod networking
- Generates join tokens for worker nodes
- Joins worker nodes to the cluster

### Step 4: Validation
- Verifies all nodes are in Ready state
- Tests pod deployment and networking
- Validates DNS resolution within cluster

## Usage Examples

### Basic Cluster Deployment
```bash
# Complete workflow from start to finish
cpc ctx ubuntu
cpc template                    # Create VM template (if needed)
cpc deploy apply               # Deploy VMs
cpc bootstrap                  # Bootstrap Kubernetes cluster
cpc get-kubeconfig            # Get cluster access
kubectl get nodes -o wide     # Verify cluster
```

### Force Re-bootstrap
```bash
# Reset and re-bootstrap existing cluster
cpc reset-all-nodes           # Optional: reset existing cluster
cpc bootstrap --force         # Force new bootstrap
```

### Skip Connectivity Checks
```bash
# Skip pre-flight checks (for debugging)
cpc bootstrap --skip-check
```

## Post-Bootstrap Steps

After successful bootstrap, consider these next steps:

### 1. Install Cluster Addons
```bash
# Install all recommended addons
cpc upgrade-addons --addon all

# Or install specific addons
cpc upgrade-addons --addon calico
cpc upgrade-addons --addon metallb
cpc upgrade-addons --addon cert-manager
cpc upgrade-addons --addon metrics-server
```

### 2. Validate Cluster Health
```bash
# Check node status
kubectl get nodes -o wide

# Check system pods
kubectl get pods --all-namespaces

# Run cluster validation
ansible-playbook -i ansible/inventory/tofu_inventory.py ansible/playbooks/validate_cluster.yml
```

### 3. Deploy Test Workload
```bash
# Deploy test application
kubectl create deployment test-nginx --image=nginx --replicas=2
kubectl expose deployment test-nginx --port=80 --type=LoadBalancer

# Verify deployment
kubectl get pods -o wide
kubectl get services

# Cleanup
kubectl delete deployment test-nginx
kubectl delete service test-nginx
```

## Troubleshooting

### Common Issues

#### 1. VM Connectivity Failures
```bash
# Check VMs are running
cpc deploy output k8s_node_ips

# Test SSH manually
ssh abevz@<vm-ip>

# Verify Ansible inventory
ansible all -i ansible/inventory/tofu_inventory.py -m ping
```

#### 2. Cluster Already Initialized
```bash
# If cluster exists but you want to re-bootstrap
cpc reset-all-nodes
cpc bootstrap --force
```

#### 3. Network Issues
```bash
# Check DNS resolution
nslookup google.com

# Verify firewall settings
sudo ufw status
sudo systemctl status firewalld
```

#### 4. Package Installation Failures
```bash
# Check repository access
curl -I https://packages.cloud.google.com/apt/

# Update package cache manually
ansible all -i ansible/inventory/tofu_inventory.py -m shell -a "apt update"
```

### Common Issues and Solutions

#### 1. SSH Host Key Verification
**Problem**: SSH prompts for host key verification during bootstrap
**Solution**: This is now handled automatically by the bootstrap process. If you still encounter issues:

```bash
# Clear SSH known_hosts manually if needed
cpc clear-ssh-hosts

# Clear SSH control sockets
cpc clear-ssh-maps
```

**Note**: The bootstrap command automatically uses SSH options that skip host key verification, so this should rarely be needed.

### Diagnostic Commands

```bash
# Check bootstrap logs
journalctl -u kubelet -f

# Verify containerd status
systemctl status containerd

# Check cluster component status
kubectl cluster-info
kubectl get componentstatuses

# Review Calico status
kubectl get pods -n calico-system
```

### Recovery Procedures

#### Complete Cluster Reset
```bash
# Full cluster reset and restart
cpc reset-all-nodes
cpc stop-vms
cpc start-vms
cpc bootstrap --force
```

#### Partial Node Recovery
```bash
# Reset specific node
cpc reset-node <node-name>
cpc add-nodes --target-hosts <node-name>
```

## Integration with Other CPC Commands

### VM Management
```bash
cpc start-vms                 # Start all VMs
cpc stop-vms                  # Stop all VMs
cpc deploy destroy            # Destroy infrastructure
```

### Cluster Management
```bash
cpc add-nodes                 # Add worker nodes
cpc drain-node <node>         # Drain node for maintenance
cpc upgrade-node <node>       # Upgrade Kubernetes on node
cpc upgrade-k8s               # Upgrade control plane
```

### Monitoring and Maintenance
```bash
cpc run-command all "systemctl status kubelet"
cpc run-command control_plane "kubectl get nodes"
```

## Performance Considerations

### Resource Requirements
- **Control Plane**: 2 CPU cores, 4GB RAM minimum
- **Worker Nodes**: 2 CPU cores, 2GB RAM minimum
- **Network**: Stable connectivity between all nodes

### Optimization Tips
- Use SSD storage for etcd performance
- Ensure proper DNS configuration
- Configure appropriate pod and service CIDR ranges
- Monitor resource usage during bootstrap

## Security Notes

- SSH keys are used for secure communication
- SOPS encrypts sensitive configuration data
- Kubernetes RBAC is enabled by default
- Network policies can be configured post-bootstrap

## Related Documentation

- [Cluster Deployment Guide](cluster_deployment_guide.md)
- [Ansible Playbooks](../ansible/playbooks/README.md)
- [CPC Template Variables Guide](cpc_template_variables_guide.md)
- [Architecture Overview](architecture.md)
