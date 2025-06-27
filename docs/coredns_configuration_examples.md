# CoreDNS Local Domain Configuration - Example Output

## Before Configuration

```bash
$ kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'
```

```
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

## After Configuration (with cpc configure-coredns)

```bash
$ kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'
```

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

.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

## Command Examples

### Basic Configuration (Default Settings)
```bash
$ ./cpc configure-coredns
Loading secrets from secrets.sops.yaml...
Successfully loaded secrets (PROXMOX_HOST: homelab.bevz.net, VM_USERNAME: abevz)
Loaded environment variables from cpc.env
Set template variables for workspace 'ubuntu':
  TEMPLATE_VM_ID: 9420
  TEMPLATE_VM_NAME: tpl-ubuntu-2404-k8s
  IMAGE_NAME: ubuntu-24.04-server-cloudimg-amd64.img
  KUBERNETES_VERSION: v1.31
  CALICO_VERSION: v3.28.0
  METALLB_VERSION: v0.14.8
  COREDNS_VERSION: v1.11.3
  ETCD_VERSION: v3.5.15
Getting DNS server from Terraform variables...
Found DNS server in Terraform: 10.10.10.187
Configuring CoreDNS for local domain resolution...
  DNS Server: 10.10.10.187
  Domains: bevz.net,bevz.dev,bevz.pl
Continue with CoreDNS configuration? [y/N] y
Running CoreDNS configuration playbook...
```

### Custom DNS Server
```bash
$ ./cpc configure-coredns --dns-server 192.168.1.10
Configuring CoreDNS for local domain resolution...
  DNS Server: 192.168.1.10
  Domains: bevz.net,bevz.dev,bevz.pl
Continue with CoreDNS configuration? [y/N] y
```

### Custom Domains
```bash
$ ./cpc configure-coredns --domains example.com,test.local,internal.dev
Getting DNS server from Terraform variables...
Found DNS server in Terraform: 10.10.10.187
Configuring CoreDNS for local domain resolution...
  DNS Server: 10.10.10.187
  Domains: example.com,test.local,internal.dev
Continue with CoreDNS configuration? [y/N] y
```

## Verification

### Test DNS Resolution
```bash
# Test from a pod
$ kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup cu1.bevz.net
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      cu1.bevz.net
Address 1: 10.10.10.10

# Test cluster internal resolution (should still work)
$ kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default.svc.cluster.local
Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
```

### Check CoreDNS Logs
```bash
$ kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
[INFO] plugin/reload: Running configuration SHA512 = ...
[INFO] 10.244.1.1:57230 - 43567 "A IN cu1.bevz.net. udp 32 false 512" NOERROR qr,rd,ra 71 0.002341042s
[INFO] 10.244.1.1:45123 - 12345 "A IN kubernetes.default.svc.cluster.local. udp 54 false 512" NOERROR qr,aa,rd 106 0.000123456s
```

## Integration with Pi-hole

This configuration works together with the Pi-hole DHCP fixes documented in `dns_lan_suffix_problem_solution.md`:

1. **Pi-hole DHCP**: Sends correct domain-search options to VMs
2. **CoreDNS**: Forwards local domain queries to Pi-hole
3. **VM DNS**: Uses CoreDNS for all DNS resolution
4. **Pi-hole DNS**: Resolves local domains and forwards external queries

## Troubleshooting

### Configuration Not Applied
```bash
# Check if CoreDNS pods restarted
$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Force restart if needed
$ kubectl rollout restart deployment/coredns -n kube-system
```

### DNS Still Not Working
```bash
# Check if the configuration is in the ConfigMap
$ kubectl get configmap coredns -n kube-system -o yaml | grep -A 10 "bevz.net"

# Check Pi-hole is accessible from nodes
$ kubectl run network-test --image=busybox --rm -it --restart=Never -- ping 10.10.10.187
```

### Restore from Backup
```bash
# List backups
$ ls -la /tmp/coredns-configmap-backup-*.yaml

# Restore
$ kubectl apply -f /tmp/coredns-configmap-backup-<timestamp>.yaml
$ kubectl rollout restart deployment/coredns -n kube-system
```
