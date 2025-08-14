# CPC Workspace Environments

This directory contains environment files for different workspaces. Each file defines workspace-specific variables like Kubernetes versions, template VM IDs, image names, etc.

## Overview

CPC (Cluster Provisioning Control) now uses a modular approach to manage workspace environments. Instead of having all workspace configurations in a single `cpc.env` file, each workspace has its own `.env` file in this directory.

## Available Workspaces

- `ubuntu.env`: Ubuntu-based workspace
- `debian.env`: Debian-based workspace
- `rocky.env`: Rocky Linux-based workspace
- `suse.env`: SUSE Linux-based workspace
- `k8s129.env`: Specialized workspace for Kubernetes 1.29
- `k8s133.env`: Specialized workspace for Kubernetes 1.33

## Node Naming Convention

When specifying additional worker or control plane nodes, you can use either:

1. **Recommended Format** (explicit index): `worker-3`, `worker-4`, `controlplane-2`
2. **Legacy Format**: `worker3`, `worker4`, `controlplane2`

Example configuration in environment file:
```
ADDITIONAL_WORKERS="worker-3,worker-4,worker-5"
ADDITIONAL_CONTROLPLANES="controlplane-2"
```

The explicit index format is recommended as it provides stable VM IDs and prevents unintended VM recreation when removing nodes. See [Node Naming Convention](../docs/node_naming_convention.md) for details.

## Creating New Workspaces

You can create new workspace environments using the `clone-workspace` command:

```bash
cpc clone-workspace <source_workspace> <destination_workspace>
```

For example:
```bash
cpc clone-workspace ubuntu my-custom-workspace
```

This will:
1. Create a new `.env` file for your workspace
2. Create a new Terraform/OpenTofu workspace
3. Allow you to customize the workspace settings

## Workspace Environment Variables

Each workspace environment file contains the following variables:

### Template VM Configuration
- `TEMPLATE_VM_ID`: The VM template ID in Proxmox
- `TEMPLATE_VM_NAME`: The name of the VM template
- `IMAGE_NAME`: The OS image name to use
- `IMAGE_LINK`: The download URL for the OS image

### Kubernetes Component Versions
- `KUBERNETES_SHORT_VERSION`: Short version (e.g., "1.29")
- `KUBERNETES_MEDIUM_VERSION`: Medium version with v prefix (e.g., "v1.29")
- `KUBERNETES_LONG_VERSION`: Full version (e.g., "1.29.8")
- `CNI_PLUGINS_VERSION`: CNI plugins version
- `CALICO_VERSION`: Calico CNI version
- `METALLB_VERSION`: MetalLB version
- `COREDNS_VERSION`: CoreDNS version
- `METRICS_SERVER_VERSION`: Metrics Server version
- `ETCD_VERSION`: etcd version
- `KUBELET_SERVING_CERT_APPROVER_VERSION`: Kubelet certificate approver version
- `LOCAL_PATH_PROVISIONER_VERSION`: Local path provisioner version
- `CERT_MANAGER_VERSION`: Cert Manager version
- `ARGOCD_VERSION`: ArgoCD version
- `INGRESS_NGINX_VERSION`: NGINX Ingress Controller version

### VM Specifications
- `VM_CPU_CORES`: Number of CPU cores for VMs
- `VM_MEMORY_DEDICATED`: Memory in MB for VMs
- `VM_DISK_SIZE`: Disk size in GB for VMs
- `VM_STARTED`: Whether VMs should start automatically
- `VM_DOMAIN`: Domain suffix for VM hostnames

## Switching Workspaces

To switch to a different workspace, use:

```bash
cpc ctx <workspace_name>
```

This will load the appropriate workspace-specific environment variables.
