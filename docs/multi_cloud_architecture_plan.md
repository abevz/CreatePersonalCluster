# Multi-Cloud Architecture Plan for CPC

## 🏗️ Architecture Overview

### Current State
- **Single Provider**: Proxmox VE only
- **Monolithic Terraform**: All resources in single configuration
- **Fixed Infrastructure**: VM-based deployment model

### Target State
- **Multi-Provider**: AWS, Azure, GCP, DigitalOcean, Linode + Proxmox
- **Modular Terraform**: Provider-specific modules with common interface
- **Flexible Infrastructure**: VMs, containers, managed services

## 📁 Proposed Directory Structure

```
terraform/
├── providers/                    # Provider-specific implementations
│   ├── proxmox/                 # Current implementation (moved)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── aws/                     # AWS EC2 implementation
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── vpc.tf
│   ├── azure/                   # Azure VM implementation
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── network.tf
│   ├── gcp/                     # Google Compute Engine
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── network.tf
│   └── digitalocean/            # DigitalOcean Droplets
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
├── modules/                     # Common modules across providers
│   ├── common/                  # Shared configurations
│   │   ├── variables.tf         # Common variables
│   │   ├── outputs.tf           # Standard outputs
│   │   └── locals.tf            # Common computations
│   ├── kubernetes/              # K8s-specific resources
│   │   ├── cluster-config.tf
│   │   └── node-groups.tf
│   └── security/                # Security groups/firewalls
│       ├── rules.tf
│       └── policies.tf
├── environments/                # Provider + OS combinations
│   ├── proxmox/
│   │   ├── ubuntu.tfvars
│   │   ├── debian.tfvars
│   │   └── rocky.tfvars
│   ├── aws/
│   │   ├── ubuntu.tfvars
│   │   ├── amazon-linux.tfvars
│   │   └── rhel.tfvars
│   ├── azure/
│   │   ├── ubuntu.tfvars
│   │   └── rhel.tfvars
│   └── gcp/
│       ├── ubuntu.tfvars
│       └── cos.tfvars
├── main.tf                      # Provider selector and common resources
├── variables.tf                 # Global variables
├── outputs.tf                   # Standardized outputs
└── providers.tf                 # All provider configurations
```

## 🔄 Provider Interface Standardization

### Common Variables (All Providers)
```hcl
# Global configuration
variable "provider_type" {
  description = "Cloud provider (proxmox, aws, azure, gcp, digitalocean)"
  type        = string
}

variable "region" {
  description = "Provider-specific region/zone"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# Node configuration
variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "node_instance_type" {
  description = "Instance type/size for nodes"
  type        = string
}

variable "node_disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 20
}

# Network configuration
variable "network_cidr" {
  description = "Network CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_public_ip" {
  description = "Enable public IP for nodes"
  type        = bool
  default     = false
}
```

### Standardized Outputs (All Providers)
```hcl
# Required outputs for Ansible inventory
output "control_plane_ips" {
  description = "Control plane node IP addresses"
  value       = local.control_plane_ips
}

output "worker_ips" {
  description = "Worker node IP addresses"  
  value       = local.worker_ips
}

output "control_plane_hostnames" {
  description = "Control plane hostnames"
  value       = local.control_plane_hostnames
}

output "worker_hostnames" {
  description = "Worker hostnames"
  value       = local.worker_hostnames
}

output "ssh_user" {
  description = "SSH user for connecting to nodes"
  value       = local.ssh_user
}

output "ssh_private_key_path" {
  description = "Path to SSH private key"
  value       = var.ssh_private_key_path
}

output "provider_info" {
  description = "Provider-specific metadata"
  value = {
    provider = var.provider_type
    region   = var.region
    vpc_id   = try(local.vpc_id, null)
    subnets  = try(local.subnet_ids, null)
  }
}
```

## 🔧 Implementation Strategy

### Step 1: Refactor Current Proxmox Implementation
1. Move existing `terraform/*.tf` to `terraform/providers/proxmox/`
2. Create common module structure
3. Standardize outputs format
4. Test existing functionality

### Step 2: Create Provider Abstraction Layer
1. Implement `terraform/main.tf` as provider selector
2. Create common variables and outputs
3. Implement provider-specific variable mapping
4. Add provider validation

### Step 3: Implement First Cloud Provider (AWS)
1. Create AWS provider module
2. Implement EC2 instance management
3. Add VPC and security group configuration
4. Test with existing Ansible playbooks

### Step 4: Update CPC CLI
1. Add provider selection to context management
2. Update deploy commands for multi-provider
3. Add provider-specific help and validation
4. Update template management for cloud images

### Step 5: Extend to Other Providers
1. Azure implementation
2. GCP implementation  
3. DigitalOcean implementation
4. Provider-specific optimizations

## 🚀 Provider-Specific Features

### AWS Implementation
- **Instance Types**: t3.medium, t3.large, m5.large, etc.
- **Networking**: VPC, Subnets, Security Groups, NAT Gateway
- **Storage**: EBS volumes with encryption
- **Images**: Ubuntu 24.04, Amazon Linux 2023, RHEL 9
- **Features**: Auto Scaling Groups, Load Balancers, Route53

### Azure Implementation  
- **Instance Types**: Standard_B2s, Standard_D2s_v3, etc.
- **Networking**: Virtual Network, Subnets, NSGs, Load Balancer
- **Storage**: Managed Disks with encryption
- **Images**: Ubuntu 24.04, RHEL 9, Windows Server
- **Features**: Availability Sets, Scale Sets, Azure DNS

### GCP Implementation
- **Instance Types**: e2-medium, n1-standard-2, etc.
- **Networking**: VPC, Subnets, Firewall Rules, Cloud NAT
- **Storage**: Persistent Disks with encryption
- **Images**: Ubuntu 24.04, COS, RHEL 9
- **Features**: Instance Groups, Load Balancing, Cloud DNS

### DigitalOcean Implementation
- **Droplet Types**: s-2vcpu-2gb, s-2vcpu-4gb, etc.
- **Networking**: VPC, Firewall Rules, Load Balancers
- **Storage**: Block Storage volumes
- **Images**: Ubuntu 24.04, Debian 12, CentOS Stream
- **Features**: Managed Kubernetes option

## 🔐 Security Considerations

### Cloud-Specific Security
1. **AWS**: IAM roles, Security Groups, KMS encryption
2. **Azure**: Managed Identity, NSGs, Key Vault encryption
3. **GCP**: Service Accounts, Firewall Rules, KMS encryption
4. **DigitalOcean**: SSH keys, Firewall Rules, Volume encryption

### Common Security Features
- SSH key management across providers
- Network segmentation and firewall rules
- Disk encryption at rest
- Secret management with SOPS
- Instance metadata security

## 📊 Cost Optimization

### Provider Cost Comparison
- **Proxmox**: Fixed infrastructure cost (self-hosted)
- **AWS**: Variable pricing, spot instances available
- **Azure**: Competitive pricing, reserved instances
- **GCP**: Sustained use discounts, preemptible instances
- **DigitalOcean**: Simple pricing, predictable costs

### Cost Control Features
- Instance size recommendations per provider
- Automatic shutdown schedules
- Spot/preemptible instance support
- Resource tagging for cost tracking
- Budget alerts and limits

## 🧪 Testing Strategy

### Multi-Provider Testing
1. **Unit Tests**: Provider module validation
2. **Integration Tests**: End-to-end deployment per provider
3. **Cross-Provider Tests**: Feature parity validation
4. **Performance Tests**: Deployment time comparison
5. **Cost Tests**: Resource cost validation

### Continuous Integration
- Provider-specific test pipelines
- Cost estimation in PR reviews
- Security scanning across providers
- Terraform plan validation
- Ansible playbook compatibility testing

## 📚 Documentation Updates

### New Documentation Needed
1. **Multi-Cloud Architecture Guide**
2. **Provider Selection Guide** 
3. **Cloud-Specific Configuration**
4. **Cost Comparison and Optimization**
5. **Migration Guide** (Proxmox to Cloud)
6. **Troubleshooting** per provider

### Updated Documentation
1. **README.md** - Multi-cloud overview
2. **Installation Guide** - Provider prerequisites  
3. **CPC Commands Reference** - New provider commands
4. **Architecture Documentation** - Multi-provider design
5. **Environment Setup** - Cloud credentials management

## 🎯 Success Metrics

### Technical Metrics
- **Provider Coverage**: 5+ cloud providers supported
- **Feature Parity**: 95% feature compatibility across providers
- **Deployment Time**: <10 minutes for standard cluster
- **Test Coverage**: >80% for all provider modules
- **Documentation**: Complete guides for each provider

### User Experience Metrics
- **Setup Time**: <30 minutes first deployment
- **Learning Curve**: Existing users can use new providers in <1 hour
- **Error Rate**: <5% deployment failures
- **Support Issues**: <10% provider-specific issues

## 🔄 Migration Path

### For Existing Users
1. **No Breaking Changes**: Existing Proxmox deployments continue working
2. **Gradual Adoption**: Can test cloud providers alongside Proxmox
3. **Easy Migration**: Tools to migrate configurations between providers
4. **Rollback Support**: Can revert to Proxmox if needed

### Migration Tools
- Configuration converter between providers
- State migration utilities
- Backup and restore procedures
- Multi-provider deployment support
