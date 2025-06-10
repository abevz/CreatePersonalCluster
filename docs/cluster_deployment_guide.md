# Kubernetes Cluster Deployment Guide

## Overview

This guide covers the complete process of deploying a Kubernetes cluster using the **my-kthw** (Kubernetes The Hard Way) project. The setup includes VM provisioning via Proxmox using Terraform/OpenTofu, infrastructure automation with Ansible, and full cluster initialization with Calico CNI.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Proxmox Hypervisor                       │
├─────────────────────────────────────────────────────────────┤
│  Control Plane Node           Worker Nodes                  │
│  ┌─────────────────┐         ┌─────────────┐ ┌─────────────┐│
│  │  cu1.bevz.net   │         │wu1.bevz.net │ │wu2.bevz.net ││
│  │  10.10.10.116   │         │10.10.10.121 │ │10.10.10.120 ││
│  │  2 CPU / 2GB    │         │2 CPU / 2GB  │ │2 CPU / 2GB  ││
│  └─────────────────┘         └─────────────┘ └─────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Software Requirements
- **OpenTofu** (v1.8.1+) - Infrastructure provisioning
- **Ansible** (v2.15+) - Configuration management  
- **kubectl** (v1.31+) - Kubernetes CLI
- **SOPS** - Secrets management
- **jq** - JSON processing
- **Python 3** - Required for inventory scripts

### Infrastructure Requirements
- **Proxmox VE** cluster with API access
- **VM Template** with cloud-init support (Ubuntu 24.04 LTS recommended)
- **Network Configuration** with static IP allocation
- **DNS Server** (Pi-hole recommended) for hostname resolution

### Access Requirements
- **SSH Key** access to Proxmox and VMs
- **SOPS Key** for decrypting secrets
- **Proxmox API** credentials with VM management permissions

## Quick Start

### 1. Initial Setup

```bash
# Clone and setup the project
cd /home/abevz/Projects/kubernetes/my-kthw

# Initialize CPC (Cluster Provisioning Control)
./cpc setup-cpc

# Set cluster context (Ubuntu recommended)
./cpc ctx ubuntu

# Copy and configure environment
cp cpc.env.example cpc.env
# Edit cpc.env with your specific versions and settings
```

### 2. Secrets Configuration

```bash
# Configure secrets file (contains Proxmox credentials, SSH keys, etc.)
# secrets.sops.yaml should contain:
# - virtual_environment_endpoint
# - virtual_environment_username  
# - virtual_environment_password
# - vm_username
# - vm_password
# - vm_ssh_keys

# Verify secrets can be decrypted
sops -d terraform/secrets.sops.yaml
```

### 3. Infrastructure Deployment

```bash
# Plan infrastructure changes
./cpc deploy plan

# Apply infrastructure (creates VMs)
./cpc deploy apply

# Verify VMs are created and accessible
./cpc deploy output k8s_node_ips
./cpc deploy output k8s_node_names
```

### 4. Kubernetes Cluster Bootstrap

```bash
# Bootstrap complete Kubernetes cluster (automated)
./cpc bootstrap

# Get cluster access configuration
./cpc get-kubeconfig

# Verify cluster is working
kubectl get nodes -o wide
```

**Alternative Manual Method:**
```bash
# Install Kubernetes components on all nodes
ansible-playbook -i ansible/inventory/tofu_inventory.py ansible/playbooks/install_kubernetes_cluster.yml

# Initialize cluster and install CNI
ansible-playbook -i ansible/inventory/tofu_inventory.py ansible/playbooks/initialize_kubernetes_cluster.yml
```

### 5. Cluster Verification

```bash
# Check cluster status
kubectl get nodes -o wide

# Verify all pods are running
kubectl get pods --all-namespaces

# Test pod deployment
kubectl run test-nginx --image=nginx
kubectl get pods -o wide
kubectl delete pod test-nginx
```

## Detailed Deployment Process

### Phase 1: Infrastructure Provisioning

#### VM Template Creation
The project requires VM templates with cloud-init support:

```bash
# Create VM template (if needed)
./cpc template --os ubuntu --version 24.04
```

#### Network and Storage Configuration
- **CPU**: 2 cores minimum (Kubernetes requirement)
- **Memory**: 2GB minimum per node
- **Storage**: 20GB+ for system, additional for container storage
- **Network**: Static IP allocation from Proxmox DHCP/DNS

#### Terraform Deployment
```bash
# Review planned changes
./cpc deploy plan

# Apply infrastructure changes
./cpc deploy apply -auto-approve

# Monitor VM creation progress in Proxmox UI
```

### Phase 2: System Preparation

#### OS Configuration
Ansible handles initial system setup:
- Package updates and security patches
- Container runtime installation (containerd)
- Kubernetes binaries installation
- System service configuration
- Network and firewall rules

#### Key Configuration Items
```yaml
# From install_kubernetes_cluster.yml
- kubernetes_version: "1.31.9"
- containerd_version: "1.7.27" 
- calico_version: "v3.28.0"
- pod_cidr: "192.168.0.0/16"
- service_cidr: "10.96.0.0/12"
```

### Phase 3: Cluster Initialization

#### Control Plane Setup
```bash
# Initialize cluster with kubeadm
kubeadm init \
  --apiserver-advertise-address=10.10.10.116 \
  --pod-network-cidr=192.168.0.0/16 \
  --service-cidr=10.96.0.0/12
```

#### CNI Installation (Calico)
```bash
# Install Calico CNI plugin
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml
```

#### Worker Node Joining
```bash
# Generate join command on control plane
kubeadm token create --print-join-command

# Execute on worker nodes
kubeadm join 10.10.10.116:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

### Phase 4: Cluster Validation

#### Node Status Verification
```bash
kubectl get nodes -o wide
# Should show all nodes as Ready with appropriate roles
```

#### Pod Network Testing
```bash
# Deploy test workload across nodes
kubectl create deployment test-app --image=nginx --replicas=2
kubectl get pods -o wide

# Verify pods are distributed and have connectivity
kubectl exec -it <pod-name> -- ping <other-pod-ip>
```

#### DNS and Service Discovery
```bash
# Test CoreDNS functionality
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

## Advanced Configuration

### Custom Resource Configuration

#### CPU and Memory Adjustments
```bash
# Update variables.tf
vm_cpu_cores = 4
vm_memory = 4096

# Apply changes
./cpc deploy apply
```

#### Network Configuration
```hcl
# terraform/locals.tf
network_config = {
  bridge    = "vmbr0"
  firewall  = true
  ip_config = "dhcp"  # or static configuration
}
```

### Cluster Add-ons

#### MetalLB Load Balancer
```bash
# Install MetalLB for LoadBalancer services
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Configure IP pool
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.10.10.200-10.10.10.220
EOF
```

#### Ingress Controller
```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml
```

### Monitoring and Logging

#### Metrics Server
```bash
# Install metrics-server for resource monitoring
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Troubleshooting

### Common Issues

#### CPU Requirements
**Problem**: Kubernetes requires minimum 2 CPU cores per node
**Solution**: Update `terraform/variables.tf`:
```hcl
variable "vm_cpu_cores" {
  default = 2  # Changed from 1
}
```

#### Container Runtime Issues
**Problem**: CRI plugin disabled in containerd
**Solution**: Regenerate containerd configuration:
```bash
# On each node
sudo containerd config default > /etc/containerd/config.toml
# Edit SystemdCgroup = true
sudo systemctl restart containerd
```

#### Network Connectivity
**Problem**: Pods can't communicate across nodes
**Solution**: Verify Calico installation:
```bash
kubectl get pods -n calico-system
kubectl get nodes -o wide  # Check Ready status
```

#### Join Token Expiration
**Problem**: Worker nodes can't join (token expired)
**Solution**: Generate new token:
```bash
# On control plane
kubeadm token create --print-join-command
```

### Diagnostic Commands

```bash
# Check cluster component status
kubectl cluster-info
kubectl get componentstatuses

# Review system logs
journalctl -u kubelet -f
journalctl -u containerd -f

# Network troubleshooting
kubectl get pods -n kube-system | grep -E "(calico|coredns)"
kubectl exec -n calico-system -it <calico-node-pod> -- calicoctl node status
```

### Recovery Procedures

#### Reset Cluster
```bash
# Reset all nodes
./cpc reset-all-nodes

# Reinitialize from scratch
ansible-playbook -i ansible/inventory/tofu_inventory.py ansible/playbooks/initialize_kubernetes_cluster.yml
```

#### VM Recovery
```bash
# Stop all VMs
./cpc stop-vms

# Restart VMs
./cpc start-vms

# Verify connectivity
ansible all -i ansible/inventory/tofu_inventory.py -m ping
```

## Performance Optimization

### Resource Allocation
- **Control Plane**: 2-4 CPU cores, 4-8GB RAM
- **Worker Nodes**: 2+ CPU cores, 2-4GB RAM minimum
- **Storage**: SSD recommended for etcd performance

### Network Configuration
- **Pod Network**: Use non-overlapping CIDR blocks
- **Service Network**: Separate from pod and node networks  
- **DNS**: Configure proper hostname resolution

### Security Considerations
- **SSH Keys**: Use key-based authentication only
- **Firewall**: Configure iptables/ufw rules appropriately
- **RBAC**: Implement proper Kubernetes role-based access control
- **Secrets**: Use SOPS for sensitive data encryption

## Next Steps

After successful cluster deployment:

1. **Configure kubectl** access for additional users
2. **Install monitoring** stack (Prometheus/Grafana)
3. **Set up logging** aggregation (ELK/Loki)
4. **Configure backups** for etcd and persistent volumes
5. **Implement GitOps** workflow (ArgoCD/Flux)
6. **Add security scanning** tools (Falco/OPA Gatekeeper)

## Support and Documentation

- **Project Repository**: `/home/abevz/Projects/kubernetes/my-kthw`
- **Ansible Playbooks**: `ansible/playbooks/`
- **Terraform Modules**: `terraform/`
- **Scripts and Utilities**: `scripts/`
- **Additional Documentation**: `docs/`

For specific issues, check the troubleshooting section or review the Ansible playbook logs for detailed error information.
