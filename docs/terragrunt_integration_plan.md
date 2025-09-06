# Terragrunt Integration Plan for Multi-Cloud CPC

## 🎯 Why Terragrunt for Multi-Cloud CPC?

### Current Problems with Pure Terraform
1. **Code Duplication**: Similar configurations across providers
2. **Variable Management**: Complex tfvars files per provider/environment
3. **Backend Configuration**: Repeated backend blocks
4. **Dependencies**: Manual management of resource dependencies
5. **State Management**: Complex workspace organization

### Terragrunt Benefits for CPC
1. **DRY Principle**: Shared configurations across providers
2. **Hierarchical Configuration**: Environment → Provider → Region structure
3. **Automatic Backend**: Generated backend configurations
4. **Dependency Management**: Automatic resource dependencies
5. **Hook System**: Pre/post deployment actions
6. **Variable Inheritance**: Cascading variable definitions

## 🏗️ Terragrunt Architecture for CPC

### Directory Structure with Terragrunt
```
CreatePersonalCluster/
├── terragrunt/                           # New Terragrunt root
│   ├── terragrunt.hcl                   # Root Terragrunt config
│   ├── environments/                    # Environment-specific configs
│   │   ├── dev/
│   │   │   ├── terragrunt.hcl          # Dev environment config
│   │   │   ├── proxmox/
│   │   │   │   ├── terragrunt.hcl      # Proxmox provider config
│   │   │   │   ├── ubuntu/
│   │   │   │   │   └── terragrunt.hcl  # Ubuntu on Proxmox
│   │   │   │   ├── debian/
│   │   │   │   │   └── terragrunt.hcl  # Debian on Proxmox
│   │   │   │   └── rocky/
│   │   │   │       └── terragrunt.hcl  # Rocky on Proxmox
│   │   │   ├── aws/
│   │   │   │   ├── terragrunt.hcl      # AWS provider config
│   │   │   │   ├── us-east-1/
│   │   │   │   │   ├── terragrunt.hcl  # Region config
│   │   │   │   │   ├── ubuntu/
│   │   │   │   │   │   └── terragrunt.hcl
│   │   │   │   │   ├── amazonlinux/
│   │   │   │   │   │   └── terragrunt.hcl
│   │   │   │   │   └── rhel/
│   │   │   │   │       └── terragrunt.hcl
│   │   │   │   └── us-west-2/
│   │   │   │       └── ...
│   │   │   ├── azure/
│   │   │   │   ├── terragrunt.hcl
│   │   │   │   ├── eastus/
│   │   │   │   │   ├── terragrunt.hcl
│   │   │   │   │   ├── ubuntu/
│   │   │   │   │   │   └── terragrunt.hcl
│   │   │   │   │   └── rhel/
│   │   │   │   │       └── terragrunt.hcl
│   │   │   │   └── westus2/
│   │   │   │       └── ...
│   │   │   ├── gcp/
│   │   │   │   ├── terragrunt.hcl
│   │   │   │   ├── us-central1/
│   │   │   │   │   ├── terragrunt.hcl
│   │   │   │   │   ├── ubuntu/
│   │   │   │   │   │   └── terragrunt.hcl
│   │   │   │   │   └── cos/
│   │   │   │   │       └── terragrunt.hcl
│   │   │   │   └── europe-west1/
│   │   │   │       └── ...
│   │   │   ├── digitalocean/
│   │   │   │   ├── terragrunt.hcl
│   │   │   │   ├── nyc1/
│   │   │   │   │   ├── terragrunt.hcl
│   │   │   │   │   ├── ubuntu/
│   │   │   │   │   │   └── terragrunt.hcl
│   │   │   │   │   └── debian/
│   │   │   │   │       └── terragrunt.hcl
│   │   │   │   └── sfo3/
│   │   │   │       └── ...
│   │   │   └── linode/
│   │   │       ├── terragrunt.hcl
│   │   │       ├── us-east/
│   │   │       │   ├── terragrunt.hcl
│   │   │       │   ├── ubuntu/
│   │   │       │   │   └── terragrunt.hcl
│   │   │       │   └── debian/
│   │   │       │       └── terragrunt.hcl
│   │   │       └── eu-west/
│   │   │           └── ...
│   │   ├── staging/
│   │   │   ├── terragrunt.hcl
│   │   │   └── [similar structure]
│   │   └── prod/
│   │       ├── terragrunt.hcl
│   │       └── [similar structure]
│   ├── _common/                         # Shared configurations
│   │   ├── cluster.hcl                  # Common cluster config
│   │   ├── networking.hcl               # Common networking config
│   │   ├── security.hcl                 # Common security config
│   │   └── monitoring.hcl               # Common monitoring config
│   └── _modules/                        # Local Terraform modules
│       ├── cluster-base/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── provider-configs/
│           ├── aws/
│           ├── azure/
│           ├── gcp/
│           ├── digitalocean/
│           ├── linode/
│           └── proxmox/
├── terraform/                           # Legacy structure (maintained for compatibility)
│   └── [existing files - gradually migrated]
└── modules/
    ├── 60_tofu.sh                      # Updated for Terragrunt support
    └── 65_terragrunt.sh                # New Terragrunt module
```

## 📝 Terragrunt Configuration Examples

### Root Terragrunt Configuration
```hcl
# terragrunt/terragrunt.hcl
locals {
  # Common variables across all environments
  common_vars = {
    project_name = "cpc"
    organization = "abevz"
  }
  
  # Parse path to extract environment, provider, region, and OS
  path_parts = split("/", path_relative_to_include())
  environment = length(local.path_parts) > 1 ? local.path_parts[1] : "dev"
  provider = length(local.path_parts) > 2 ? local.path_parts[2] : "proxmox"
  region = length(local.path_parts) > 3 ? local.path_parts[3] : "default"
  os_type = length(local.path_parts) > 4 ? local.path_parts[4] : "ubuntu"
}

# Generate backend configuration dynamically
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
terraform {
  backend "s3" {
    bucket = "cpc-terraform-state-${local.common_vars.organization}"
    key    = "${local.environment}/${local.provider}/${local.region}/${local.os_type}/terraform.tfstate"
    region = "us-east-1"
    
    # State locking
    dynamodb_table = "cpc-terraform-locks"
    encrypt        = true
  }
}
EOF
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents = templatefile("${get_parent_terragrunt_dir()}/_common/providers/${local.provider}.hcl", {
    environment = local.environment
    region      = local.region
  })
}

# Common inputs for all configurations
inputs = merge(
  local.common_vars,
  {
    environment = local.environment
    provider_type = local.provider
    region = local.region
    os_type = local.os_type
    
    # Common tags
    common_tags = {
      Environment = local.environment
      Provider    = local.provider
      Region      = local.region
      OS          = local.os_type
      ManagedBy   = "terragrunt"
      Project     = local.common_vars.project_name
    }
  }
)

# Remote state configuration for dependencies
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket = "cpc-terraform-state-${local.common_vars.organization}"
    key = "${local.environment}/${local.provider}/${local.region}/${local.os_type}/terraform.tfstate"
    region = "us-east-1"
    
    dynamodb_table = "cpc-terraform-locks"
    encrypt        = true
  }
}
```

### Environment Configuration
```hcl
# terragrunt/environments/dev/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

locals {
  environment_vars = {
    cluster_size = "small"
    enable_monitoring = false
    enable_backups = false
    auto_scaling = false
    
    # Development-specific settings
    control_plane_count = 1
    worker_count = 2
    instance_size = "small"
  }
}

inputs = merge(
  local.environment_vars,
  {
    # Development-specific overrides
    environment = "dev"
    
    # Cost optimization for dev
    enable_spot_instances = true
    max_spot_price = "0.05"
  }
)
```

### Provider Configuration
```hcl
# terragrunt/environments/dev/aws/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

include "environment" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  aws_vars = {
    # AWS-specific configurations
    vpc_cidr = "10.0.0.0/16"
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
    enable_flow_logs = false
    
    # Instance type mapping
    instance_types = {
      small = {
        control_plane = "t3.medium"
        worker = "t3.small"
      }
      medium = {
        control_plane = "t3.large"
        worker = "t3.medium"
      }
      large = {
        control_plane = "m5.large"
        worker = "m5.large"
      }
    }
  }
}

inputs = merge(
  local.aws_vars,
  {
    provider_type = "aws"
    
    # AWS-specific settings
    enable_cloudwatch = true
    enable_iam_roles = true
    
    # Select instance types based on environment size
    control_plane_instance_type = local.aws_vars.instance_types["small"]["control_plane"]
    worker_instance_type = local.aws_vars.instance_types["small"]["worker"]
  }
)

# Dependencies
dependencies {
  paths = ["../vpc", "../security-groups"]
}
```

### Region Configuration
```hcl
# terragrunt/environments/dev/aws/us-east-1/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

include "provider" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  region_vars = {
    aws_region = "us-east-1"
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
    
    # Region-specific settings
    enable_multi_az = true
    preferred_az = "us-east-1a"
  }
}

inputs = merge(
  local.region_vars,
  {
    region = "us-east-1"
  }
)
```

### OS-Specific Configuration
```hcl
# terragrunt/environments/dev/aws/us-east-1/ubuntu/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

include "region" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${get_parent_terragrunt_dir()}/_modules/aws-cluster"
}

locals {
  ubuntu_vars = {
    os_family = "ubuntu"
    os_version = "22.04"
    
    # Ubuntu-specific settings
    ssh_user = "ubuntu"
    package_manager = "apt"
    
    # AMI filter
    ami_filter = {
      name = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      owners = ["099720109477"] # Canonical
    }
  }
}

inputs = merge(
  local.ubuntu_vars,
  {
    os_type = "ubuntu"
    
    # Cluster configuration
    cluster_name = "cpc-dev-aws-ubuntu"
    
    # Kubernetes version for Ubuntu
    kubernetes_version = "1.31.9"
    containerd_version = "1.7.27"
    
    # Ubuntu-specific packages
    additional_packages = [
      "ubuntu-advantage-tools",
      "landscape-common"
    ]
  }
)

# Hooks for pre/post actions
terraform {
  before_hook "validate_ubuntu" {
    commands = ["plan", "apply"]
    execute = ["bash", "-c", "echo 'Validating Ubuntu configuration...'"]
  }
  
  after_hook "setup_ubuntu" {
    commands = ["apply"]
    execute = ["bash", "-c", "${get_parent_terragrunt_dir()}/../scripts/post-deploy-ubuntu.sh"]
  }
}
```

## 🔧 Enhanced CPC CLI for Terragrunt

### New Terragrunt Module
```bash
# modules/65_terragrunt.sh
#!/bin/bash
# modules/65_terragrunt.sh - Terragrunt management module

function cpc_terragrunt() {
  local command="$1"
  shift

  case "$command" in
    plan)
      terragrunt_plan "$@"
      ;;
    apply)
      terragrunt_apply "$@"
      ;;
    destroy)
      terragrunt_destroy "$@"
      ;;
    plan-all)
      terragrunt_plan_all "$@"
      ;;
    apply-all)
      terragrunt_apply_all "$@"
      ;;
    destroy-all)
      terragrunt_destroy_all "$@"
      ;;
    run-all)
      terragrunt_run_all "$@"
      ;;
    graph)
      terragrunt_graph "$@"
      ;;
    validate-all)
      terragrunt_validate_all "$@"
      ;;
    output-all)
      terragrunt_output_all "$@"
      ;;
    *)
      echo "Unknown terragrunt command: $command"
      terragrunt_help
      return 1
      ;;
  esac
}

function terragrunt_plan() {
  local environment="${1:-dev}"
  local provider="${2:-proxmox}"
  local region="${3:-default}"
  local os_type="${4:-ubuntu}"
  
  local tg_dir="$REPO_PATH/terragrunt/environments/$environment/$provider"
  [[ "$provider" != "proxmox" ]] && tg_dir="$tg_dir/$region"
  tg_dir="$tg_dir/$os_type"
  
  if [[ ! -d "$tg_dir" ]]; then
    log_error "Terragrunt configuration not found: $tg_dir"
    return 1
  fi
  
  log_info "Planning deployment for $environment/$provider/$region/$os_type"
  
  pushd "$tg_dir" >/dev/null || return 1
  terragrunt plan "$@"
  local result=$?
  popd >/dev/null || return 1
  
  return $result
}

function terragrunt_apply() {
  local environment="${1:-dev}"
  local provider="${2:-proxmox}"
  local region="${3:-default}"
  local os_type="${4:-ubuntu}"
  
  local tg_dir="$REPO_PATH/terragrunt/environments/$environment/$provider"
  [[ "$provider" != "proxmox" ]] && tg_dir="$tg_dir/$region"
  tg_dir="$tg_dir/$os_type"
  
  if [[ ! -d "$tg_dir" ]]; then
    log_error "Terragrunt configuration not found: $tg_dir"
    return 1
  fi
  
  log_info "Applying deployment for $environment/$provider/$region/$os_type"
  
  pushd "$tg_dir" >/dev/null || return 1
  terragrunt apply "$@"
  local result=$?
  popd >/dev/null || return 1
  
  return $result
}

function terragrunt_plan_all() {
  local environment="${1:-dev}"
  local provider="$2"
  
  local tg_dir="$REPO_PATH/terragrunt/environments/$environment"
  [[ -n "$provider" ]] && tg_dir="$tg_dir/$provider"
  
  if [[ ! -d "$tg_dir" ]]; then
    log_error "Terragrunt environment not found: $tg_dir"
    return 1
  fi
  
  log_info "Planning all deployments for $environment$([ -n "$provider" ] && echo "/$provider")"
  
  pushd "$tg_dir" >/dev/null || return 1
  terragrunt plan-all --terragrunt-non-interactive
  local result=$?
  popd >/dev/null || return 1
  
  return $result
}

function terragrunt_apply_all() {
  local environment="${1:-dev}"
  local provider="$2"
  
  local tg_dir="$REPO_PATH/terragrunt/environments/$environment"
  [[ -n "$provider" ]] && tg_dir="$tg_dir/$provider"
  
  if [[ ! -d "$tg_dir" ]]; then
    log_error "Terragrunt environment not found: $tg_dir"
    return 1
  fi
  
  log_info "Applying all deployments for $environment$([ -n "$provider" ] && echo "/$provider")"
  
  pushd "$tg_dir" >/dev/null || return 1
  terragrunt apply-all --terragrunt-non-interactive
  local result=$?
  popd >/dev/null || return 1
  
  return $result
}

function terragrunt_graph() {
  local environment="${1:-dev}"
  
  local tg_dir="$REPO_PATH/terragrunt/environments/$environment"
  
  if [[ ! -d "$tg_dir" ]]; then
    log_error "Terragrunt environment not found: $tg_dir"
    return 1
  fi
  
  log_info "Generating dependency graph for $environment"
  
  pushd "$tg_dir" >/dev/null || return 1
  terragrunt graph-dependencies | dot -Tpng > "$REPO_PATH/terragrunt-dependency-graph-$environment.png"
  local result=$?
  popd >/dev/null || return 1
  
  if [[ $result -eq 0 ]]; then
    log_success "Dependency graph saved to terragrunt-dependency-graph-$environment.png"
  fi
  
  return $result
}
```

### Updated CPC Commands with Terragrunt
```bash
# Enhanced commands in main cpc script

# New multi-provider deployment commands
./cpc tg plan dev aws us-east-1 ubuntu          # Plan specific deployment
./cpc tg apply dev aws us-east-1 ubuntu         # Apply specific deployment
./cpc tg plan-all dev aws                       # Plan all AWS deployments in dev
./cpc tg apply-all dev                          # Apply all dev environment

# Provider comparison
./cpc tg compare-providers dev ubuntu           # Compare costs across providers
./cpc tg compare-regions dev aws ubuntu         # Compare regions for AWS

# Multi-environment operations
./cpc tg promote staging prod aws               # Promote staging config to prod
./cpc tg drift-detect dev                       # Detect configuration drift

# Advanced operations
./cpc tg graph dev                              # Generate dependency graph
./cpc tg validate-all dev                       # Validate all configurations
./cpc tg plan-all --parallel                    # Parallel planning
```

## 🚀 Migration Strategy

### Phase 1: Gradual Migration (Week 1-2)
1. **Setup Terragrunt Structure**: Create directory hierarchy
2. **Convert Proxmox First**: Migrate existing Proxmox configs
3. **Test Compatibility**: Ensure existing workflows work
4. **Documentation**: Update guides for Terragrunt usage

### Phase 2: Provider Migration (Week 3-4)
1. **AWS Migration**: Convert AWS modules to Terragrunt
2. **Azure/GCP Migration**: Convert remaining cloud providers
3. **Validation**: Test all provider configurations
4. **Performance Testing**: Compare Terragrunt vs pure Terraform

### Phase 3: Advanced Features (Week 5-6)
1. **Dependencies**: Implement cross-resource dependencies
2. **Hooks**: Add pre/post deployment automation
3. **Multi-Environment**: Setup staging/prod environments
4. **Advanced CLI**: Enhanced terragrunt commands

## 📊 Benefits of Terragrunt Integration

### Code Reduction
- **Before**: ~2000 lines of duplicated Terraform code
- **After**: ~500 lines of shared modules + configuration
- **Reduction**: 75% less code to maintain

### Deployment Speed
- **Parallel Execution**: Deploy multiple environments simultaneously
- **Dependency Management**: Automatic ordering of resources
- **Caching**: Shared module caching across environments

### Operational Benefits
- **Consistency**: Same configuration patterns across providers
- **Scalability**: Easy addition of new regions/environments
- **Maintainability**: Centralized configuration management
- **Testing**: Environment-specific testing strategies

## 🎯 Enhanced Architecture with Terragrunt

```
CPC v2.0 with Terragrunt
├── Traditional Mode (Backward Compatible)
│   └── ./cpc deploy apply (uses existing terraform/)
├── Terragrunt Mode (New Multi-Cloud)
│   ├── ./cpc tg apply dev aws us-east-1 ubuntu
│   ├── ./cpc tg plan-all dev
│   └── ./cpc tg apply-all staging
└── Hybrid Mode
    ├── Use Terragrunt for new deployments
    └── Maintain Terraform for existing clusters
```

Terragrunt даст нам огромные преимущества для мульти-облачной архитектуры - от устранения дублирования кода до автоматического управления зависимостями. Хотите начать с миграции существующей Proxmox конфигурации на Terragrunt или сразу создать новую AWS конфигурацию?
