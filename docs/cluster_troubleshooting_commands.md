# Cluster Troubleshooting Commands

This document contains a set of commands for diagnosing and troubleshooting Kubernetes clusters created through CPC.

## General Diagnostic Commands

### CPC Status Check
```bash
# Check current cluster context
./cpc ctx

# Check loaded environment variables
./cpc load_secrets
```

### Tofu/Terraform Infrastructure Check
```bash
# Check planned changes
./cpc deploy plan

# Check resource state
./cpc deploy show

# Get outputs
./cpc deploy output

# Get node IP addresses
./cpc deploy output k8s_node_ips
```

### Connectivity Check
```bash
# Check VM connections
ansible all -i ansible/inventory/hosts -m ping

# Check connection with automatic SSH key acceptance
ansible all -i ansible/inventory/hosts -m ping --ssh-extra-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

## SSH Diagnostics

### SSH Connection Management
```bash
# Clear SSH known_hosts
./cpc clear-ssh-hosts

# Clear SSH control sockets
./cpc clear-ssh-maps

# Check SSH connection to control plane
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null abevz@<control_plane_ip>
```

### SSH Key Check
```bash
# Check SSH keys in secrets
grep -A5 -B5 ssh_public_key secrets.sops.yaml

# Check loaded SSH keys
./cpc load_secrets | grep -i ssh
```

## Container and Kubernetes Diagnostics

### Containerd Check
```bash
# Check containerd status on node
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo systemctl status containerd"

# Check containerd configuration
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo cat /etc/containerd/config.toml | grep -A5 -B5 cri"

# Check containerd CRI plugin (should NOT be disabled)
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo cat /etc/containerd/config.toml | grep disabled_plugins"

# Restart containerd if needed
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo systemctl restart containerd"
```

### Kubelet Check
```bash
# Check kubelet status
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo systemctl status kubelet"

# View kubelet logs
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo journalctl -u kubelet -f --no-pager"

# Restart kubelet
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo systemctl restart kubelet"
```

### Control Plane Component Check
```bash
# Check containers via crictl
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a"

# Check specific components
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a | grep kube-apiserver"
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a | grep etcd"
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a | grep kube-controller-manager"
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a | grep kube-scheduler"

# View container logs
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl logs <container_id>"
```

### API Server Check
```bash
# Check API server availability locally on control plane
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes"

# Check external API server availability
kubectl cluster-info --context cluster-<workspace>

# Check ports
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo netstat -tlnp | grep 6443"
```

## Kubeconfig Diagnostics

### Kubeconfig Check
```bash
# Show all contexts
kubectl config get-contexts

# Show current context
kubectl config current-context

# Check connection
kubectl cluster-info

# Check server IP in context
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}' --context cluster-<workspace>

# Switch to context
kubectl config use-context cluster-<workspace>
```

### Get kubeconfig via CPC
```bash
# Get kubeconfig (automatically overwrites existing)
./cpc get-kubeconfig

# Get kubeconfig with custom context name
./cpc get-kubeconfig --context-name my-cluster

# Force overwrite
./cpc get-kubeconfig --force
```

## Network and CNI Diagnostics

### Network Settings Check
```bash
# Check network bridges
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo sysctl net.bridge.bridge-nf-call-iptables"
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo sysctl net.ipv4.ip_forward"

# Check iptables rules
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo iptables -L -n"

# Check Calico pods
kubectl get pods -n calico-system --context cluster-<workspace>
kubectl get pods -n kube-system --context cluster-<workspace> | grep calico
```

### DNS Check
```bash
# Check CoreDNS
kubectl get pods -n kube-system --context cluster-<workspace> | grep coredns

# Test DNS inside cluster
kubectl run test-dns --image=busybox --rm -it --restart=Never --context cluster-<workspace> -- nslookup kubernetes.default
```

## Bootstrap Process Diagnostics

### Bootstrap Stage Check
```bash
# Check VM readiness
./cpc deploy output k8s_node_ips

# Run bootstrap with verbose output
./cpc bootstrap

# Check state after bootstrap
kubectl get nodes --context cluster-<workspace>
kubectl get pods --all-namespaces --context cluster-<workspace>
```

### Bootstrap Problem Analysis
```bash
# Check kubeadm logs
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo journalctl -u kubelet --no-pager | grep -i error"

# Check cloud-init logs
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo tail -f /var/log/cloud-init-output.log"

# Check system resources
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "free -h && df -h && systemctl status"
```

## Reset and Recreate Commands

### Complete Cluster Reset
```bash
# Stop VMs
./cpc stop-vms

# Remove infrastructure
./cpc deploy destroy -auto-approve

# Clean kubeconfig
kubectl config delete-context cluster-<workspace> 2>/dev/null || true
kubectl config delete-cluster cluster-<workspace>-cluster 2>/dev/null || true
kubectl config delete-user cluster-<workspace>-admin 2>/dev/null || true

# Clear SSH
./cpc clear-ssh-hosts
./cpc clear-ssh-maps
```

### Cluster Recreation
```bash
# Create new infrastructure
./cpc deploy apply -auto-approve

# Wait for VM readiness (2-3 minutes)
./cpc deploy output k8s_node_ips

# Run bootstrap
./cpc bootstrap

# Get kubeconfig
./cpc get-kubeconfig

# Check result
kubectl get nodes --context cluster-<workspace>
```

## Useful Aliases

Add these aliases to your `.bashrc` or `.zshrc`:

```bash
# CPC aliases
alias cpc-ctx='./cpc ctx'
alias cpc-deploy='./cpc deploy'
alias cpc-bootstrap='./cpc bootstrap'
alias cpc-kubeconfig='./cpc get-kubeconfig'

# Kubernetes aliases for troubleshooting
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdn='kubectl describe node'
alias klogs='kubectl logs'
```

## Specific Scenario Examples

### Scenario 1: API server not responding
```bash
# 1. Check IP address in kubeconfig
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}' --context cluster-ubuntu

# 2. Check real control plane IP
./cpc deploy output k8s_node_ips

# 3. If IPs differ - get new kubeconfig
./cpc get-kubeconfig

# 4. Check kubelet status on control plane
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo systemctl status kubelet"

# 5. Restart kubelet if needed
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo systemctl restart kubelet"
```

### Scenario 2: Nodes in NotReady status
```bash
# 1. Check node status
kubectl get nodes --context cluster-<workspace>

# 2. Check CNI pods
kubectl get pods -n calico-system --context cluster-<workspace>

# 3. Check containerd CRI on all nodes
for ip in $(./cpc deploy output k8s_node_ips | jq -r '.[]'); do
  echo "=== Node $ip ==="
  ssh -o StrictHostKeyChecking=no abevz@$ip "sudo cat /etc/containerd/config.toml | grep disabled_plugins"
done

# 4. Fix CRI configuration if needed
for ip in $(./cpc deploy output k8s_node_ips | jq -r '.[]'); do
  ssh -o StrictHostKeyChecking=no abevz@$ip "sudo sed -i 's/disabled_plugins = \[\"cri\"\]/disabled_plugins = []/g' /etc/containerd/config.toml && sudo systemctl restart containerd"
done
```

### Scenario 3: Bootstrap interrupted on SSH
```bash
# 1. Clear SSH cache
./cpc clear-ssh-hosts
./cpc clear-ssh-maps

# 2. Check SSH connection manually
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null abevz@<node_ip>

# 3. Run bootstrap again - SSH keys will be accepted automatically
./cpc bootstrap
```

---

**Note**: Replace `<workspace>`, `<node_ip>`, `<control_plane_ip>`, `<container_id>` with actual values for your cluster.
