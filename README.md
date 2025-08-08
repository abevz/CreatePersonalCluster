# Create Personal Cluster - CPC (Cluster Provisioning Control)

A comprehensive Kubernetes cluster deployment system using Proxmox VE, Terraform, and Ansible.

## Project Overview

This project provides a complete solution for deploying production-ready Kubernetes clusters using infrastructure as code. The system includes:

- **CPC Script**: Cluster Provisioning Control tool for managing the entire lifecycle
- **VM Template Creation**: Automated creation of optimized VM templates for different OS distributions
- **Infrastructure as Code**: Terraform-based infrastructure provisioning
- **Configuration Management**: Ansible-based cluster configuration and addon management
- **Multi-Distribution Support**: Currently supports Ubuntu and SUSE distributions

## Inspiration

This project draws inspiration from [ClusterCreator](https://github.com/christensenjairus/ClusterCreator) by Jairus Christensen, particularly for its automated cluster provisioning methodology.

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
   # Edit cpc.env with your global configuration
   ./cpc setup-cpc
   ```
   
   📖 **For detailed setup instructions, see [Project Setup Guide](docs/project_setup_guide.md)**

2. **Choose and configure workspace**:
   ```bash
   ./cpc list-workspaces                    # See available workspaces
   ./cpc clone-workspace ubuntu myproject  # Create custom workspace
   ./cpc ctx myproject                      # Switch to your workspace
   ./cpc template                           # Create VM template
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

## Workspace System

CPC uses a modular workspace system to manage different environments. Workspaces allow you to:
- Use different OS distributions (Ubuntu, Debian, Rocky, SUSE)
- Configure different Kubernetes versions for each workspace
- Customize component versions per workspace
- Easily create new workspaces from existing ones

### Managing Workspaces
```bash
# List available workspaces
./cpc list-workspaces

# Switch to a workspace  
./cpc ctx ubuntu

# Create a new workspace based on an existing one
./cpc clone-workspace ubuntu my-custom-workspace

# Delete a custom workspace (keeps built-in workspaces safe)
./cpc delete-workspace my-custom-workspace

# View current workspace status
./cpc ctx
```

Each workspace has its own environment file in the `envs/` directory. See [Workspace Environments](envs/README.md) for details.

### Supported Workspaces

#### ✅ Fully Functional
- **Ubuntu 24.04**: Complete support with all features working
- **SUSE**: Complete support with all features working
- **Kubernetes 1.29**: Specialized workspace for Kubernetes 1.29

#### 🚧 In Development
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
- [Modular Workspace System](docs/modular_workspace_system.md) - New workspace management system
- [Hostname Generation System](docs/hostname_generation_system.md) - RELEASE_LETTER and hostname patterns
- [Cluster Deployment Guide](docs/cluster_deployment_guide.md) - Complete deployment walkthrough
- [CPC Commands Reference](docs/cpc_commands_reference.md) - Complete command documentation
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

### Modular Workspace System
CPC uses a modular workspace system with environment files in the `envs/` directory:

```bash
envs/
├── debian.env      # Debian workspace configuration
├── ubuntu.env      # Ubuntu workspace configuration  
├── rocky.env       # Rocky Linux workspace configuration
├── suse.env        # SUSE workspace configuration
└── k8s129.env      # Custom Kubernetes 1.29 workspace
```

Each workspace file contains distribution-specific configuration:

```bash
# From envs/ubuntu.env
TEMPLATE_VM_ID="9420"
TEMPLATE_VM_NAME="tpl-ubuntu-2404-k8s"
KUBERNETES_VERSION="v1.31"
CALICO_VERSION="v3.28.0"
RELEASE_LETTER="u"
```

### Workspace Management
Create and manage custom workspaces:

```bash
./cpc list-workspaces                    # List available workspaces
./cpc clone-workspace ubuntu myproject  # Clone ubuntu config to myproject
./cpc ctx myproject                      # Switch to myproject workspace
./cpc delete-workspace myproject        # Delete custom workspace
```

## Project Structure

```
CreatePersonalCluster/
├── cpc                    # Main CPC script
├── cpc.env               # Global configuration file  
├── envs/                 # Workspace environment files
│   ├── debian.env        # Debian workspace
│   ├── ubuntu.env        # Ubuntu workspace
│   ├── rocky.env         # Rocky Linux workspace
│   └── suse.env          # SUSE workspace
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
