# Kubernetes The Hard Way - CPC (Cluster Provisioning Control)

A comprehensive Kubernetes cluster deployment system using Proxmox VE, Terraform, and Ansible.

## Project Overview

This project provides a complete solution for deploying production-ready Kubernetes clusters using infrastructure as code. The system includes:

- **CPC Script**: Cluster Provisioning Control tool for managing the entire lifecycle
- **VM Template Creation**: Automated creation of optimized VM templates for different OS distributions
- **Infrastructure as Code**: Terraform-based infrastructure provisioning
- **Configuration Management**: Ansible-based cluster configuration and addon management
- **Multi-Distribution Support**: Currently supports Ubuntu and SUSE distributions

## Quick Start

### Prerequisites

- Proxmox VE 8.0+ server
- Terraform/OpenTofu installed
- Ansible installed
- SSH key pair configured

### Basic Usage

1. **Initialize environment**:
   ```bash
   cp cpc.env.example cpc.env
   # Edit cpc.env with your configuration
   ./cpc setup-cpc
   ```

2. **Set cluster context and create VM template**:
   ```bash
   ./cpc ctx ubuntu
   ./cpc template
   ```

3. **Deploy infrastructure and bootstrap cluster**:
   ```bash
   ./cpc deploy apply                # Deploy VMs
   ./cpc bootstrap                   # Bootstrap Kubernetes cluster
   ./cpc get-kubeconfig             # Get cluster access
   ```

4. **Install addons**:
   ```bash
   ./cpc upgrade-addons             # Interactive menu
   # or direct installation:
   ./cpc upgrade-addons --addon all
   ```

## Supported Workspaces

### ✅ Fully Functional
- **Ubuntu 24.04**: Complete support with all features working
- **SUSE**: Complete support with all features working

### 🚧 In Development
- **Debian**: Basic functionality (some features pending)
- **Rocky Linux**: Basic functionality (some features pending)

## Key Features

### VM Template Management
- Automated creation of optimized VM templates
- Support for multiple Linux distributions
- Cloud-init integration for automated provisioning
- SSH key and user account management

### Cluster Deployment
- High-availability control plane setup
- Calico CNI networking
- MetalLB load balancer
- Comprehensive addon ecosystem

### Addon Management
- **Calico CNI**: Advanced networking with IPAM
- **MetalLB**: Load balancer for bare-metal deployments
- **cert-manager**: Certificate management
- **ArgoCD**: GitOps continuous delivery
- **ingress-nginx**: Ingress controller
- **Metrics Server**: Resource metrics collection
- **kubelet-serving-cert-approver**: Automatic certificate approval

### Recent Improvements
- ✅ **Fixed Calico CRD annotation size limit issue** - Resolved the 262144 byte annotation limit that prevented "all" addon installations
- ✅ **Enhanced idempotency** - All addon installations now handle re-installation gracefully
- ✅ **Smart version detection** - Prevents unnecessary updates when same versions are already running
- ✅ **MetalLB stability** - Resolved crashloop issues with improved timing and error handling

## Documentation

### Core Documentation
- [Architecture Overview](docs/architecture.md) - System architecture and design principles
- [Cluster Deployment Guide](docs/cluster_deployment_guide.md) - Complete deployment walkthrough
- [CPC Template Variables Guide](docs/cpc_template_variables_guide.md) - Configuration reference

### Troubleshooting Guides
- [SSH Management Commands](docs/ssh_management_commands.md) - SSH connection and known_hosts management
- [SSH Key Troubleshooting](docs/ssh_key_troubleshooting.md) - SSH authentication issues
- [Template SSH Troubleshooting](docs/template_ssh_troubleshooting.md) - VM template SSH problems
- [Cloud-Init User Issues](docs/cloud_init_user_issues.md) - User account creation problems
- [Proxmox VM Helper](docs/proxmox_vm_helper.md) - VM management utilities

### Status Reports
- [Project Status Report](docs/project_status_report.md) - Current development status
- [Addon Installation Report](docs/addon_installation_completion_report.md) - Recent addon improvements

### Component Documentation
- [Ansible Configuration](ansible/README.md) - Playbooks and automation details
  - [Ansible Playbooks](ansible/playbooks/README.md) - Detailed playbook documentation
- [Terraform Infrastructure](terraform/README.md) - Infrastructure as code documentation
- [Scripts and Utilities](scripts/README.md) - Helper scripts and tools

## Configuration

### Environment Setup
The `cpc.env` file contains all configuration variables:

```bash
# Proxmox Configuration
PROXMOX_HOST="your-proxmox-host"
VM_USERNAME="your-username"

# Template Configuration
TEMPLATE_VM_ID_UBUNTU="9420"
TEMPLATE_VM_NAME_UBUNTU="tpl-ubuntu-2404-k8s"

# Kubernetes Versions (per workspace)
KUBERNETES_VERSION_UBUNTU="v1.31"
CALICO_VERSION_UBUNTU="v3.28.0"
METALLB_VERSION_UBUNTU="v0.14.8"
```

### Workspace Selection
Use the `--workspace` flag to specify which distribution to use:

```bash
./cpc template --workspace ubuntu    # Ubuntu 24.04
./cpc template --workspace suse      # SUSE
./cpc bootstrap --workspace ubuntu   # Deploy Ubuntu-based cluster
```

## Project Structure

```
my-kthw/
├── cpc                    # Main CPC script
├── cpc.env               # Configuration file
├── ansible/              # Ansible playbooks and roles
├── terraform/            # Infrastructure as code
├── scripts/              # Utility scripts
└── docs/                 # Documentation
```

## Contributing

1. Follow the established code organization
2. Update documentation for any changes
3. Test changes with supported workspaces
4. Ensure all comments are in English

## License

This project is provided as-is for educational and production use.

## Support

For issues and questions:
1. Check the troubleshooting guides in the `docs/` directory
2. Review the architecture documentation
3. Examine the configuration examples

---

**Note**: This project implements Kubernetes deployment following security best practices and production-ready configurations. All templates and configurations are optimized for performance and reliability.
