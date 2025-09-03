# 🔧 Hotfix v1.1.1 - Critical Status Command Fixes

## 🐛 Bug Fixes
- **SSH Connectivity**: Fixed count showing "0/3" instead of actual reachable nodes
- **SSH Testing**: Fixed loop only testing first VM due to subshell variable scoping  
- **CNI Detection**: Fixed Calico detection by checking both `calico-system` and `kube-system` namespaces
- **Proxmox Integration**: Fixed VM status check by implementing proper REST API calls

## 🔒 Security Improvements  
- **Password Security**: Use stdin for Proxmox password to prevent exposure in process list

## ⚡ Performance & Code Quality
- **Optimization**: Replace inefficient `echo+cut` with direct `read` in VM parsing
- **Refactoring**: Eliminate code duplication in Proxmox VM status display

## 🧪 Testing
All fixes verified with `./cpc status` command showing correct:
- ✅ "All 3 nodes are reachable via SSH" 
- ✅ Proxmox VMs showing "✓ Running"
- ✅ CNI showing "✓ Running (2/2)"

## 📦 Installation
```bash
git checkout v1.1.1
# or download from releases page
```

## 🔄 Upgrade from v1.1.0
```bash
git pull origin main
./cpc status  # verify fixes
```
