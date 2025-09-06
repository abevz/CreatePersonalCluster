# CPC Multi-Cloud Support Implementation Plan

## 🔧 CLI Updates for Multi-Provider Support

### New Commands Structure

```bash
# Provider management
./cpc provider list                      # List available providers
./cpc provider select <provider>         # Select default provider  
./cpc provider config <provider>         # Configure provider credentials

# Context with provider support
./cpc ctx <workspace>                    # Current behavior (defaults to proxmox)
./cpc ctx <workspace> --provider <type>  # New: specify provider
./cpc ctx list --provider <type>         # List workspaces for specific provider

# Multi-provider deployment  
./cpc deploy plan --provider aws         # Deploy to specific provider
./cpc deploy apply --provider aws        # Apply with provider override
./cpc deploy status --all-providers      # Show status across all providers

# Cloud-specific operations
./cpc aws create-keypair                 # AWS-specific commands
./cpc azure create-resource-group        # Azure-specific commands  
./cpc gcp create-project                 # GCP-specific commands
```

### Configuration Structure

```bash
# Provider-specific environment files
envs/
├── proxmox/
│   ├── debian.env
│   ├── ubuntu.env
│   └── rocky.env
├── aws/
│   ├── ubuntu.env
│   ├── amazonlinux.env
│   └── rhel.env
├── azure/
│   ├── ubuntu.env
│   └── rhel.env
└── gcp/
    ├── ubuntu.env
    └── cos.env

# Provider credentials (SOPS encrypted)
terraform/secrets/
├── proxmox.sops.yaml
├── aws.sops.yaml  
├── azure.sops.yaml
└── gcp.sops.yaml
```

### Module Updates Required

#### 1. Core Module (modules/10_core.sh)
- Add provider detection and validation
- Implement provider-specific configuration loading
- Add provider context management

#### 2. Terraform Module (modules/20_tofu.sh)  
- Add provider-specific terraform directory handling
- Implement provider module selection logic
- Add provider-specific variable file management

#### 3. New Provider Module (modules/15_providers.sh)
- Provider discovery and validation
- Provider-specific credential management
- Cloud CLI tool integration (aws cli, azure cli, gcloud)

### Implementation Steps

#### Phase 1: Core Infrastructure (Week 1-2)
1. **Provider Abstraction Layer**
   ```bash
   # New function in modules/10_core.sh
   function core_get_current_provider() {
       local workspace="${1:-$(core_get_current_workspace)}"
       local provider_file="$REPO_PATH/workspaces/$workspace/.provider"
       
       if [[ -f "$provider_file" ]]; then
           cat "$provider_file"
       else
           echo "proxmox"  # Default fallback
       fi
   }
   
   function core_set_provider() {
       local workspace="${1:-$(core_get_current_workspace)}"
       local provider="$2"
       local workspace_dir="$REPO_PATH/workspaces/$workspace"
       
       [[ ! -d "$workspace_dir" ]] && mkdir -p "$workspace_dir"
       echo "$provider" > "$workspace_dir/.provider"
   }
   ```

2. **Provider Configuration Management**
   ```bash
   # Provider-specific configuration loading
   function core_load_provider_config() {
       local provider="$1"
       local workspace="$2"
       
       # Load provider-specific environment
       local provider_env="$REPO_PATH/envs/$provider/$workspace.env"
       [[ -f "$provider_env" ]] && source "$provider_env"
       
       # Load provider credentials
       local provider_secrets="$REPO_PATH/terraform/secrets/$provider.sops.yaml"
       if [[ -f "$provider_secrets" ]]; then
           eval "$(sops -d "$provider_secrets" | yq -r 'to_entries | .[] | "\(.key)=\(.value)"')"
           export $(sops -d "$provider_secrets" | yq -r 'keys[]')
       fi
   }
   ```

#### Phase 2: Provider Module (Week 2-3)
1. **Provider Discovery**
   ```bash
   # modules/15_providers.sh
   #!/usr/bin/env bash
   
   # Provider registry
   declare -A SUPPORTED_PROVIDERS=(
       ["proxmox"]="Proxmox Virtual Environment"
       ["aws"]="Amazon Web Services"
       ["azure"]="Microsoft Azure"
       ["gcp"]="Google Cloud Platform"
       ["digitalocean"]="DigitalOcean"
       ["linode"]="Linode"
   )
   
   function providers_list() {
       echo "Supported cloud providers:"
       for provider in "${!SUPPORTED_PROVIDERS[@]}"; do
           local status="❌"
           providers_check_prerequisites "$provider" &>/dev/null && status="✅"
           printf "  %s %-12s - %s\n" "$status" "$provider" "${SUPPORTED_PROVIDERS[$provider]}"
       done
   }
   
   function providers_check_prerequisites() {
       local provider="$1"
       
       case "$provider" in
           proxmox)
               command -v tofu >/dev/null && [[ -f "$REPO_PATH/terraform/secrets/proxmox.sops.yaml" ]]
               ;;
           aws)
               command -v aws >/dev/null && [[ -f "$REPO_PATH/terraform/secrets/aws.sops.yaml" ]]
               ;;
           azure)
               command -v az >/dev/null && [[ -f "$REPO_PATH/terraform/secrets/azure.sops.yaml" ]]
               ;;
           gcp)
               command -v gcloud >/dev/null && [[ -f "$REPO_PATH/terraform/secrets/gcp.sops.yaml" ]]
               ;;
           *)
               return 1
               ;;
       esac
   }
   ```

2. **Provider-Specific Operations**
   ```bash
   function providers_setup() {
       local provider="$1"
       
       case "$provider" in
           aws)
               providers_setup_aws
               ;;
           azure)  
               providers_setup_azure
               ;;
           gcp)
               providers_setup_gcp
               ;;
           *)
               log_error "Setup not implemented for provider: $provider"
               return 1
               ;;
       esac
   }
   
   function providers_setup_aws() {
       log_info "Setting up AWS provider..."
       
       # Check AWS CLI
       if ! command -v aws >/dev/null; then
           log_error "AWS CLI not found. Please install: https://aws.amazon.com/cli/"
           return 1
       fi
       
       # Validate credentials
       if ! aws sts get-caller-identity >/dev/null 2>&1; then
           log_error "AWS credentials not configured. Run 'aws configure'"
           return 1
       fi
       
       # Create key pair if doesn't exist
       local key_name="cpc-$(whoami)-$(date +%Y%m%d)"
       if ! aws ec2 describe-key-pairs --key-names "$key_name" >/dev/null 2>&1; then
           log_info "Creating AWS key pair: $key_name"
           aws ec2 create-key-pair \
               --key-name "$key_name" \
               --query 'KeyMaterial' \
               --output text > "$HOME/.ssh/cpc-aws-key.pem"
           chmod 600 "$HOME/.ssh/cpc-aws-key.pem"
       fi
       
       log_success "AWS provider setup completed"
   }
   ```

#### Phase 3: Terraform Integration (Week 3-4)
1. **Provider Module Selection**
   ```bash
   # modules/20_tofu.sh updates
   function tofu_get_provider_module_path() {
       local provider="$1"
       local terraform_dir="$REPO_PATH/terraform"
       
       if [[ -d "$terraform_dir/providers/$provider" ]]; then
           echo "$terraform_dir/providers/$provider"
       else
           log_error "Provider module not found: $provider"
           return 1
       fi
   }
   
   function tofu_deploy() {
       local action="$1"
       local provider="$(core_get_current_provider)"
       local workspace="$(core_get_current_workspace)"
       
       # Load provider-specific configuration
       core_load_provider_config "$provider" "$workspace"
       
       # Get provider module path
       local provider_module="$(tofu_get_provider_module_path "$provider")"
       [[ $? -ne 0 ]] && return 1
       
       # Set terraform directory to provider module
       local old_tf_dir="$TERRAFORM_DIR"
       export TERRAFORM_DIR="$provider_module"
       
       # Execute terraform command
       case "$action" in
           plan|apply|destroy)
               tofu_exec_with_vars "$action" "$@"
               ;;
           *)
               tofu_exec "$action" "$@"
               ;;
       esac
       
       local result=$?
       export TERRAFORM_DIR="$old_tf_dir"
       return $result
   }
   ```

2. **Variable File Management**
   ```bash
   function tofu_get_var_files() {
       local provider="$1"
       local workspace="$2"
       local var_files=()
       
       # Common variables
       [[ -f "$REPO_PATH/terraform/common.tfvars" ]] && var_files+=("-var-file=$REPO_PATH/terraform/common.tfvars")
       
       # Provider-specific variables  
       local provider_vars="$REPO_PATH/terraform/environments/$provider/$workspace.tfvars"
       [[ -f "$provider_vars" ]] && var_files+=("-var-file=$provider_vars")
       
       # Output var files
       printf '%s\n' "${var_files[@]}"
   }
   ```

#### Phase 4: Context Management (Week 4-5)
1. **Enhanced Context Commands**
   ```bash
   # Enhanced cpc ctx command
   function ctx_with_provider() {
       local workspace="$1"
       local provider="$2"
       
       if [[ -z "$workspace" ]]; then
           ctx_show_current_with_provider
           return
       fi
       
       # Validate provider if specified
       if [[ -n "$provider" ]]; then
           if ! providers_check_prerequisites "$provider"; then
               log_error "Provider '$provider' is not available or not configured"
               return 1
           fi
       fi
       
       # Set workspace
       core_set_current_workspace "$workspace"
       
       # Set provider if specified
       if [[ -n "$provider" ]]; then
           core_set_provider "$workspace" "$provider"
           log_info "Set workspace '$workspace' with provider '$provider'"
       else
           log_info "Set workspace '$workspace' (provider: $(core_get_current_provider "$workspace"))"
       fi
   }
   
   function ctx_show_current_with_provider() {
       local current_workspace="$(core_get_current_workspace)"
       local current_provider="$(core_get_current_provider "$current_workspace")"
       
       echo "Current workspace: $current_workspace"
       echo "Current provider:  $current_provider"
       echo ""
       
       echo "Available workspaces:"
       for workspace_dir in "$REPO_PATH/workspaces"/*; do
           [[ ! -d "$workspace_dir" ]] && continue
           
           local ws_name="$(basename "$workspace_dir")"
           local ws_provider="$(core_get_current_provider "$ws_name")"
           local indicator=""
           
           [[ "$ws_name" == "$current_workspace" ]] && indicator="*"
           
           printf "  %s %-12s (provider: %s)\n" "$indicator" "$ws_name" "$ws_provider"
       done
   }
   ```

### Testing Strategy

#### Unit Tests per Provider
```bash
# bashtest/test_providers.sh  
function test_provider_detection() {
    local providers=("proxmox" "aws" "azure" "gcp")
    
    for provider in "${providers[@]}"; do
        if providers_check_prerequisites "$provider"; then
            echo "✅ Provider $provider is available"
        else
            echo "⚠️  Provider $provider prerequisites not met"
        fi
    done
}

function test_provider_switching() {
    # Test provider switching
    ctx_with_provider "test" "aws"
    local result_provider="$(core_get_current_provider "test")"
    
    if [[ "$result_provider" == "aws" ]]; then
        echo "✅ Provider switching works"
    else
        echo "❌ Provider switching failed"
        return 1
    fi
}
```

### Documentation Updates

#### New Documentation Files
1. **Multi-Cloud Architecture Guide** (`docs/multi_cloud_guide.md`)
2. **Provider Setup Guides** (`docs/providers/`)
   - `aws_setup.md`
   - `azure_setup.md` 
   - `gcp_setup.md`
3. **Migration Guide** (`docs/migration_guide.md`)
4. **Cost Comparison** (`docs/cost_analysis.md`)

### Migration Path for Existing Users

#### Backward Compatibility
```bash
# Automatic migration for existing workspaces
function migrate_existing_workspaces() {
    log_info "Migrating existing workspaces to multi-provider format..."
    
    for workspace in debian ubuntu rocky suse; do
        local workspace_dir="$REPO_PATH/workspaces/$workspace"
        
        if [[ ! -d "$workspace_dir" ]]; then
            mkdir -p "$workspace_dir"
            echo "proxmox" > "$workspace_dir/.provider"
            log_info "Migrated workspace '$workspace' to Proxmox provider"
        fi
    done
}

# Run migration on first multi-provider command
function ensure_migration() {
    local migration_marker="$REPO_PATH/.multi_provider_migration_complete"
    
    if [[ ! -f "$migration_marker" ]]; then
        migrate_existing_workspaces
        touch "$migration_marker"
    fi
}
```

This implementation plan provides a comprehensive roadmap for adding multi-cloud support while maintaining backward compatibility with existing Proxmox deployments.
