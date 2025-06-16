# Kubernetes Certificate DNS Hostname Issue and Solution

## Problem

When creating a Kubernetes cluster with kubeadm, the API server creates self-signed certificates that include only the node IP addresses as Subject Alternative Names (SAN). This creates a problem when:

1. **DHCP assigns different IP addresses** during server reboots
2. **DNS names of servers remain constant** (e.g., cu1.bevz.net, wu1.bevz.net)
3. **Certificates become invalid** when IP addresses change

## Technical Cause

The current `initialize_kubernetes_cluster.yml` uses:

```yaml
kubeadm init \
  --apiserver-advertise-address={{ ansible_default_ipv4.address }} \
  --control-plane-endpoint={{ ansible_default_ipv4.address }}
```

This leads to certificates that contain only IP addresses in SAN, but not DNS names.

## Solution

### 1. New Playbook for creating cluster with DNS support

Created file `initialize_kubernetes_cluster_with_dns.yml`, which:

- Uses **kubeadm configuration file** instead of command line
- Adds **DNS names to certSANs** for API server
- Sets **control-plane-endpoint** as FQDN instead of IP

**Key improvements:**
```yaml
apiServer:
  certSANs:
  - {{ ansible_default_ipv4.address }}     # IP address
  - {{ ansible_hostname }}                 # Short name
  - {{ ansible_fqdn }}                     # Full DNS name
  - localhost                              # Local access
  - 127.0.0.1                             
  - kubernetes                             # Standard names
  - kubernetes.default
  - kubernetes.default.svc
  - kubernetes.default.svc.cluster.local
controlPlaneEndpoint: "{{ ansible_fqdn }}:6443"  # Uses FQDN
```

### 2. Playbook for updating existing clusters

Created file `regenerate_certificates_with_dns.yml` for clusters that are already deployed:

**Process:**
1. Creates backup of existing certificates
2. Stops kubelet and containerd
3. Removes old API server certificates
4. Generates new certificates with DNS names
5. Updates kubeconfig files
6. Restarts services

### 3. Enhanced get-kubeconfig function

Created script `enhanced_get_kubeconfig.sh`, which:

- **Prioritizes DNS names** over IP addresses
- **Checks DNS resolution** before using hostname
- **Tests connection** to API server
- **Automatically falls back** to IP on DNS issues

## Solution Benefits

### ✅ Resilience to IP changes
- Cluster remains accessible when DHCP IP addresses change
- DNS names of servers remain constant

### ✅ Better DNS integration
- Ability to use internal DNS infrastructure
- Support for complex network topologies

### ✅ Compatibility
- Supports both DNS names and IP addresses
- Automatic fallback to IP on DNS issues

### ✅ Security
- Certificates contain all necessary SANs
- No warnings about untrusted certificates

## Usage

### For new clusters

```bash
# Use the new playbook instead of the standard one
ansible-playbook -i ansible/inventory/tofu_inventory.py \
  ansible/playbooks/initialize_kubernetes_cluster_with_dns.yml
```

### For existing clusters

```bash
# Update certificates with DNS support
ansible-playbook -i ansible/inventory/tofu_inventory.py \
  ansible/playbooks/regenerate_certificates_with_dns.yml
```

### Getting kubeconfig with DNS support

```bash
# Use the enhanced function
source scripts/enhanced_get_kubeconfig.sh
enhanced_get_kubeconfig --use-hostname
```

## Result Verification

After applying the solution:

```bash
# Check SAN in certificate
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A 10 "Subject Alternative Name"

# Check access via DNS name
kubectl --server=https://cu1.bevz.net:6443 get nodes

# Check kubeconfig
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}'
```

## Important Notes

1. **DNS must be configured** correctly for all cluster nodes
2. **Certificate backup** is created automatically during updates
3. **Temporary API server interruption** is possible during certificate updates
4. **Worker nodes** will reconnect automatically after updates

## CPC Integration

For integration with the main CPC tool:

1. Replace the call to `initialize_kubernetes_cluster.yml` with `initialize_kubernetes_cluster_with_dns.yml` in the bootstrap function
2. Add command for certificate updates: `cpc regenerate-certificates`
3. Update the `get-kubeconfig` function to use DNS names

This ensures full DNS name support in your Kubernetes infrastructure!
