# CoreDNS Local Domain Configuration

## Overview

This document describes how to configure CoreDNS in your Kubernetes cluster to forward local domain queries to your Pi-hole DNS server.

## Purpose

When you have local domains (like `bevz.net`, `bevz.dev`, `bevz.pl`) that are managed by Pi-hole, you need to configure CoreDNS to forward queries for these domains to Pi-hole instead of trying to resolve them through upstream DNS servers.

## Configuration

### Automatic Configuration (Recommended)

Use the `cpc configure-coredns` command to automatically configure CoreDNS:

```bash
# Configure with defaults (uses dns_servers from Terraform variables.tf)
./cpc configure-coredns

# Configure with custom Pi-hole IP
./cpc configure-coredns --dns-server 192.168.1.10

# Configure with custom domains
./cpc configure-coredns --domains example.com,test.local

# Show help
./cpc configure-coredns --help
```

### Manual Configuration

If you prefer to configure manually, you can run the Ansible playbook directly:

```bash
# Configure with default settings
ansible-playbook ansible/playbooks/configure_coredns_local_domains.yml -i ansible/inventory -l control_plane

# Configure with custom variables
ansible-playbook ansible/playbooks/configure_coredns_local_domains.yml -i ansible/inventory -l control_plane \
  -e 'dns_servers=["192.168.1.10"]' \
  -e '{"local_domains": ["example.com", "test.local"]}'
```

## What the Configuration Does

The configuration adds the following blocks to the CoreDNS Corefile:

```
# --- Local domain forwarding to Pi-hole ---
bevz.net:53 {
    errors
    cache 30
    # Forward to Pi-hole DNS server
    forward . 10.10.10.187
}

bevz.dev:53 {
    errors
    cache 30
    # Forward to Pi-hole DNS server
    forward . 10.10.10.187
}

bevz.pl:53 {
    errors
    cache 30
    # Forward to Pi-hole DNS server
    forward . 10.10.10.187
}
# ----------------------------------------
```

## How It Works

1. **DNS Server Detection**: The script automatically extracts the Pi-hole IP from:
   - Terraform output (if available)
   - `terraform.tfvars` file
   - `variables.tf` default values
   - Fallback to `10.10.10.36`

2. **ConfigMap Backup**: Creates a backup of the current CoreDNS ConfigMap before making changes

3. **Configuration Update**: Adds local domain forwarding blocks to the beginning of the Corefile

4. **Deployment Restart**: Restarts the CoreDNS deployment to apply the new configuration

5. **Verification**: Tests DNS resolution to ensure the configuration works

## DNS Flow

```
Pod DNS Query for bevz.net → CoreDNS → Pi-hole (10.10.10.187) → Response
Pod DNS Query for google.com → CoreDNS → Upstream DNS → Response
```

## Files Involved

- **`ansible/playbooks/configure_coredns_local_domains.yml`**: Main Ansible playbook
- **`scripts/get_dns_server.sh`**: Script to extract DNS server IP from Terraform
- **`terraform/variables.tf`**: Contains `dns_servers` variable with Pi-hole IP
- **`cpc`**: Main command script with `configure-coredns` command

## Troubleshooting

### Check Current CoreDNS Configuration

```bash
kubectl get configmap coredns -n kube-system -o yaml
```

### Check CoreDNS Pods

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

### Test DNS Resolution

```bash
# Test from within a pod
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup your-domain.bevz.net

# Test from a node
dig your-domain.bevz.net @<coredns-service-ip>
```

### View CoreDNS Logs

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### Restore from Backup

If something goes wrong, you can restore from the backup:

```bash
# List available backups
ls -la /tmp/coredns-configmap-backup-*.yaml

# Restore from backup
kubectl apply -f /tmp/coredns-configmap-backup-<timestamp>.yaml
kubectl rollout restart deployment/coredns -n kube-system
```

## Integration with Pi-hole

This configuration works in conjunction with:

1. **Pi-hole DNS Configuration**: Ensure Pi-hole has the correct local DNS records
2. **DHCP Configuration**: As documented in `dns_lan_suffix_problem_solution.md`
3. **Network Configuration**: Ensure proper routing between Kubernetes nodes and Pi-hole

## Variables

The configuration uses the following variables:

- **`dns_servers`**: List of DNS servers (Pi-hole IP) from Terraform `variables.tf`
- **`local_domains`**: List of domains to forward to Pi-hole (default: `bevz.net`, `bevz.dev`, `bevz.pl`)

## Security Considerations

- CoreDNS forwards queries only for specified local domains
- Cache timeout is set to 30 seconds for local domains
- Backup is created before any changes
- Configuration is applied with proper error handling
