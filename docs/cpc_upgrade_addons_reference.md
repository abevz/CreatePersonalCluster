# CPC upgrade-addons - Reference Guide

## 📋 **OVERVIEW**

The `./cpc upgrade-addons` command is designed to install and upgrade additional Kubernetes cluster components.

⚠️ **IMPORTANT:** The command now **ALWAYS** shows an interactive menu for addon selection unless the `--addon` parameter is specified!

## 🔧 **SYNTAX**

```bash
./cpc upgrade-addons [--addon <name>] [--version <version>]
```

## 📋 **PARAMETERS**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--addon <name>` | Force specific addon selection (skips menu) | Interactive menu is shown |
| `--version <version>` | Addon version | From environment variables |

## 🧩 **AVAILABLE ADDONS**

| Addon | Description | Purpose |
|-------|-------------|---------|
| `calico` | Calico CNI networking | Cluster networking subsystem |
| `metallb` | MetalLB load balancer | Load Balancer for bare-metal |
| `metrics-server` | Kubernetes Metrics Server | Resource metrics |
| `coredns` | CoreDNS DNS server | Cluster DNS server |
| `cert-manager` | Certificate manager | Certificate management |
| `kubelet-serving-cert-approver` | Automatic cert approval | Automatic certificate approval |
| `argocd` | ArgoCD GitOps | GitOps continuous delivery |
| `ingress-nginx` | NGINX Ingress Controller | Ingress traffic |
| `all` | All of the above | Complete installation |

## 💡 **USAGE EXAMPLES**

### **Show help**
```bash
./cpc upgrade-addons --help
```

### **Interactive mode (new default behavior)**
```bash
# Shows addon selection menu:
./cpc upgrade-addons
```

### **Direct mode (skip menu)**
```bash
# Install all addons directly
./cpc upgrade-addons --addon all

# Install specific addon without menu
./cpc upgrade-addons --addon metallb
```

### **Install specific addon**
```bash
# MetalLB Load Balancer
./cpc upgrade-addons --addon metallb

# Cert-Manager
./cpc upgrade-addons --addon cert-manager

# NGINX Ingress
./cpc upgrade-addons --addon ingress-nginx

# ArgoCD
./cpc upgrade-addons --addon argocd
```

### **Install addon with specific version**
```bash
./cpc upgrade-addons --addon metallb --version v0.14.8
./cpc upgrade-addons --addon cert-manager --version v1.16.2
./cpc upgrade-addons --addon ingress-nginx --version v1.12.0
```

## 🔄 **RECOMMENDED WORKFLOW**

### **After creating base cluster:**

```bash
# 1. Create and configure cluster
./cpc bootstrap
./cpc add-nodes --target-hosts "workers"

# 2. Get cluster access
./cpc get-kubeconfig

# 3. Install core addons step by step
./cpc upgrade-addons --addon metallb      # Load Balancer
./cpc upgrade-addons --addon cert-manager # Certificate management
./cpc upgrade-addons --addon ingress-nginx # Ingress Controller

# 4. (Optional) GitOps
./cpc upgrade-addons --addon argocd
```

### **Or install everything at once:**
```bash
./cpc upgrade-addons --addon all
```

## 🚨 **IMPORTANT NOTES**

### **⚠️ New Default Behavior**
```bash
# THIS COMMAND NOW SHOWS INTERACTIVE MENU
./cpc upgrade-addons
```

For automated installation, always specify `--addon`:
```bash
./cpc upgrade-addons --addon metallb
```

### **📋 Dependencies**
- Cluster must be initialized (`./cpc bootstrap`)
- Worker nodes must be joined (`./cpc add-nodes`)
- kubectl access must be configured (`./cpc get-kubeconfig`)

### **🔍 Installation Verification**
```bash
# Check all pods
kubectl get pods --all-namespaces

# Specific components:
kubectl get pods -n metallb-system    # MetalLB
kubectl get pods -n cert-manager       # Cert-Manager
kubectl get pods -n ingress-nginx      # NGINX Ingress
kubectl get pods -n argocd            # ArgoCD
```

## 🛠️ **TROUBLESHOOTING**

### **Addon fails to install**
```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check playbook logs
# (logs are shown during command execution)
```

### **Wrong addon version**
```bash
# Reinstall with correct version
./cpc upgrade-addons --addon <name> --version <correct-version>
```

### **Addon conflicts**
```bash
# Check existing installations
kubectl get namespaces
kubectl get pods --all-namespaces | grep <addon-name>

# If necessary, delete and reinstall
kubectl delete namespace <addon-namespace>
./cpc upgrade-addons --addon <name>
```

## 📚 **RELATED COMMANDS**

```bash
# Cluster creation
./cpc bootstrap

# Node addition
./cpc add-nodes --target-hosts "workers"

# Access setup
./cpc get-kubeconfig

# Status verification
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

---
*Reference guide created based on CPC upgrade-addons command analysis*  
*Date: June 12, 2025*
