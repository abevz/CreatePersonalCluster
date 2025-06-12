# Complete Kubernetes Cluster Creation Guide with CPC

## 📋 **OVERVIEW**

This guide describes the correct sequence for creating a Kubernetes cluster using CPC (Cluster Provisioning Control) based on our successful deployment experience.

**Update Date:** June 12, 2025  
**Status:** Tested and working  
**Kubernetes Version:** v1.31.9  

## 🎯 **GOAL**

Create a fully functional 3-node Kubernetes cluster:
- 1 Control Plane node
- 2 Worker nodes
- Calico CNI
- All system components

## 🚀 **STEP-BY-STEP GUIDE**

### **Step 1: Preparation and Setup**

```bash
# Setup CPC (if not already done)
./cpc setup-cpc

# Set context (e.g., ubuntu)
./cpc ctx ubuntu

# Load secrets
./cpc load_secrets
```

**Verification:**
```bash
# Should see loaded secrets and variables
Loading secrets from secrets.sops.yaml...
Successfully loaded secrets (PROXMOX_HOST: homelab.bevz.net, VM_USERNAME: abevz)
```

### **Step 2: Infrastructure Creation**

```bash
# Plan changes (optional but recommended)
./cpc deploy plan

# Create VMs
./cpc deploy apply -auto-approve

# Verify created VMs
./cpc deploy output k8s_node_ips
```

**Expected output:**
```json
{
  "controlplane1": "10.10.10.X",
  "worker1": "10.10.10.Y", 
  "worker2": "10.10.10.Z"
}
```

### **Step 3: Kubernetes Components Installation**

```bash
# Install Kubernetes, containerd on all nodes
./cpc run-ansible install_kubernetes_cluster.yml
```

**What this does:**
- Installs kubeadm, kubelet, kubectl
- Configures containerd with proper CRI settings
- Sets up network prerequisites
- Disables swap

### **Step 4: Cluster Initialization**

```bash
# Complete cluster initialization (control plane + CNI)
./cpc bootstrap
```

**This command:**
- Initializes control plane with kubeadm
- Installs Calico CNI
- Configures cluster networking
- Sets up kubectl access

### **Step 5: Worker Nodes Addition**

```bash
# Join worker nodes to cluster
./cpc add-nodes --target-hosts "workers"
```

**What happens:**
- Generates join tokens
- Dynamically resolves control plane IP
- Joins all worker nodes
- Verifies node status

### **Step 6: Access Configuration**

```bash
# Get kubeconfig
./cpc get-kubeconfig

# Verify cluster access
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

### **Step 7: Additional Components (Optional)**

```bash
# Install additional components (shows interactive menu)
./cpc upgrade-addons
# or direct installation:
./cpc upgrade-addons --addon metallb
./cpc upgrade-addons --addon cert-manager
```

### **Step 8: Final Verification**

```bash
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

## 🔧 **MANAGING ADDITIONAL COMPONENTS**

### **upgrade-addons Command**

✨ **NEW:** The `./cpc upgrade-addons` command now shows an **interactive menu** for component selection!

**Proper usage:**

```bash
# Show help and available addons
./cpc upgrade-addons --help

# Interactive menu (new default behavior)
./cpc upgrade-addons
# Shows menu:
# 1) all - Install/upgrade all addons
# 2) calico - Calico CNI networking
# 3) metallb - MetalLB load balancer
# ... etc.

# Direct installation of all addons (skip menu)
./cpc upgrade-addons --addon all

# Install specific addon (skip menu)
./cpc upgrade-addons --addon metallb
./cpc upgrade-addons --addon cert-manager
./cpc upgrade-addons --addon ingress-nginx

# Install addon with specific version
./cpc upgrade-addons --addon metallb --version v0.14.8
```

**Available addons:**
- `calico` - Calico CNI networking
- `metallb` - MetalLB load balancer
- `metrics-server` - Kubernetes Metrics Server
- `coredns` - CoreDNS DNS server
- `cert-manager` - Certificate manager
- `kubelet-serving-cert-approver` - Automatic certificate approval
- `argocd` - ArgoCD GitOps
- `ingress-nginx` - NGINX Ingress Controller

## 📋 **COMPLETE WORKFLOW FOR NEW CLUSTER**

```bash
# 1. Full cleanup (if recreating)
./cpc stop-vms                           # Stop VMs
./cpc deploy destroy -auto-approve       # Remove infrastructure
./cpc clear-ssh-hosts && ./cpc clear-ssh-maps  # Clear SSH cache

# 2. Create new infrastructure
./cpc deploy apply -auto-approve

# 3. Install components
./cpc run-ansible install_kubernetes_cluster.yml

# 4. Initialize cluster
./cpc bootstrap

# 5. Add worker nodes
./cpc add-nodes --target-hosts "workers"

# 6. Get access
./cpc get-kubeconfig

# 7. Install additional components (optional)
./cpc upgrade-addons  # Shows interactive menu
# or direct installation:
./cpc upgrade-addons --addon metallb
./cpc upgrade-addons --addon cert-manager

# 8. Final verification
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

## ⚠️ **IMPORTANT PRINCIPLES**

### **DO's (What to do):**
- ✅ Always use **step sequence 1-8**
- ✅ Check each step before proceeding to next
- ✅ Use `./cpc deploy plan` before `apply`
- ✅ After each infrastructure change, clear SSH cache:
  ```bash
  ./cpc clear-ssh-hosts
  ./cpc clear-ssh-maps
  ```

### **DON'T's (What not to do):**
- ❌ Don't run `./cpc add-nodes` before `./cpc bootstrap`
- ❌ Don't skip component installation (`install_kubernetes_cluster.yml`)
- ❌ Don't use static IPs in playbooks - they may change

## 🔍 **KEY FIXES IMPLEMENTED**

### **1. Containerd CRI Configuration** 
Fixed in `ansible/playbooks/install_kubernetes_cluster.yml` (line ~133):
```yaml
# REMOVED this line to allow configuration regeneration:
# args:
#   creates: /etc/containerd/config.toml
```

### **2. Worker Node Joining**
Fixed recursive error in `ansible/playbooks/pb_add_nodes.yml`:
```yaml
# Added facts gathering for control plane
- name: Gather facts from control plane
  setup:
  delegate_to: "{{ groups['control_plane'][0] }}"
  delegate_facts: yes
  run_once: true

# Dynamic endpoint definition
- name: Set control plane endpoint
  set_fact:
    control_plane_endpoint: "{{ hostvars[groups['control_plane'][0]]['ansible_default_ipv4']['address'] + ':6443' }}"
```

## 📊 **EXPECTED RESULTS**

After completing all steps, you will have:
- **3-node cluster**: 1 control plane + 2 workers
- **All nodes Ready**
- **Calico CNI installed and working**
- **All system pods Running**
- **kubeconfig configured locally**

### **Sample successful output:**
```bash
kubectl get nodes -o wide
NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP    
cu1.bevz.net   Ready    control-plane   15m   v1.31.9   10.10.10.116   
wu1.bevz.net   Ready    <none>          12m   v1.31.9   10.10.10.101   
wu2.bevz.net   Ready    <none>          12m   v1.31.9   10.10.10.29    
```

## 🛠️ **TROUBLESHOOTING**

### **Common Issues and Solutions:**

#### **API server not responding**
```bash
# 1. Check IP in kubeconfig
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}'

# 2. Check real control plane IP
./cpc deploy output k8s_node_ips

# 3. If IPs differ - get new kubeconfig
./cpc get-kubeconfig
```

#### **Nodes in NotReady status**
```bash
# 1. Check node status
kubectl get nodes

# 2. Check CNI pods
kubectl get pods -n calico-system

# 3. Check containerd CRI
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo cat /etc/containerd/config.toml | grep disabled_plugins"
```

#### **Bootstrap interrupted on SSH**
```bash
# 1. Clear SSH cache
./cpc clear-ssh-hosts
./cpc clear-ssh-maps

# 2. Run bootstrap again
./cpc bootstrap
```

## 📚 **RELATED DOCUMENTATION**

- [CPC upgrade-addons Reference](cpc_upgrade_addons_reference.md)
- [Cluster Troubleshooting Commands](cluster_troubleshooting_commands.md)
- [Architecture Overview](architecture.md)

---
*This guide ensures stable cluster creation without errors!*  
*Date: June 12, 2025*
