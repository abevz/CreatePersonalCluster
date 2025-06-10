# Kubeconfig Context Troubleshooting Guide

## Overview
This document provides commands and techniques for troubleshooting kubeconfig context issues, particularly when dealing with multiple clusters and IP address conflicts.

## Common Issues

### 1. Context IP Address Conflicts
When the same context name exists with different server IPs, it can cause connection issues.

### 2. Partial Context Cleanup
When contexts are not properly removed before creating new ones with the same name.

### 3. Merge Issues
Problems with `kubectl config view --flatten` not properly handling duplicate contexts.

## Diagnostic Commands

### Check Current Contexts
```bash
# List all contexts
kubectl config get-contexts

# Show current context
kubectl config current-context

# View complete kubeconfig
kubectl config view

# View flattened kubeconfig
kubectl config view --flatten
```

### Check Specific Context Details
```bash
# Get server IP for specific context
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}' --context CONTEXT_NAME

# Get all cluster server addresses
kubectl config view -o jsonpath='{.clusters[*].cluster.server}'

# Get context names only
kubectl config get-contexts -o name
```

### Check Context Existence
```bash
# Check if context exists (method 1)
kubectl config get-contexts CONTEXT_NAME &>/dev/null && echo "exists" || echo "not found"

# Check if context exists (method 2 - more reliable)
kubectl config get-contexts -o name | grep -q "^CONTEXT_NAME$" && echo "exists" || echo "not found"
```

### Clean Up Contexts
```bash
# Remove specific context
kubectl config delete-context CONTEXT_NAME

# Remove specific cluster
kubectl config delete-cluster CLUSTER_NAME

# Remove specific user
kubectl config delete-user USER_NAME

# Remove all parts of a context (example for cluster-ubuntu)
kubectl config delete-context cluster-ubuntu 2>/dev/null || true
kubectl config delete-cluster cluster-ubuntu-cluster 2>/dev/null || true  
kubectl config delete-user cluster-ubuntu-admin 2>/dev/null || true
```

### Test Context Connectivity
```bash
# Test specific context
kubectl cluster-info --context CONTEXT_NAME

# Test with timeout
timeout 10s kubectl cluster-info --context CONTEXT_NAME

# Get nodes with specific context
kubectl get nodes --context CONTEXT_NAME
```

## CPC Script Context Management

### Check CPC Context
```bash
# Check current CPC context
./cpc ctx

# Set CPC context
./cpc ctx WORKSPACE_NAME

# Get control plane IP from Tofu
cd terraform && tofu workspace select WORKSPACE && tofu output k8s_node_ips
```

### Test SSH Connectivity to Control Plane
```bash
# Test SSH connection
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null USER@CONTROL_PLANE_IP "echo 'SSH OK'"

# Check kubelet status
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null USER@CONTROL_PLANE_IP "sudo systemctl status kubelet"

# Check API server container
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null USER@CONTROL_PLANE_IP "sudo crictl ps | grep kube-apiserver"

# Check API server logs
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null USER@CONTROL_PLANE_IP "sudo crictl logs \$(sudo crictl ps -q --name kube-apiserver)"
```

### Check Kubernetes Cluster Status
```bash
# Check if kubeconfig exists on control plane
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null USER@CONTROL_PLANE_IP "sudo ls -la /etc/kubernetes/admin.conf"

# Test kubeconfig on control plane
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null USER@CONTROL_PLANE_IP "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes"

# Check cluster initialization status
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null USER@CONTROL_PLANE_IP "sudo kubeadm config print init-defaults"
```

## Troubleshooting Workflow

### 1. Identify the Problem
```bash
# Check current context
kubectl config current-context

# Check if context can connect
kubectl cluster-info

# Check server IP in context
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}'
```

### 2. Verify Infrastructure
```bash
# Check CPC context
./cpc ctx

# Get expected control plane IP
cd terraform && tofu output k8s_node_ips

# Test SSH connectivity
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null USER@EXPECTED_IP "echo 'SSH OK'"
```

### 3. Clean and Recreate Context
```bash
# Remove old context completely
kubectl config delete-context CONTEXT_NAME 2>/dev/null || true
kubectl config delete-cluster CLUSTER_NAME 2>/dev/null || true
kubectl config delete-user USER_NAME 2>/dev/null || true

# Recreate with CPC
./cpc get-kubeconfig

# Test new context
kubectl cluster-info
```

### 4. Verify Cluster Health
```bash
# Check nodes
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system

# Check cluster info
kubectl cluster-info
```

## Common Fix Commands

### Fix CPC get-kubeconfig Context Conflicts
The CPC script now automatically removes conflicting contexts before creating new ones:

```bash
# This is handled automatically in the updated CPC script
if kubectl config get-contexts -o name | grep -q "^${context_name}$"; then
  echo "Removing existing context '$context_name' to avoid conflicts..."
  kubectl config delete-context "$context_name" &>/dev/null || true
  kubectl config delete-cluster "${context_name}-cluster" &>/dev/null || true
  kubectl config delete-user "${context_name}-admin" &>/dev/null || true
fi
```

### Backup and Restore Kubeconfig
```bash
# Backup current kubeconfig
cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d_%H%M%S)

# Restore from backup
cp ~/.kube/config.backup.TIMESTAMP ~/.kube/config
```

## Prevention Tips

1. **Always use unique context names** for different clusters
2. **Clean up old contexts** before creating new ones with the same name
3. **Use CPC context management** instead of manual kubectl commands
4. **Test connectivity** after context changes
5. **Keep backups** of working kubeconfig files

## Emergency Recovery

If kubeconfig is completely broken:

```bash
# Reset kubeconfig completely
mv ~/.kube/config ~/.kube/config.broken

# Recreate from scratch
./cpc get-kubeconfig --context-name cluster-WORKSPACE

# Or manually copy from control plane
scp USER@CONTROL_PLANE_IP:/etc/kubernetes/admin.conf ~/.kube/config
# Then fix server IP and context names manually
```
