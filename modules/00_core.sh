#!/bin/bash
# =============================================================================
# CPC Core Module (00_core.sh)
# =============================================================================
# Core functionality: context management, secrets, workspaces, setup

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

#----------------------------------------------------------------------
# Core CPC Functions
#----------------------------------------------------------------------

# Main entry point for CPC core functionality
cpc_core() {
  case "${1:-}" in
  setup-cpc)
    shift
    core_setup_cpc "$@"
    ;;
  ctx)
    shift
    core_ctx "$@"
    ;;
  clone-workspace)
    shift
    core_clone_workspace "$@"
    ;;
  delete-workspace)
    shift
    core_delete_workspace "$@"
    ;;
  load_secrets)
    shift
    core_load_secrets_command "$@"
    ;;
  clear-cache)
    shift
    core_clear_cache "$@"
    ;;
  list-workspaces)
    shift
    core_list_workspaces "$@"
    ;;
  *)
    log_error "Unknown core command: ${1:-}"
    log_info "Available commands: setup-cpc, ctx, clone-workspace, delete-workspace, load_secrets, clear-cache, list-workspaces"
    return 1
    ;;
  esac
}

# --- Core Functions ---

# Get repository path
get_repo_path() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Go up from modules/ to main directory
  dirname "$script_dir"
}

# Cached secrets loading system
load_secrets_cached() {
  local cache_file="/tmp/cpc_secrets_cache"
  local cache_env_file="/tmp/cpc_env_cache.sh"
  local secrets_file
  local repo_root

  if ! repo_root=$(get_repo_path); then
    error_handle "$ERROR_CONFIG" "Failed to determine repository path" "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  secrets_file="$repo_root/terraform/secrets.sops.yaml"

  # Check if cache exists and is fresh
  if [[ -f "$cache_env_file" && -f "$secrets_file" ]]; then
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_env_file" 2>/dev/null || echo 0)))
    local secrets_age=$(($(date +%s) - $(stat -c %Y "$secrets_file" 2>/dev/null || echo 0)))

    # Use cache if it's newer than secrets file and less than 5 minutes old
    if [[ $cache_age -lt 300 && $cache_age -lt $secrets_age ]]; then
      log_info "Using cached secrets (age: ${cache_age}s)"
      source "$cache_env_file"
      return 0
    fi
  fi

  # Load fresh secrets and cache them
  log_info "Loading fresh secrets..."
  if load_secrets_fresh; then
    # Cache only the secret environment variables
    {
      echo "# CPC Secrets Cache - Generated $(date)"
      echo "export PROXMOX_HOST='$PROXMOX_HOST'"
      echo "export PROXMOX_USERNAME='$PROXMOX_USERNAME'"
      echo "export VM_USERNAME='$VM_USERNAME'"
      echo "export VM_SSH_KEY='$VM_SSH_KEY'"
      [[ -n "${PROXMOX_PASSWORD:-}" ]] && echo "export PROXMOX_PASSWORD='$PROXMOX_PASSWORD'"
      [[ -n "${VM_PASSWORD:-}" ]] && echo "export VM_PASSWORD='$VM_PASSWORD'"
      [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && echo "export AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID'"
      [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] && echo "export AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY'"
      [[ -n "${DOCKER_HUB_USERNAME:-}" ]] && echo "export DOCKER_HUB_USERNAME='$DOCKER_HUB_USERNAME'"
      [[ -n "${DOCKER_HUB_PASSWORD:-}" ]] && echo "export DOCKER_HUB_PASSWORD='$DOCKER_HUB_PASSWORD'"
      [[ -n "${HARBOR_HOSTNAME:-}" ]] && echo "export HARBOR_HOSTNAME='$HARBOR_HOSTNAME'"
      [[ -n "${HARBOR_ROBOT_USERNAME:-}" ]] && echo "export HARBOR_ROBOT_USERNAME='$HARBOR_ROBOT_USERNAME'"
      [[ -n "${HARBOR_ROBOT_TOKEN:-}" ]] && echo "export HARBOR_ROBOT_TOKEN='$HARBOR_ROBOT_TOKEN'"
      [[ -n "${CLOUDFLARE_DNS_API_TOKEN:-}" ]] && echo "export CLOUDFLARE_DNS_API_TOKEN='$CLOUDFLARE_DNS_API_TOKEN'"
      [[ -n "${CLOUDFLARE_EMAIL:-}" ]] && echo "export CLOUDFLARE_EMAIL='$CLOUDFLARE_EMAIL'"
    } >"$cache_env_file"

    chmod 600 "$cache_env_file" # Secure the cache file
    log_debug "Secrets cached successfully"
    return 0
  else
    return 1
  fi
}

# Fresh secrets loading (renamed from load_secrets)
load_secrets_fresh() {
  # Create temporary file for environment variables
  local env_file="/tmp/cpc_env_vars.sh"
  rm -f "$env_file"
  touch "$env_file"

  local repo_root
  if ! repo_root=$(get_repo_path); then
    error_handle "$ERROR_CONFIG" "Failed to determine repository path" "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  local secrets_file="$repo_root/terraform/secrets.sops.yaml"

  if ! error_validate_file "$secrets_file" "secrets.sops.yaml not found at $secrets_file"; then
    return 1
  fi

  # Check if sops is installed
  if ! error_validate_command_exists "sops" "Please install SOPS: https://github.com/mozilla/sops"; then
    return 1
  fi

  # Check if jq is installed
  if ! error_validate_command_exists "jq" "Please install jq: apt install jq or brew install jq"; then
    return 1
  fi

  # Check if yq is installed
  if ! error_validate_command_exists "yq" "Please install yq: https://github.com/mikefarah/yq/#install"; then
    return 1
  fi

  log_debug "Loading secrets from secrets.sops.yaml..."

  # Try to decrypt and validate secrets with error handling
  if ! retry_execute \
    "sops -d '$secrets_file' > /dev/null" \
    2 \
    1 \
    10 \
    "" \
    "Decrypt secrets file"; then
    error_handle "$ERROR_AUTH" "Failed to decrypt secrets.sops.yaml. Check your SOPS configuration and GPG keys." "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  # Export sensitive variables from SOPS with validation
  local required_vars=("PROXMOX_HOST" "PROXMOX_USERNAME" "VM_USERNAME" "VM_SSH_KEY")
  local missing_vars=()

  # Map secrets file keys to expected environment variable names
  local secrets_map=(
    "PROXMOX_HOST:default.proxmox.endpoint"
    "PROXMOX_USERNAME:default.proxmox.username"
    "PROXMOX_SSH_USERNAME:default.proxmox.ssh_username"
    "VM_USERNAME:global.vm_username"
    "VM_SSH_KEY:global.vm_ssh_keys[0]" # Take first SSH key from array
  )

  for mapping in "${secrets_map[@]}"; do
    IFS=':' read -r env_var secret_key <<<"$mapping"
    local value
    value=$(sops -d "$secrets_file" | yq -r ".${secret_key} // \"\"" 2>/dev/null)
    if [[ -z "$value" || "$value" == "null" ]]; then
      missing_vars+=("$env_var")
    else
      printf "export %s='%s'\n" "$env_var" "$value" >>/tmp/cpc_env_vars.sh
      export "$env_var=$value"
      declare -g "$env_var=$value"
      # echo "DEBUG: Loaded secret: $env_var = $value" >&2
      log_debug "Loaded secret: $env_var = $value"
    fi
  done

  # Check for optional variables
  local optional_vars_map=(
    "PROXMOX_PASSWORD:default.proxmox.password"
    "VM_PASSWORD:global.vm_password"
    "AWS_ACCESS_KEY_ID:default.s3_backend.access_key"
    "AWS_SECRET_ACCESS_KEY:default.s3_backend.secret_key"
    "DOCKER_HUB_USERNAME:global.docker_hub_username"
    "DOCKER_HUB_PASSWORD:global.docker_hub_password"
    "HARBOR_HOSTNAME:default.harbor.hostname"
    "HARBOR_ROBOT_USERNAME:default.harbor.robot_username"
    "HARBOR_ROBOT_TOKEN:default.harbor.robot_token"
    "CLOUDFLARE_DNS_API_TOKEN:global.cloudflare_dns_api_token"
    "CLOUDFLARE_EMAIL:global.cloudflare_email"
    "PIHOLE_WEB_PASSWORD:default.pihole.web_password"
    "PIHOLE_IP_ADDRESS:default.pihole.ip_address"
  )

  for mapping in "${optional_vars_map[@]}"; do
    IFS=':' read -r env_var secret_key <<<"$mapping"
    local value
    value=$(sops -d "$secrets_file" | yq -r ".${secret_key} // \"\"" 2>/dev/null)
    if [[ -n "$value" && "$value" != "null" ]]; then
      export "$env_var=$value"
      declare -g "$env_var=$value"
      log_debug "Loaded optional secret: $env_var"
    fi
  done

  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    error_handle "$ERROR_CONFIG" "Missing required secrets: ${missing_vars[*]}" "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  log_success "Secrets loaded successfully"
  return 0
}

# Load environment variables
load_env_vars() {
  local repo_root
  repo_root=$(get_repo_path)

  # Load secrets with caching
  load_secrets_cached

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
    if [ -f "$CPC_CONTEXT_FILE" ]; then
      local current_workspace
      current_workspace=$(cat "$CPC_CONTEXT_FILE")
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
  if [ -f "$CPC_CONTEXT_FILE" ]; then
    local context
    context=$(cat "$CPC_CONTEXT_FILE" 2>/dev/null)
    if [[ $? -eq 0 && -n "$context" ]]; then
      echo "$context"
    else
      log_warning "Failed to read cluster context file: $CPC_CONTEXT_FILE"
      echo "default"
    fi
  else
    log_debug "Cluster context file not found, using default"
    echo "default"
  fi
}

# Set cluster context
set_cluster_context() {
  local context="$1"

  if [ -z "$context" ]; then
    error_handle "$ERROR_VALIDATION" "Usage: set_cluster_context <context_name>" "$SEVERITY_HIGH"
    return 1
  fi

  # Validate workspace name
  if ! validate_workspace_name "$context"; then
    return 1
  fi

  # Create directory if it doesn't exist
  local context_dir
  context_dir=$(dirname "$CPC_CONTEXT_FILE")
  if ! mkdir -p "$context_dir" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to create context directory: $context_dir" "$SEVERITY_HIGH"
    return 1
  fi

  # Write context with error handling
  if ! echo "$context" >"$CPC_CONTEXT_FILE" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to write cluster context to file: $CPC_CONTEXT_FILE" "$SEVERITY_HIGH"
    return 1
  fi

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

#----------------------------------------------------------------------
# Core Command Implementations
#----------------------------------------------------------------------

# Initial setup for cpc command
core_setup_cpc() {
  local current_script_path
  current_script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Go up from modules/ to main directory
  current_script_path="$(dirname "$current_script_path")"

  local repo_path_file="$HOME/.config/cpc/repo_path"
  mkdir -p "$(dirname "$repo_path_file")"

  echo "$current_script_path" >"$repo_path_file"

  echo -e "${GREEN}cpc setup complete. Repository path set to: $current_script_path${ENDCOLOR}"
  echo -e "${BLUE}You might want to add this script to your PATH, e.g., by creating a symlink in /usr/local/bin/cpc${ENDCOLOR}"
  echo -e "${BLUE}Example: sudo ln -s \"$current_script_path/cpc\" /usr/local/bin/cpc${ENDCOLOR}"
  echo -e "${BLUE}Also, create a 'cpc.env' file in '$current_script_path' for version management (see cpc.env.example).${ENDCOLOR}"
}

# Get or set the current cluster context (Tofu workspace)
core_ctx() {
  if [ -z "$1" ]; then
    local current_ctx
    current_ctx=$(get_current_cluster_context)
    echo "Current cluster context: $current_ctx"
    echo "Available Tofu workspaces:"
    (cd "$REPO_PATH/terraform" && tofu workspace list)
    return 0
  elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: cpc ctx [<cluster_name>]"
    echo "Sets the current cluster context for cpc and switches Tofu workspace."
    return 0
  fi

  local cluster_name="$1"
  local cluster_context_file="$CPC_CONTEXT_FILE"
  mkdir -p "$(dirname "$cluster_context_file")"

  echo "$cluster_name" >"$cluster_context_file"
  echo -e "${GREEN}Cluster context set to: $cluster_name${ENDCOLOR}"

  pushd "$REPO_PATH/terraform" >/dev/null || return 1
  if tofu workspace list | grep -qw "$cluster_name"; then
    tofu workspace select "$cluster_name"
  else
    echo -e "${YELLOW}Tofu workspace '$cluster_name' does not exist. Creating and selecting.${ENDCOLOR}"
    tofu workspace new "$cluster_name"
  fi
  popd >/dev/null || return 1

  # Clear cache when switching workspaces to ensure fresh data
  core_clear_cache

  # Update template variables for the new workspace context
  set_workspace_template_vars "$cluster_name"
}

# Clone a workspace environment to create a new one
core_clone_workspace() {
  if [[ "$1" == "-h" || "$1" == "--help" || $# -lt 2 ]]; then
    echo "Usage: cpc clone-workspace <source_workspace> <destination_workspace> [release_letter]"
    echo "Clones a workspace environment to create a new one."
    echo ""
    echo "Arguments:"
    echo "  <source_workspace>      Source workspace to clone (e.g., ubuntu, debian)"
    echo "  <destination_workspace> New workspace name (e.g., k8s129, test-workspace)"
    echo "  [release_letter]        Optional: Single letter to use for hostnames (defaults to first letter of destination)"
    echo ""
    echo "Example:"
    echo "  cpc clone-workspace ubuntu k8s129 k"
    return 0
  fi
  local source_workspace="$1"
  local new_workspace_name="$2"
  local release_letter="$3"
  local repo_root
  repo_root=$(get_repo_path)
  local source_env_file="$repo_root/$ENVIRONMENTS_DIR/${source_workspace}.env"
  local new_env_file="$repo_root/$ENVIRONMENTS_DIR/${new_workspace_name}.env"
  local locals_tf_file="$repo_root/$TERRAFORM_DIR/locals.tf"
  local locals_tf_backup_file="${locals_tf_file}.bak"

  # --- Checks ---
  if [[ ! -f "$source_env_file" ]]; then
    log_error "Source workspace environment file not found: $source_env_file"
    return 1
  fi
  if [[ -f "$new_env_file" ]]; then
    log_error "New workspace environment file already exists: $new_env_file"
    return 1
  fi
  if ! [[ "$release_letter" =~ $RELEASE_LETTER_PATTERN ]]; then
    log_error "Invalid release letter. Must be a single letter."
    return 1
  fi

  # --- Save the current context to restore it later ---
  local original_context
  original_context=$(get_current_cluster_context)

  # --- Create a backup of locals.tf for reliable rollback ---
  cp "$locals_tf_file" "$locals_tf_backup_file"

  log_step "Cloning workspace '$source_workspace' to '$new_workspace_name'..."

  # 1. Create and modify files
  cp "$source_env_file" "$new_env_file"
  sed -i "s/^RELEASE_LETTER=.*/RELEASE_LETTER=$release_letter/" "$new_env_file"
  log_info "New environment file created: $new_env_file"

  #  local template_var_name="pm_template_${source_workspace}_id"
  #  local new_entry="  \"${new_workspace_name}\" = var.${template_var_name}"
  #  sed -i "/template_vm_ids = {/a\\$new_entry" "$locals_tf_file"

  # --- PART 1: FIXING template_vm_ids ---

  log_info "Updating template_vm_ids map..."

  # Use awk to find the value ONLY within the template_vm_ids block
  local source_value
  source_value=$(awk -v workspace="\"${source_workspace}\"" '
  /template_vm_ids = {/,/}/{
    if ($1 == workspace) {
      # Found the line, extracting the value
      split($0, parts, "=")
      gsub(/[[:space:]]/, "", parts[2]) # Remove spaces
      gsub(/#.*/, "", parts[2])        # Remove comments
      print parts[2]
      exit
    }
  }' "$locals_tf_file")

  if [[ -z "$source_value" ]]; then
    log_error "Could not find a template value for '${source_workspace}' in the template_vm_ids map."
    return 1
  fi
  log_success "Found template value: ${source_value}"

  # Create and insert the new entry
  local new_template_entry="  \"${new_workspace_name}\" = ${source_value}"
  awk -i inplace -v new_entry="$new_template_entry" '
  /template_vm_ids = {/ { print; print new_entry; next }
  1' "$locals_tf_file"
  log_success "Added new entry to template_vm_ids."

  # --- PART 2: FIXING workspace_ip_map ---

  log_info "Updating workspace_ip_map with the first available IP index..."

  # 1. Get a sorted and unique list of all used IDs
  local used_ids
  used_ids=$(awk '/workspace_ip_map = {/,/}/' "$locals_tf_file" | grep -oP '=\s*\K[0-9]+' | sort -un)

  local next_id=1
  if [[ -n "$used_ids" ]]; then
    # 2. Look for the first "gap" in the sequence
    for id in $used_ids; do
      if [[ "$next_id" -lt "$id" ]]; then
        # Found! next_id is free, and id is already greater.
        break
      fi
      # If id matches next_id, increment and check the next
      next_id=$((next_id + 1))
    done
  fi

  # 3. Create and insert a new entry with the CORRECT free ID
  local new_ip_entry="    \"${new_workspace_name}\"         = ${next_id}  # Auto-added by clone-workspace"
  awk -i inplace -v new_entry="$new_ip_entry" '
  /workspace_ip_map = {/ { print; print new_entry; next }
  1' "$locals_tf_file"
  log_success "Added workspace_ip_map entry: \"${new_workspace_name}\" = ${next_id}"

  # 2. Switch context to the new workspace
  set_cluster_context "$new_workspace_name"

  # 3. Create the new workspace in Terraform
  log_step "Creating Terraform workspace '$new_workspace_name'..."
  if ! cpc_tofu workspace new "$new_workspace_name"; then
    log_error "Failed to create Terraform workspace '$new_workspace_name'."
    log_error "Reverting changes..."
    # --- Rollback changes in case of error ---
    rm -f "$new_env_file"
    mv "$locals_tf_backup_file" "$locals_tf_file"
    set_cluster_context "$original_context" # Restore the old context
    log_warning "Changes have been reverted."
    return 1
  fi

  # 4. Successful completion and cleanup
  rm -f "$locals_tf_backup_file" # Remove the backup as it's no longer needed
  log_success "Successfully cloned workspace '$source_workspace' to '$new_workspace_name'."
  log_info "Switched context to '$new_workspace_name'."

}

# (in modules/00_core.sh)
# (in modules/00_core.sh)

function core_delete_workspace() {
  if [[ -z "$1" ]]; then
    log_error "Usage: cpc delete-workspace <workspace_name>"
    return 1
  fi

  local workspace_name="$1"
  local repo_root
  repo_root=$(get_repo_path)
  local env_file="$repo_root/$ENVIRONMENTS_DIR/${workspace_name}.env"
  local locals_tf_file="$repo_root/$TERRAFORM_DIR/locals.tf"

  local original_context
  original_context=$(get_current_cluster_context)

  log_warning "This command will first DESTROY all infrastructure in workspace '$workspace_name'."
  read -p "Are you sure you want to DESTROY and DELETE workspace '$workspace_name'? This cannot be undone. (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Operation cancelled."
    return 1
  fi

  # 1. Switch to the context that will be deleted, to destroy resources
  set_cluster_context "$workspace_name"

  # 2. Destroy all resources
  log_step "Destroying all resources in workspace '$workspace_name'..."
  if ! cpc_tofu deploy destroy; then
    log_error "Failed to destroy resources for workspace '$workspace_name'."
    log_error "Workspace deletion aborted. Please destroy resources manually before trying again."
    set_cluster_context "$original_context" # Restore the original context in case of error
    return 1
  fi
  log_success "All resources for '$workspace_name' have been destroyed."

  # Clear cache after destroying resources to ensure fresh data
  core_clear_cache

  # 3. Switch to a SAFE context BEFORE deletion.
  #    If we are deleting a different context, return to it.
  #    Otherwise, switch to 'ubuntu' (or 'default' if 'ubuntu' is not available).
  local safe_context="ubuntu" # 'ubuntu' is a good default candidate
  if [[ "$original_context" != "$workspace_name" ]]; then
    safe_context="$original_context"
  fi

  log_step "Switching to safe context ('$safe_context') to perform deletion..."
  # Use your own function to switch
  if ! core_ctx "$safe_context"; then
    log_error "Could not switch to a safe workspace ('$safe_context'). Aborting workspace deletion."
    log_warning "Resources were destroyed, but the empty workspace '$workspace_name' remains."
    return 1
  fi

  # 4. Now, while in the safe workspace, delete the target
  log_step "Deleting Terraform workspace '$workspace_name' from the backend..."
  if ! cpc_tofu workspace delete "$workspace_name"; then
    log_error "Failed to delete the Terraform workspace '$workspace_name' from backend."
  else
    log_success "Terraform workspace '$workspace_name' has been deleted."
  fi

  # 5. Clean up local configuration files
  log_step "Removing local configuration for '$workspace_name'..."
  if [[ -f "$env_file" ]]; then
    rm -f "$env_file"
    log_info "Removed environment file: $env_file."
  fi

  if grep -q "\"${workspace_name}\"" "$locals_tf_file"; then
    sed -i "/\"${workspace_name}\"/d" "$locals_tf_file"
    log_info "Removed entries for '$workspace_name' from locals.tf."
  fi

  # Clear cache after workspace deletion to ensure clean state
  core_clear_cache

  log_success "Workspace '$workspace_name' has been successfully deleted."
}

# Command wrapper for load_secrets function
core_load_secrets_command() {
  log_info "Reloading secrets from SOPS..."
  load_secrets_fresh
  log_success "Secrets reloaded successfully"
}

# Clear secrets and status cache
core_clear_cache() {
  local cache_files=(
    "/tmp/cpc_secrets_cache"
    "/tmp/cpc_env_cache.sh"
    "/tmp/cpc_status_cache_*"
    "/tmp/cpc_ssh_cache_*"
    "/tmp/cpc_tofu_output_cache_*"
    "/tmp/cpc_workspace_cache"
  )

  log_info "Clearing CPC cache files..."

  for pattern in "${cache_files[@]}"; do
    if [[ "$pattern" == *"*"* ]]; then
      # Handle wildcard patterns
      for file in $pattern; do
        if [[ -f "$file" ]]; then
          rm -f "$file"
          log_debug "Removed cache file: $file"
        fi
      done
    else
      # Handle specific files
      if [[ -f "$pattern" ]]; then
        rm -f "$pattern"
        log_debug "Removed cache file: $pattern"
      fi
    fi
  done

  log_success "Cache cleared successfully"
}

# List all available workspaces
core_list_workspaces() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: cpc list-workspaces"
    echo "Lists all available workspaces (Tofu workspaces and environment files)."
    return 0
  fi

  local repo_root
  repo_root=$(get_repo_path)

  log_info "Available Workspaces:"
  echo

  # Show current workspace
  local current_workspace=""
  if [[ -f "$CPC_CONTEXT_FILE" ]]; then
    current_workspace=$(cat "$CPC_CONTEXT_FILE")
    log_info "Current workspace: $current_workspace"
  else
    log_warning "No current workspace set"
  fi

  echo

  # List Tofu workspaces
  log_info "Tofu workspaces:"
  if [[ -d "$repo_root/terraform" ]]; then
    pushd "$repo_root/terraform" >/dev/null || return 1
    if command -v tofu &>/dev/null; then
      tofu workspace list
    else
      log_warning "OpenTofu not available - cannot list Tofu workspaces"
    fi
    popd >/dev/null || return 1
  else
    log_warning "Terraform directory not found"
  fi

  echo
  echo

  # List environment files
  log_info "Environment files:"
  if [[ -d "$repo_root/envs" ]]; then
    for env_file in "$repo_root/envs"/*.env; do
      if [[ -f "$env_file" ]]; then
        local env_name
        env_name=$(basename "$env_file" .env)
        echo "  $env_name"
      fi
    done
  else
    log_warning "Environment directory not found"
  fi
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

# @description: Retrieves the full JSON output from Terraform for the current workspace.
# @stdout: The full JSON string from 'cpc deploy output'.
# @internal
_get_terraform_outputs_json() {
  log_debug "Getting all infrastructure data from Tofu..."
  local raw_output
  raw_output=$("$REPO_PATH/cpc" deploy output -json 2>/dev/null)

  local tofu_outputs_json
  tofu_outputs_json=$(echo "$raw_output" | sed -n '/^{$/,/^}$/p')

  if [[ -z "$tofu_outputs_json" ]]; then
    log_error "Failed to extract JSON from 'cpc deploy output'. Please check for errors."
    return 1
  fi
  # Output JSON for capture
  echo "$tofu_outputs_json"
  return 0
}

# @description: Finds a hostname in the Terraform output JSON based on an IP address.
# @arg $1: IP address to search for.
# @arg $2: The full Terraform output JSON string.
# @stdout: The found hostname, or empty string if not found.
# @internal
_get_hostname_by_ip() {
  local ip_address="$1"
  local tofu_outputs_json="$2"
  local hostname

  if [[ -z "$ip_address" || -z "$tofu_outputs_json" ]]; then
    log_error "Internal error: IP address or JSON data not provided to _get_hostname_by_ip."
    return 1
  fi

  # Extract the inventory string from the full JSON
  local ansible_inventory_string
  ansible_inventory_string=$(echo "$tofu_outputs_json" | jq -r '.ansible_inventory.value')

  hostname=$(echo "$ansible_inventory_string" | jq -r --arg IP "$ip_address" '._meta.hostvars | to_entries[] | select(.value.ansible_host == $IP) | .key')

  echo "$hostname"
  return 0
}

# @description Creates a temporary static inventory file from the current workspace's Terraform output.
# @stdout The path to the created temporary inventory file.
# @return 1 on failure.

function ansible_create_temp_inventory() {
  log_debug "Creating temporary static Ansible inventory from cached cluster data..."

  # Get cached cluster summary data (reuses the caching logic from tofu module)
  local current_ctx
  current_ctx=$(get_current_cluster_context) || return 1

  local cache_file="/tmp/cpc_status_cache_${current_ctx}"
  local dynamic_inventory_json=""

  # Try to get data from cache first
  if [[ -f "$cache_file" ]]; then
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    if [[ $cache_age -lt 30 ]]; then
      local cached_data
      cached_data=$(cat "$cache_file" 2>/dev/null)
      if [[ -n "$cached_data" && "$cached_data" != "null" ]]; then
        # Check if cached data has .value or is direct JSON
        if echo "$cached_data" | jq -e '.value' >/dev/null 2>&1; then
          dynamic_inventory_json=$(echo "$cached_data" | jq -r '.value')
        else
          dynamic_inventory_json="$cached_data"
        fi
        log_debug "Using cached cluster data for inventory (age: ${cache_age}s)"
      fi
    fi
  fi

  # Fall back to direct tofu call if no cache or cache is stale
  if [[ -z "$dynamic_inventory_json" || "$dynamic_inventory_json" == "null" ]]; then
    log_debug "Cache unavailable, getting fresh cluster data..."
    local raw_output
    if ! raw_output=$("$REPO_PATH/cpc" deploy output -json cluster_summary 2>/dev/null) || [[ -z "$raw_output" ]]; then
      log_error "Command 'cpc deploy output -json cluster_summary' failed or returned empty."
      return 1
    fi

    # Extract JSON data from the output
    dynamic_inventory_json=$(echo "$raw_output" | grep '^{.*}$' | tail -1)
    if [[ -z "$dynamic_inventory_json" || "$dynamic_inventory_json" == "null" ]]; then
      log_error "Cluster summary data is empty or invalid."
      return 1
    fi
  fi

  local temp_inventory_file
  temp_inventory_file=$(mktemp /tmp/cpc_inventory.XXXXXX.ini)

  # Transform the cluster data into Ansible inventory INI format with groups
  if ! cat >"$temp_inventory_file" <<EOF; then
[control_plane]
$(echo "$dynamic_inventory_json" | jq -r 'to_entries[] | select(.key | contains("controlplane")) | "\(.value.hostname) ansible_host=\(.value.IP)"')

[workers]
$(echo "$dynamic_inventory_json" | jq -r 'to_entries[] | select(.key | contains("worker")) | "\(.value.hostname) ansible_host=\(.value.IP)"')

[all:vars]
ansible_user=abevz
ansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
EOF
    log_error "Failed to create static inventory file."
    rm -f "$temp_inventory_file"
    return 1
  fi

  log_debug "Temporary static inventory created at $temp_inventory_file"
  echo "$temp_inventory_file"
  return 0
}

# Export core functions
export -f get_repo_path load_secrets_fresh load_secrets_cached load_env_vars set_workspace_template_vars
export -f get_current_cluster_context set_cluster_context validate_workspace_name
export -f cpc_setup cpc_core
export -f core_setup_cpc core_ctx core_clone_workspace core_delete_workspace core_load_secrets_command core_clear_cache core_list_workspaces
export -f _get_terraform_outputs_json _get_hostname_by_ip ansible_create_temp_inventory
