#!/bin/bash
# =============================================================================
# CPC Core Module (00_core.sh)
# =============================================================================
# Core functionality: context management, secrets, workspaces

# --- Core Functions ---

# Get repository path
get_repo_path() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Go up from modules/ to main directory
    dirname "$script_dir"
}

# Load secrets from SOPS
load_secrets() {
    local secrets_file="$REPO_PATH/secrets.sops.yaml"
    
    if [ ! -f "$secrets_file" ]; then
        log_warning "Secrets file not found: $secrets_file"
        return 1
    fi
    
    log_debug "Loading secrets from: $secrets_file"
    
    if ! command -v sops >/dev/null 2>&1; then
        log_fatal "SOPS not found. Please install SOPS to decrypt secrets."
    fi
    
    # Extract specific secrets we need
    export PROXMOX_HOST=$(sops -d --extract '["proxmox_host"]' "$secrets_file" 2>/dev/null || echo "")
    export VM_USERNAME=$(sops -d --extract '["vm_username"]' "$secrets_file" 2>/dev/null || echo "")
    export VM_SSH_KEYS=$(sops -d --extract '["vm_ssh_keys"]' "$secrets_file" 2>/dev/null || echo "")
    export VM_PASSWORD=$(sops -d --extract '["vm_password"]' "$secrets_file" 2>/dev/null || echo "")
    
    # AWS/MinIO credentials for Terraform backend
    export AWS_ACCESS_KEY_ID=$(sops -d --extract '["aws_access_key_id"]' "$secrets_file" 2>/dev/null || echo "")
    export AWS_SECRET_ACCESS_KEY=$(sops -d --extract '["aws_secret_access_key"]' "$secrets_file" 2>/dev/null || echo "")
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    
    if [ -n "$PROXMOX_HOST" ] && [ -n "$VM_USERNAME" ]; then
        log_success "Successfully loaded secrets (PROXMOX_HOST: $PROXMOX_HOST, VM_USERNAME: $VM_USERNAME)"
    else
        log_error "Failed to load required secrets from $secrets_file"
        return 1
    fi
}

# Load environment variables
load_env_vars() {
    local repo_root
    repo_root=$(get_repo_path)
    
    # Load secrets first
    load_secrets
    
    if [ -f "$repo_root/$CPC_ENV_FILE" ]; then
        set -a # Automatically export all variables
        source "$repo_root/$CPC_ENV_FILE"
        set +a # Stop automatically exporting
        log_info "Loaded environment variables from $CPC_ENV_FILE"
        
        # Export static IP configuration variables to Terraform
        [ -n "${NETWORK_CIDR:-}" ] && export TF_VAR_network_cidr="$NETWORK_CIDR"
        [ -n "${STATIC_IP_START:-}" ] && export TF_VAR_static_ip_start="$STATIC_IP_START"
        [ -n "${WORKSPACE_IP_BLOCK_SIZE:-}" ] && export TF_VAR_workspace_ip_block_size="$WORKSPACE_IP_BLOCK_SIZE"
        [ -n "${STATIC_IP_BASE:-}" ] && export TF_VAR_static_ip_base="$STATIC_IP_BASE"
        [ -n "${STATIC_IP_GATEWAY:-}" ] && export TF_VAR_static_ip_gateway="$STATIC_IP_GATEWAY"
        
        # Set workspace-specific template variables based on current context
        if [ -f "$CLUSTER_CONTEXT_FILE" ]; then
            local current_workspace
            current_workspace=$(cat "$CLUSTER_CONTEXT_FILE")
            set_workspace_template_vars "$current_workspace"
        fi
    else
        log_warning "Environment file not found: $repo_root/$CPC_ENV_FILE"
    fi
}

# Set workspace-specific template variables
set_workspace_template_vars() {
    local workspace="$1"
    
    if [ -z "$workspace" ]; then
        log_debug "No workspace specified for template variables"
        return
    fi
    
    local env_file="$REPO_PATH/envs/$workspace.env"
    
    if [ ! -f "$env_file" ]; then
        log_warning "Workspace environment file not found: $env_file"
        return
    fi
    
    log_debug "Loading template variables for workspace: $workspace"
    
    # Extract and export template variables
    local template_vm_id template_vm_name image_name kubernetes_version
    local calico_version metallb_version coredns_version etcd_version
    
    template_vm_id=$(grep -E "^TEMPLATE_VM_ID=" "$env_file" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
    template_vm_name=$(grep -E "^TEMPLATE_VM_NAME=" "$env_file" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
    image_name=$(grep -E "^IMAGE_NAME=" "$env_file" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
    kubernetes_version=$(grep -E "^KUBERNETES_VERSION=" "$env_file" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
    calico_version=$(grep -E "^CALICO_VERSION=" "$env_file" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
    metallb_version=$(grep -E "^METALLB_VERSION=" "$env_file" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
    coredns_version=$(grep -E "^COREDNS_VERSION=" "$env_file" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
    etcd_version=$(grep -E "^ETCD_VERSION=" "$env_file" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
    
    # Export template variables
    [ -n "$template_vm_id" ] && export TEMPLATE_VM_ID="$template_vm_id"
    [ -n "$template_vm_name" ] && export TEMPLATE_VM_NAME="$template_vm_name"
    [ -n "$image_name" ] && export IMAGE_NAME="$image_name"
    [ -n "$kubernetes_version" ] && export KUBERNETES_VERSION="$kubernetes_version"
    [ -n "$calico_version" ] && export CALICO_VERSION="$calico_version"
    [ -n "$metallb_version" ] && export METALLB_VERSION="$metallb_version"
    [ -n "$coredns_version" ] && export COREDNS_VERSION="$coredns_version"
    [ -n "$etcd_version" ] && export ETCD_VERSION="$etcd_version"
    
    log_success "Set template variables for workspace '$workspace':"
    log_info "  TEMPLATE_VM_ID: $template_vm_id"
    log_info "  TEMPLATE_VM_NAME: $template_vm_name"
    log_info "  IMAGE_NAME: $image_name"
    log_info "  KUBERNETES_VERSION: $kubernetes_version"
    log_info "  CALICO_VERSION: $calico_version"
    log_info "  METALLB_VERSION: $metallb_version"
    log_info "  COREDNS_VERSION: $coredns_version"
    log_info "  ETCD_VERSION: $etcd_version"
}

# Get current cluster context
get_current_cluster_context() {
    if [ -f "$CLUSTER_CONTEXT_FILE" ]; then
        cat "$CLUSTER_CONTEXT_FILE"
    else
        echo "default"
    fi
}

# Set cluster context
set_cluster_context() {
    local context="$1"
    
    if [ -z "$context" ]; then
        log_error "Usage: set_cluster_context <context_name>"
        return 1
    fi
    
    echo "$context" > "$CLUSTER_CONTEXT_FILE"
    log_success "Cluster context set to: $context"
}

# Validate workspace name
validate_workspace_name() {
    local workspace="$1"
    
    if [[ ! "$workspace" =~ $WORKSPACE_NAME_PATTERN ]]; then
        log_error "Invalid workspace name: $workspace"
        log_info "Workspace names must:"
        log_info "  - Start and end with alphanumeric characters"
        log_info "  - Contain only letters, numbers, and hyphens"
        log_info "  - Be between 3-30 characters long"
        return 1
    fi
    
    return 0
}

# Main context command
cpc_ctx() {
    local context="$1"
    
    if [ -z "$context" ]; then
        local current_context
        current_context=$(get_current_cluster_context)
        log_info "Current cluster context: $current_context"
        return 0
    fi
    
    # Validate workspace name
    if ! validate_workspace_name "$context"; then
        return 1
    fi
    
    # Check if workspace environment exists
    local env_file="$REPO_PATH/envs/$context.env"
    if [ ! -f "$env_file" ]; then
        log_error "Workspace environment file not found: $env_file"
        log_info "Available workspaces:"
        ls -1 "$REPO_PATH/envs/"*.env 2>/dev/null | sed 's|.*/||; s|\.env$||' | sed 's/^/  /'
        return 1
    fi
    
    # Load environment and set context
    load_env_vars
    set_cluster_context "$context"
    
    # Switch Terraform workspace
    local tf_dir="$REPO_PATH/terraform"
    if [ -d "$tf_dir" ]; then
        pushd "$tf_dir" >/dev/null || return 1
        if tofu workspace select "$context" 2>/dev/null; then
            log_success "Switched to workspace \"$context\"!"
        else
            log_warning "Terraform workspace '$context' does not exist. Creating it..."
            tofu workspace new "$context"
            log_success "Created and switched to workspace \"$context\"!"
        fi
        popd >/dev/null || return 1
    fi
    
    # Set template variables for the new context
    set_workspace_template_vars "$context"
}

# Setup CPC project
cpc_setup() {
    log_header "Setting up CPC project"
    
    local script_path
    script_path="$(realpath "${BASH_SOURCE[0]}")"
    
    # Get the directory containing the cpc script (going up from modules/)
    REPO_PATH="$(dirname "$(dirname "$script_path")")"
    export REPO_PATH
    
    log_info "Repository path: $REPO_PATH"
    
    # Validate project structure
    local required_dirs=("terraform" "envs" "ansible" "scripts")
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$REPO_PATH/$dir" ]; then
            log_error "Required directory not found: $REPO_PATH/$dir"
            return 1
        fi
    done
    
    # Initialize environment
    load_env_vars
    
    log_success "CPC setup completed successfully"
}

# Export core functions
export -f get_repo_path load_secrets load_env_vars set_workspace_template_vars
export -f get_current_cluster_context set_cluster_context validate_workspace_name
export -f cpc_ctx cpc_setup
