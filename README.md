# 🚀 Create Personal Cluster (CPC)

> ⚠️ **DEPRECATED: This project has evolved into [platform-iac](https://github.com/abevz/platform-iac)**
>
> CPC has been superseded by **platform-iac** - a more modular, enterprise-ready Infrastructure as Code solution.
> All active development has moved to the new repository.
> 
> **Key improvements in platform-iac:**
> - **35+ modular Ansible roles** vs monolithic single role in CPC
> - **Molecule testing framework** for Ansible roles
> - **Native OpenTofu tests** (tftest.hcl)
> - **iac-wrapper.sh** - unified CLI for all operations
> - **Cleaner architecture** with separated concerns
> - **Full English documentation** and comments
>
> ➡️ **Please use [platform-iac](https://github.com/abevz/platform-iac) for new deployments**

---

[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31+-blue.svg)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/Terraform-1.0+-purple.svg)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-2.15+-red.svg)](https://www.ansible.com/)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE_8.0+-orange.svg)](https://www.proxmox.com/)

> **Complete Kubernetes cluster deployment and management system** using Proxmox VE, Terraform/OpenTofu, and Ansible automation.

---

## 📋 Table of Contents

- [🔒 Security & Secrets](#-security--secrets)
- [🎯 Overview](#-overview)
- [✨ Key Features](#-key-features)
- [🚀 Quick Start](#-quick-start)
- [📖 Documentation](#-documentation)
- [🛠️ Installation & Setup](#%EF%B8%8F-installation--setup)
- [💻 Usage Examples](#-usage-examples)
- [🏗️ Architecture](#%EF%B8%8F-architecture)
- [🔧 Configuration](#-configuration)
- [📚 Workspace System](#-workspace-system)
- [🧪 Testing & Validation](#-testing--validation)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

---

## 🔒 Security & Secrets

**⚠️ IMPORTANT**: This project handles sensitive information including API keys, passwords, and tokens. Always follow security best practices:

### 🚨 Never Commit Secrets
- **DO NOT** commit files containing real secrets to version control
- Use `secrets.sops.yaml` (encrypted with SOPS) for sensitive data
- Temporary files like `secrets_temp.yaml` are **automatically ignored**
- Always run `gitleaks detect` before pushing to check for exposed secrets

### 🔐 Secret Management
- Use [SOPS](https://github.com/getsops/sops) for encrypting secrets
- Store encrypted secrets in `secrets.sops.yaml`
- Decrypt only when needed: `sops decrypt secrets.sops.yaml`
- Never store decrypted secrets in the repository

### 🛡️ Security Tools
- Run `gitleaks detect` regularly to scan for exposed secrets
- Use `.gitignore` to prevent accidental commits of sensitive files
- Rotate compromised credentials immediately

---

## 🎯 Overview

**CPC (Cluster Provisioning Control)** is a comprehensive, production-ready solution for deploying and managing Kubernetes clusters on Proxmox Virtual Environment. Built with infrastructure as code principles, it provides:

- **🔄 Complete Lifecycle Management**: From VM template creation to cluster operations
- **🏗️ Infrastructure as Code**: Terraform/OpenTofu-based provisioning
- **⚙️ Configuration Management**: Ansible-powered cluster configuration
- **🌐 Multi-Distribution Support**: Ubuntu, Debian, Rocky Linux, SUSE
- **📦 Rich Addon Ecosystem**: Calico CNI, MetalLB, cert-manager, ArgoCD, and more
- **🔒 Security-First**: Production-ready configurations with best practices

### 🎯 Use Cases

- **🏠 Home Lab Clusters**: Perfect for personal Kubernetes experimentation
- **🏢 Development Environments**: Isolated development and testing clusters
- **🏭 Production Deployments**: Enterprise-grade cluster management
- **🎓 Learning Platform**: Educational Kubernetes deployments

---

## ✨ Key Features

### 🖥️ Infrastructure Management
- ✅ **Automated VM Template Creation** - Optimized templates for multiple OS distributions
- ✅ **Dynamic IP Management** - Smart IP allocation with conflict prevention
- ✅ **Multi-Workspace Support** - Isolated environments for different projects
- ✅ **Cloud-Init Integration** - Automated VM provisioning and configuration

### 🚢 Kubernetes Operations
- ✅ **High-Availability Clusters** - Production-ready control plane setup
- ✅ **Automated Bootstrap** - One-command cluster deployment
- ✅ **Node Scaling** - Add/remove nodes dynamically
- ✅ **Certificate Management** - Automated SSL certificate handling

### 📦 Addon Ecosystem
- ✅ **Calico CNI** - Advanced networking with IPAM
- ✅ **MetalLB** - Load balancer for bare-metal deployments
- ✅ **cert-manager** - Automated certificate management
- ✅ **ArgoCD** - GitOps continuous delivery
- ✅ **ingress-nginx** - Kubernetes ingress controller
- ✅ **Metrics Server** - Resource monitoring and metrics
- ✅ **CoreDNS** - DNS service with local domain forwarding

### 🔧 Developer Experience
- ✅ **Modular Architecture** - Clean, maintainable codebase
- ✅ **Comprehensive CLI** - Intuitive command-line interface
- ✅ **Rich Documentation** - Extensive guides and troubleshooting
- ✅ **Error Handling** - Robust error detection and recovery

---

## 🚀 Quick Start

### 📋 Prerequisites

- **Proxmox VE 8.0+** server with API access
- **Terraform/OpenTofu** installed on management machine
- **Ansible** installed on management machine
- **SSH key pair** configured for passwordless access

### ⚡ 5-Minute Setup

```bash
# 1. Clone and configure
git clone <repository-url>
cd CreatePersonalCluster
cp cpc.env.example cpc.env
# Edit cpc.env with your Proxmox details

# 2. Initial setup
./cpc setup-cpc

# 3. Create your workspace
./cpc clone-workspace ubuntu my-cluster
./cpc ctx my-cluster

# 4. Create VM template
./cpc template

# 5. Deploy and bootstrap
./cpc deploy apply
./cpc bootstrap

# 6. Install addons
./cpc upgrade-addons
```

**🎉 Your cluster is ready!** Access it with:
```bash
./cpc get-kubeconfig
kubectl get nodes
```

---

## 📖 Documentation

### 📚 Getting Started
- **[📖 Complete Cluster Creation Guide](docs/complete_cluster_creation_guide.md)** - Step-by-step deployment
- **[🔄 Complete Workflow Guide](docs/complete_workflow_guide.md)** - Full workflow walkthrough
- **[🏗️ Architecture Overview](docs/architecture.md)** - System design and principles
- **[⚙️ Project Setup Guide](docs/project_setup_guide.md)** - Detailed setup instructions

### 🛠️ Reference Documentation
- **[📋 CPC Commands Reference](docs/cpc_commands_reference.md)** - Complete command reference
- **[🔧 CPC Template Variables Guide](docs/cpc_template_variables_guide.md)** - Configuration variables
- **[🌐 Modular Workspace System](docs/modular_workspace_system.md)** - Workspace management
- **[📡 Static IP Configuration](docs/static_ip_configuration.md)** - IP management guide

### 🔍 Troubleshooting
- **[🔑 SSH Key Troubleshooting](docs/ssh_key_troubleshooting.md)** - SSH authentication issues
- **[🌐 DNS Certificate Solution](docs/kubernetes_dns_certificate_solution.md)** - DNS/certificates
- **[🐛 Cluster Troubleshooting](docs/cluster_troubleshooting_commands.md)** - Common issues
- **[📊 Project Status Report](docs/project_status_report.md)** - Current development status

---

## 🛠️ Installation & Setup

### 1️⃣ System Requirements

**Management Machine:**
```bash
# Required packages
sudo apt update
sudo apt install -y ansible terraform python3-pip jq curl

# Install OpenTofu (alternative to Terraform)
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh
```

**Proxmox Server:**
- Proxmox VE 8.0 or higher
- API access enabled
- SSH access configured
- Sufficient resources (CPU, RAM, Storage)

### 2️⃣ Project Setup

```bash
# Clone repository
git clone <repository-url>
cd CreatePersonalCluster

# Configure environment
cp cpc.env.example cpc.env
nano cpc.env  # Edit with your Proxmox details

# Initial setup
./cpc setup-cpc
```

### 3️⃣ Proxmox Configuration

**Required Settings in `cpc.env`:**
```bash
# Proxmox connection
PROXMOX_HOST="192.168.1.100"
PROXMOX_USERNAME="root@pam"
PROXMOX_PASSWORD="your-password"

# Network configuration
NETWORK_CIDR="192.168.1.0/24"
NETWORK_GATEWAY="192.168.1.1"
STATIC_IP_START="110"

# DNS settings
PRIMARY_DNS_SERVER="192.168.1.10"
SECONDARY_DNS_SERVER="8.8.8.8"
```

---

## 💻 Usage Examples

### 🏗️ Basic Cluster Deployment

```bash
# Create and switch to workspace
./cpc clone-workspace ubuntu production
./cpc ctx production

# Deploy infrastructure
./cpc deploy plan    # Review changes
./cpc deploy apply   # Deploy VMs

# Bootstrap Kubernetes
./cpc bootstrap

# Verify cluster
./cpc status
kubectl get nodes
```

### 🔄 Cluster Scaling

```bash
# Add worker node
./cpc add-vm
# Follow interactive prompts

# Remove node
./cpc remove-vm
# Select node to remove

# Check cluster health
./cpc cluster-info
```

### 📦 Addon Management

```bash
# Interactive addon installation
./cpc upgrade-addons

# Install specific addon
./cpc upgrade-addons --addon metallb

# Install all addons
./cpc upgrade-addons --addon all
```

### 🔍 Debug Mode

CPC supports debug mode for troubleshooting and development:

```bash
# Enable debug output for any command
./cpc --debug deploy plan
./cpc --debug ctx
./cpc --debug bootstrap

# Short form
./cpc -d deploy apply

# Debug shows:
# - Secret loading details
# - Template variable processing
# - Command execution steps
# - Detailed error information
```

**When to use debug mode:**
- Troubleshooting deployment issues
- Understanding command execution flow
- Development and testing
- Investigating configuration problems

**Note:** Debug mode displays sensitive information like secrets and credentials. Use only when necessary and avoid in production environments.

### 🌐 DNS & SSL Management

```bash
# Configure CoreDNS for local domains
./cpc configure-coredns

# Test DNS resolution
./cpc test-dns example.local

# Verify certificates
./cpc verify-certificates
```

### 🔧 Workspace Management

```bash
# List available workspaces
./cpc list-workspaces

# Create development environment
./cpc clone-workspace ubuntu dev
./cpc ctx dev

# Switch between environments
./cpc ctx production
./cpc ctx staging
./cpc ctx dev
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    CPC Management Layer                     │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                    Main CPC Script                      │ │
│  │                                                         │ │
│  │  • Command parsing & routing                           │ │
│  │  • Configuration management                            │ │
│  │  • Module orchestration                                │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────┐
│                 Modular Architecture Layer                  │
│  ┌─────────────┬─────────────┬─────────────┬─────────────┐ │
│  │ 00_core.sh  │ 20_ansible  │ 30_k8s      │ 40_k8s      │ │
│  │             │ .sh         │ _cluster.sh │ _nodes.sh   │ │
│  │ • Workspace  │ • Playbook  │ • Bootstrap │ • Scaling   │ │
│  │ • Context    │ • Secrets   │ • K8s init  │ • Node mgmt │ │
│  │ • Utilities  │ • Inventory │ • Addons    │ • Health    │ │
│  └─────────────┴─────────────┴─────────────┴─────────────┘ │
└─────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────┐
│                 Infrastructure Layer                        │
│  ┌─────────────────────┬───────────────────────────────────┐ │
│  │   Terraform/        │           Ansible                 │ │
│  │   OpenTofu          │           Playbooks               │ │
│  │                     │                                   │ │
│  │ • VM provisioning   │ • K8s installation                │ │
│  │ • Network config    │ • Addon deployment                │ │
│  │ • Resource mgmt     │ • Configuration management        │ │
│  └─────────────────────┴───────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────┐
│                 Proxmox VE Infrastructure                   │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Kubernetes Cluster                         │ │
│  │                                                         │ │
│  │  Control Plane Nodes        Worker Nodes               │ │
│  │  ┌─────────┬─────────┐    ┌─────────┬─────────┬─────────┐ │
│  │  │ CP-1    │ CP-2    │    │ W-1     │ W-2     │ W-3     │ │
│  │  │ Ubuntu  │ Ubuntu  │    │ Ubuntu  │ Ubuntu  │ Ubuntu  │ │
│  │  │ K8s     │ K8s     │    │ K8s     │ K8s     │ K8s     │ │
│  │  │ v1.31   │ v1.31   │    │ v1.31   │ v1.31   │ v1.31   │ │
│  │  └─────────┴─────────┘    └─────────┴─────────┴─────────┘ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 🏗️ System Components

- **CPC Script**: Main orchestration tool
- **Modules**: Specialized functionality (core, ansible, k8s, etc.)
- **Terraform**: Infrastructure provisioning
- **Ansible**: Configuration management
- **Proxmox VE**: Virtualization platform
- **Kubernetes**: Container orchestration

---

## 🔧 Configuration

### 📁 Project Structure

```
CreatePersonalCluster/
├── cpc                          # Main CPC script
├── cpc.env                      # Global configuration
├── cpc.env.example              # Configuration template
├── modules/                     # Core functionality modules
│   ├── 00_core.sh              # Workspace & context management
│   ├── 20_ansible.sh           # Ansible integration
│   ├── 30_k8s_cluster.sh       # K8s bootstrap & addons
│   ├── 40_k8s_nodes.sh         # Node management
│   ├── 50_cluster_ops.sh       # Cluster operations
│   ├── 60_tofu.sh              # Terraform/OpenTofu integration
│   └── 80_ssh.sh               # SSH management
├── envs/                       # Workspace configurations
│   ├── ubuntu.env              # Ubuntu workspace
│   ├── debian.env              # Debian workspace
│   ├── rocky.env               # Rocky Linux workspace
│   └── suse.env                # SUSE workspace
├── ansible/                    # Ansible automation
│   ├── ansible.cfg            # Ansible configuration
│   ├── inventory/             # Dynamic inventory
│   ├── playbooks/             # Ansible playbooks
│   └── roles/                 # Ansible roles
├── terraform/                  # Infrastructure as code
│   ├── main.tf                # Main configuration
│   ├── variables.tf           # Variable definitions
│   ├── outputs.tf             # Output definitions
│   └── locals.tf              # Local values
├── bashtest/                   # Bash unit tests
│   ├── run_all_tests.sh       # Master test runner
│   ├── bash_test_framework.sh # Testing framework
│   └── test_*.sh              # Module-specific tests
├── tests/                      # Python integration tests
│   ├── unit/                  # Unit tests
│   └── integration/           # Integration tests
├── scripts/                   # Utility scripts
├── docs/                      # Documentation
└── lib/                       # Shared libraries
```

### ⚙️ Configuration Files

#### Global Configuration (`cpc.env`)

```bash
# Proxmox Connection
PROXMOX_HOST="192.168.1.100"
PROXMOX_USERNAME="root@pam"
PROXMOX_PASSWORD="your-secure-password"

# Network Settings
NETWORK_CIDR="192.168.1.0/24"
NETWORK_GATEWAY="192.168.1.1"
STATIC_IP_START="110"
WORKSPACE_IP_BLOCK_SIZE="10"

# DNS Configuration
PRIMARY_DNS_SERVER="192.168.1.10"
SECONDARY_DNS_SERVER="8.8.8.8"

# Kubernetes Settings
KUBERNETES_VERSION="v1.31"
CALICO_VERSION="v3.28.0"

# VM Template Settings
TEMPLATE_VM_ID="9000"
TEMPLATE_VM_NAME="k8s-template"
```

#### Workspace Configuration (`envs/ubuntu.env`)

```bash
# Ubuntu-specific settings
TEMPLATE_VM_ID="9420"
TEMPLATE_VM_NAME="tpl-ubuntu-2404-k8s"
KUBERNETES_VERSION="v1.31"
CALICO_VERSION="v3.28.0"
RELEASE_LETTER="u"
VM_USERNAME="ubuntu"
```

#### Secrets Configuration (`terraform/secrets.sops.yaml`)

CPC uses [Mozilla SOPS](https://github.com/mozilla/sops) for secure secret management. All sensitive data is encrypted and stored in `terraform/secrets.sops.yaml`.

**📖 For detailed secrets configuration, see: [Secrets Management Guide](docs/secrets_management_guide.md)**

##### 🔐 Key Security Features

- **🔒 Encrypted Storage**: AES256-GCM encryption with Age keys
- **🚫 No Plaintext**: Secrets never stored in plaintext files
- **🔄 Automatic Decryption**: On-demand decryption during execution
- **📝 Audit Trail**: Track changes and modifications
- **🔑 Key Rotation**: Support for encryption key rotation

##### 📁 Secrets Structure Overview

```yaml
global:          # VM credentials, SSH keys, Docker Hub, Cloudflare
default:         # Infrastructure-specific configs
  proxmox:       # Proxmox VE connection settings
  s3_backend:    # MinIO/S3 backend for Terraform state
  pihole:        # DNS server configuration
  harbor:        # Container registry settings
```

**⚠️ Important**: Never commit decrypted secrets to version control. Always test decryption before production deployment.

---

## 📚 Workspace System

### 🌍 Multi-Workspace Architecture

CPC uses a sophisticated workspace system that allows you to:

- **Maintain multiple environments** (dev, staging, production)
- **Use different OS distributions** per workspace
- **Customize Kubernetes versions** per environment
- **Isolate configurations** between projects

### 🏢 Built-in Workspaces

| Workspace | Status | Description |
|-----------|--------|-------------|
| `ubuntu` | ✅ Production Ready | Ubuntu 24.04 LTS with full feature support |
| `debian` | 🚧 In Development | Debian support with basic functionality |
| `rocky` | 🚧 In Development | Rocky Linux support with basic functionality |
| `suse` | ✅ Production Ready | SUSE Linux with full feature support |
| `k8s129` | ✅ Production Ready | Specialized Kubernetes 1.29 environment |

### 🔄 Workspace Operations

```bash
# List all workspaces
./cpc list-workspaces

# Create custom workspace
./cpc clone-workspace ubuntu my-project

# Switch workspace context
./cpc ctx my-project

# Delete custom workspace
./cpc delete-workspace my-project
```

### 📋 Workspace Configuration

Each workspace has its own environment file in `envs/`:

```bash
# Example: envs/my-project.env
TEMPLATE_VM_ID="9500"
TEMPLATE_VM_NAME="tpl-my-project"
KUBERNETES_VERSION="v1.30"
CALICO_VERSION="v3.27.0"
RELEASE_LETTER="p"
VM_USERNAME="ubuntu"
```

---

## 🧪 Testing & Validation

> 📖 **Detailed Testing Guide**: See [Testing Documentation](docs/testing_guide.md) for comprehensive testing instructions, examples, and best practices.

### 🔧 Automated Testing

```bash
# Run all bash unit tests
./bashtest/run_all_tests.sh

# Run Python integration tests
python -m pytest tests/

# Run specific test modules
./bashtest/test_core_module.sh
./bashtest/test_k8s_cluster_module.sh
```

### ✅ Cluster Health Checks

```bash
# Comprehensive cluster status
./cpc status

# DNS functionality test
./cpc check-cluster-dns

# Certificate validation
./cpc verify-certificates

# Network connectivity test
./cpc test-dns example.local
```

### 🔍 Troubleshooting Tools

```bash
# SSH connection management
./cpc clear-ssh-hosts
./cpc clear-ssh-maps

# VM status and information
./cpc cluster-info

# Ansible inventory update
./cpc update-inventory
```

### 📊 Monitoring & Logs

```bash
# View cluster events
kubectl get events --sort-by=.metadata.creationTimestamp

# Check pod status
kubectl get pods -A

# View logs
kubectl logs -n kube-system deployment/calico-kube-controllers
```

---

## 🤝 Contributing

### 📚 Documentation
- [🧪 Testing Guide](docs/testing_guide.md) - Comprehensive testing documentation with examples
- [🏗️ Architecture](docs/architecture.md) - System architecture and design
- [📖 Project Setup](docs/project_setup_guide.md) - Development environment setup

### 🛠️ Development Setup

```bash
# Fork and clone
git clone https://github.com/your-username/CreatePersonalCluster.git
cd CreatePersonalCluster

# Create development workspace
./cpc clone-workspace ubuntu dev
./cpc ctx dev

# Make changes and test
# ... development work ...

# Submit pull request
```

### 📝 Contribution Guidelines

1. **Follow the modular architecture** - Keep code organized in appropriate modules
2. **Update documentation** - Document any new features or changes
3. **Test thoroughly** - Validate changes across different workspaces
4. **Use English comments** - All code comments must be in English
5. **Follow naming conventions** - Use consistent naming patterns

### 🐛 Issue Reporting

When reporting issues, please include:

- **CPC version**: `./cpc --version`
- **Workspace**: `./cpc ctx`
- **Error logs**: Relevant error messages
- **System info**: Proxmox version, OS details
- **Steps to reproduce**: Clear reproduction steps

---

## 📄 License

This project is provided **as-is** for educational and production use. While every effort has been made to ensure reliability and security, users are responsible for their own deployments and configurations.

### ⚖️ Terms

- **Educational Use**: Free for learning and experimentation
- **Production Use**: Use at your own risk with proper testing
- **Commercial Use**: Contact maintainers for commercial licensing
- **Modifications**: Feel free to modify and distribute

---

## 🙏 Acknowledgments

- **Inspired by**: [ClusterCreator](https://github.com/christensenjairus/ClusterCreator) by Jairus Christensen
- **Community**: Thanks to all contributors and users
- **Open Source**: Built on Terraform, Ansible, Kubernetes, and Proxmox

---

## 📞 Support

### 📚 Documentation
- **[📖 Complete Guides](docs/)** - Comprehensive documentation
- **[🔧 Troubleshooting](docs/)** - Problem resolution guides
- **[📋 Command Reference](docs/cpc_commands_reference.md)** - Complete command documentation

### 🆘 Getting Help

1. **Check Documentation**: Review the extensive docs in the `docs/` directory
2. **Search Issues**: Look for similar problems in existing issues
3. **Create Issue**: Open a new issue with detailed information
4. **Community**: Join discussions and share solutions

---

**🎉 Happy Clustering!** Deploy your Kubernetes clusters with confidence using CPC.

---

*Last updated: September 2025 | CPC v2.0 | Kubernetes 1.31+ Support*
