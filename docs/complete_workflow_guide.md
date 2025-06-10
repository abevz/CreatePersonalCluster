# Complete Kubernetes Cluster Deployment Workflow

## Quick Start Guide

This guide provides the complete workflow for deploying a production-ready Kubernetes cluster using CPC.

### Prerequisites Checklist
- [ ] Proxmox VE 8.0+ running and accessible
- [ ] OpenTofu/Terraform installed locally
- [ ] Ansible 2.15+ installed locally
- [ ] kubectl installed locally
- [ ] SOPS installed and configured
- [ ] SSH key pair generated

### 1. Initial Project Setup

```bash
# Clone and setup the project
cd /home/abevz/Projects/kubernetes/my-kthw

# Initialize CPC
./cpc setup-cpc

# Copy and configure environment
cp cpc.env.example cpc.env
# Edit cpc.env with your Proxmox details and versions

# Verify SOPS secrets can be decrypted
sops -d terraform/secrets.sops.yaml
```

### 2. Template Creation (One-time per OS)

```bash
# Set cluster context (choose your OS)
./cpc ctx ubuntu          # Recommended: Ubuntu 24.04
# OR: ./cpc ctx suse      # SUSE Linux Enterprise
# OR: ./cpc ctx rocky     # Rocky Linux
# OR: ./cpc ctx debian    # Debian (limited support)

# Create VM template (only needed once per OS)
./cpc template

# Verify template was created successfully
# Check Proxmox UI for template with configured VM ID
```

### 3. Infrastructure Deployment

```bash
# Plan infrastructure changes
./cpc deploy plan

# Deploy VMs (creates control plane + worker nodes)
./cpc deploy apply

# Verify VMs are created and accessible
./cpc deploy output k8s_node_ips
./cpc deploy output k8s_node_names

# Check VMs are running in Proxmox UI
```

### 4. Kubernetes Cluster Bootstrap

```bash
# Bootstrap complete Kubernetes cluster
./cpc bootstrap

# Expected output:
# ✅ VM connectivity check passed
# ✅ Ansible connectivity test passed (no SSH prompts - fully automated!)
# ✅ Step 1: Installing Kubernetes components
# ✅ Step 2: Initializing cluster and installing Calico CNI
# ✅ Step 3: Validating cluster installation
# ✅ Kubernetes cluster bootstrap completed successfully!
```

**Note**: The bootstrap process now automatically handles SSH host key verification, so you won't see SSH authentication prompts during deployment.

### 5. Cluster Access and Verification

```bash
# Get cluster access configuration
./cpc get-kubeconfig

# Verify cluster is working
kubectl get nodes -o wide
kubectl cluster-info

# Expected output:
# NAME               STATUS   ROLES           AGE   VERSION
# cu1.bevz.net      Ready    control-plane   5m    v1.31.0
# wu1.bevz.net      Ready    <none>          4m    v1.31.0
# wu2.bevz.net      Ready    <none>          4m    v1.31.0
```

### 6. Install Cluster Addons

```bash
# Install all recommended addons
./cpc upgrade-addons --addon all

# OR install specific addons
./cpc upgrade-addons --addon metallb       # Load balancer
./cpc upgrade-addons --addon cert-manager  # Certificate management
./cpc upgrade-addons --addon metrics-server # Resource metrics
./cpc upgrade-addons --addon ingress-nginx # Ingress controller
./cpc upgrade-addons --addon argocd       # GitOps platform

# Verify addons are running
kubectl get pods --all-namespaces
```

### 7. Test Cluster Functionality

```bash
# Deploy test application
kubectl create deployment test-nginx --image=nginx --replicas=2
kubectl expose deployment test-nginx --port=80 --type=LoadBalancer

# Verify deployment
kubectl get pods -o wide
kubectl get services

# Test connectivity (should show nginx welcome page)
kubectl port-forward service/test-nginx 8080:80
curl http://localhost:8080

# Cleanup test resources
kubectl delete deployment test-nginx
kubectl delete service test-nginx
```

## Advanced Operations

### Cluster Management

```bash
# Add more worker nodes
# 1. Update terraform configuration to add more VMs
# 2. Apply changes
./cpc deploy apply
# 3. Add nodes to cluster
./cpc add-nodes --target-hosts new_workers

# Node maintenance
./cpc drain-node wu1.bevz.net              # Drain workloads
./cpc upgrade-node wu1.bevz.net            # Upgrade Kubernetes
./cpc delete-node wu1.bevz.net             # Remove from cluster

# Control plane operations
./cpc upgrade-k8s                          # Upgrade control plane
./cpc run-command control_plane "kubectl get nodes"
```

### VM Management

```bash
# Start/stop all VMs in current context
./cpc start-vms
./cpc stop-vms

# Manage specific VMs through Proxmox UI or API
# VM state is managed through Terraform/OpenTofu
```

### Cluster Reset and Recovery

```bash
# Reset entire cluster
./cpc reset-all-nodes

# Reset specific node
./cpc reset-node wu2.bevz.net

# Complete infrastructure teardown
./cpc deploy destroy

# Rebuild cluster from scratch
./cpc deploy apply
./cpc bootstrap --force
```

## Context Management

```bash
# Switch between different OS distributions
./cpc ctx ubuntu     # Switch to Ubuntu cluster
./cpc ctx suse       # Switch to SUSE cluster
./cpc ctx rocky      # Switch to Rocky cluster

# Check current context
./cpc ctx

# Each context maintains separate:
# - Terraform workspace
# - VM configurations
# - Cluster settings
```

## Troubleshooting Quick Reference

### VM Issues
```bash
# Check VM status
./cpc deploy output vm_fqdns
ssh abevz@<vm-ip>

# Restart VMs
./cpc stop-vms && ./cpc start-vms
```

### SSH Connection Issues
```bash
# Clear SSH known_hosts entries (after VM recreation)
./cpc clear-ssh-hosts

# Clear SSH control sockets and connections
./cpc clear-ssh-maps

# Preview what would be cleared
./cpc clear-ssh-hosts --dry-run
./cpc clear-ssh-maps --dry-run

# Clear SSH artifacts for all contexts
./cpc clear-ssh-hosts --all
./cpc clear-ssh-maps --all
```

### Cluster Issues
```bash
# Check cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Check logs
./cpc run-command all "journalctl -u kubelet -n 50"
./cpc run-command all "systemctl status containerd"
```

### Network Issues
```bash
# Check Calico
kubectl get pods -n calico-system
kubectl exec -n calico-system -it <calico-pod> -- calicoctl node status

# Test pod networking
kubectl run test-pod --image=busybox --rm -it -- ping 8.8.8.8
```

## Production Considerations

### Security
- Change default passwords in secrets.sops.yaml
- Configure proper firewall rules
- Implement Kubernetes RBAC policies
- Use network policies for micro-segmentation

### High Availability
- Deploy multiple control plane nodes
- Use external etcd cluster
- Configure load balancer for API server
- Implement proper backup strategy

### Monitoring
- Install Prometheus and Grafana
- Configure log aggregation (ELK/Loki)
- Set up alerting rules
- Monitor resource usage

### Backup
- Regular etcd backups
- Persistent volume snapshots
- Configuration backup (GitOps)
- Disaster recovery procedures

## Support and Documentation

- **Main README**: [README.md](../README.md)
- **Bootstrap Guide**: [bootstrap_command_guide.md](bootstrap_command_guide.md)
- **Ansible Playbooks**: [../ansible/playbooks/README.md](../ansible/playbooks/README.md)
- **Troubleshooting**: Check `docs/` directory for specific guides

## Success Metrics

A successful deployment should show:
- ✅ All VMs in Running state in Proxmox
- ✅ All nodes showing Ready in `kubectl get nodes`
- ✅ All system pods Running in `kubectl get pods -n kube-system`
- ✅ Successful pod-to-pod communication test
- ✅ External connectivity from pods (internet access)
- ✅ DNS resolution working within cluster
