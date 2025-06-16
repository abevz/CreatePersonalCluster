# Quick DNS Certificate Fix for Kubernetes

## Problem Symptoms
- ❌ Cluster becomes unavailable when IP addresses change after VM reboot
- ❌ Certificates contain only IP addresses, not DNS names (cu1.bevz.net)
- ❌ `kubectl` shows certificate errors when using hostnames

## Quick Solution

### For NEW clusters

```bash
# DNS support is ALREADY BUILT INTO CPC!
cd /home/abevz/Projects/kubernetes/my-kthw

# 1. Deploy VMs
./cpc deploy apply

# 2. Initialize cluster with DNS support (automatically)
./cpc bootstrap

# 3. Get kubeconfig with DNS endpoint
./cpc get-kubeconfig --force

# 4. Check result
kubectl get nodes
```

### For EXISTING clusters

```bash
# 1. Create cluster backup
kubectl get all --all-namespaces > cluster-backup.yaml

# 2. Apply certificate patch
cd /home/abevz/Projects/kubernetes/my-kthw
./cpc run-ansible regenerate_certificates_with_dns.yml

# 3. Get updated kubeconfig
./cpc get-kubeconfig --force

# 4. Verify functionality
kubectl get nodes
```

## Result Verification

```bash
# 1. Check SAN in certificate
ssh abevz@cu1.bevz.net "sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A 10 'Subject Alternative Name'"

# Should show:
# DNS:cu1.bevz.net, DNS:cu1, IP Address:10.10.10.116, ...

# 2. Check DNS access
kubectl --server=https://cu1.bevz.net:6443 get nodes

# 3. Check kubeconfig endpoint
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}'
# Should show: https://cu1.bevz.net:6443
```

## What Changes

### ✅ BEFORE (problem):
```yaml
# Certificate contained only:
IP Address:10.10.10.116

# kubeconfig used:
server: https://10.10.10.116:6443
```

### ✅ AFTER (solution):
```yaml
# Certificate contains:
DNS:cu1.bevz.net, DNS:cu1, IP Address:10.10.10.116

# kubeconfig uses:
server: https://cu1.bevz.net:6443
```

## Recovery if Problems Occur

If something goes wrong:

```bash
# 1. Restore from backup (created automatically)
sudo cp /root/k8s-cert-backup-*/pki/* /etc/kubernetes/pki/
sudo cp /root/k8s-cert-backup-*/admin.conf /etc/kubernetes/

# 2. Restart kubelet
sudo systemctl restart kubelet

# 3. Get kubeconfig with IP
./cpc get-kubeconfig --use-ip --force
```

## Common Issue: Pending Kubelet Serving CSRs

After DNS changes, nodes may create new Certificate Signing Requests (CSRs) that need approval:

```bash
# Check for pending CSRs
kubectl get csr | grep kubelet-serving | grep Pending

# Approve all pending kubelet serving CSRs
kubectl get csr -o name | grep "kubelet-serving" | xargs kubectl certificate approve

# Or use the dedicated CPC command
./cpc run-ansible approve_kubelet_csr.yml
```

**Symptoms of CSR issues:**
- Metrics Server fails to start with readiness probe errors
- `kubectl top nodes` doesn't work
- TLS errors when accessing kubelet API

**Note:** The bootstrap process now automatically approves CSRs, but manual intervention may be needed if you regenerate certificates on existing clusters.

## Additional CPC Configuration

For automatic DNS use in new clusters, edit `cpc`:

```bash
# Find line 819 in cpc file:
sed -i 's/initialize_kubernetes_cluster.yml/initialize_kubernetes_cluster_with_dns.yml/g' cpc
```

Now all new clusters will be created with DNS hostname support!

## Support

Full documentation: `docs/kubernetes_dns_certificate_solution.md`
