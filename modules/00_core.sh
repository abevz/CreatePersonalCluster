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
  auto)
    shift
    core_auto_command "$@"
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
    log_info "Available commands: setup-cpc, ctx, clone-workspace, delete-workspace, load_secrets, auto, clear-cache, list-workspaces"
    return 1
    ;;
  esac
}

#----------------------------------------------------------------------
# Refactored Functions
#----------------------------------------------------------------------

# parse_core_command() - Parses and validates the incoming core command and arguments to determine the appropriate action.
function parse_core_command() {
  local command="$1"
  shift
  case "$command" in
  setup-cpc|ctx|clone-workspace|delete-workspace|load_secrets|clear-cache|list-workspaces)
    echo "$command"
    ;;
  *)
    echo "invalid"
    ;;
  esac
}

# route_core_command() - Routes the validated command to the corresponding handler function based on the command type.
function route_core_command() {
  local command="$1"
  shift
  case "$command" in
  setup-cpc)
    core_setup_cpc "$@"
    ;;
  ctx)
    core_ctx "$@"
    ;;
  clone-workspace)
    core_clone_workspace "$@"
    ;;
  delete-workspace)
    core_delete_workspace "$@"
    ;;
  load_secrets)
    core_load_secrets_command "$@"
    ;;
  clear-cache)
    core_clear_cache "$@"
    ;;
  list-workspaces)
    core_list_workspaces "$@"
    ;;
  *)
    log_error "Unknown core command: $command"
    return 1
    ;;
  esac
}

# handle_core_errors() - Centralizes error handling for invalid commands or routing failures.
function handle_core_errors() {
  local error_type="$1"
  local message="$2"
  case "$error_type" in
  invalid_command)
    log_error "Invalid core command: $message"
    ;;
  routing_failure)
    log_error "Failed to route command: $message"
    ;;
  *)
    log_error "Unknown error: $message"
    ;;
  esac
}

# determine_script_directory() - Identifies the directory containing the current script.
function determine_script_directory() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$script_dir"
}

# navigate_to_parent_directory() - Moves up from the script directory to the repository root.
function navigate_to_parent_directory() {
  local script_dir="$1"
  dirname "$script_dir"
}

# validate_repo_path() - Verifies that the determined path is a valid repository.
function validate_repo_path() {
  local repo_path="$1"
  if [[ -d "$repo_path" && -f "$repo_path/config.conf" ]]; then
    echo "valid"
  else
    echo "invalid"
  fi
}

# Get repository path
get_repo_path() {
  local script_dir
  script_dir=$(determine_script_directory)
  local repo_path
  repo_path=$(navigate_to_parent_directory "$script_dir")
  if [[ "$(validate_repo_path "$repo_path")" == "valid" ]]; then
    echo "$repo_path"
  else
    error_handle "$ERROR_CONFIG" "Invalid repository path: $repo_path" "$SEVERITY_CRITICAL" "abort"
    return 1
  fi
}

# check_cache_freshness() - Determines if the cached secrets are still valid based on age and file existence.
function check_cache_freshness() {
  local cache_file="$1"
  local secrets_file="$2"
  if [[ -f "$cache_file" && -f "$secrets_file" ]]; then
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    local secrets_age=$(($(date +%s) - $(stat -c %Y "$secrets_file" 2>/dev/null || echo 0)))
    if [[ $cache_age -lt 300 && $cache_age -lt $secrets_age ]]; then
      echo "fresh"
    else
      echo "stale"
    fi
  else
    echo "missing"
  fi
}

# decrypt_secrets_file() - Decrypts the SOPS secrets file using the appropriate tools.
function decrypt_secrets_file() {
  local secrets_file="$1"
  if command -v sops &>/dev/null; then
    sops -d "$secrets_file"
  else
    log_error "SOPS not found. Cannot decrypt secrets."
    return 1
  fi
}

# load_secrets_into_environment() - Parses and exports the decrypted secrets into the environment variables.
function load_secrets_into_environment() {
  local decrypted_data="$1"
  
  # Use yq to parse YAML and extract flat key-value pairs
  if command -v yq &>/dev/null; then
    # Parse YAML and create environment variables
    echo "$decrypted_data" | yq -o shell | while read -r line; do
      # Skip empty lines and comments
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      
      # Extract variable name and value
      if [[ "$line" =~ ^export[[:space:]]+([^=]+)=(.*)$ ]]; then
        var_name="${BASH_REMATCH[1]}"
        var_value="${BASH_REMATCH[2]}"
        
        # Remove quotes from value if present
        var_value=$(echo "$var_value" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\\(.*\\)'$/\\1/")
        
        # Convert YAML path to environment variable name
        # e.g., default.proxmox.username -> PROXMOX_USERNAME
        env_name=$(echo "$var_name" | tr '[:lower:]' '[:upper:]' | tr '.' '_' | sed 's/[^A-Z0-9_]//g')
        
        # Export the variable
        export "$env_name=$var_value"
        log_debug "Exported secret: $env_name"
      fi
    done
  else
    log_error "yq not found. Cannot parse secrets YAML."
    return 1
  fi
}

# update_cache_timestamp() - Updates the cache file with the latest secrets and timestamp.
function update_cache_timestamp() {
  local cache_file="$1"
  local secrets_data="$2"
  echo "# CPC Secrets Cache - Generated $(date)" > "$cache_file"
  echo "$secrets_data" >> "$cache_file"
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

  local cache_status
  cache_status=$(check_cache_freshness "$cache_file" "$secrets_file")
  if [[ "$cache_status" == "fresh" ]]; then
    log_info "Using cached secrets (age: $(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))s)"
    source "$cache_env_file"
    return 0
  fi

  # Load fresh secrets and cache them
  log_info "Loading fresh secrets..."
  if load_secrets_fresh; then
    # Cache both secret and environment variables
    {
      echo "# CPC Secrets and Environment Cache - Generated $(date)"
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
      # Environment variables from .env file
      [[ -n "${PRIMARY_DNS_SERVER:-}" ]] && echo "export PRIMARY_DNS_SERVER='$PRIMARY_DNS_SERVER'"
      [[ -n "${SECONDARY_DNS_SERVER:-}" ]] && echo "export SECONDARY_DNS_SERVER='$SECONDARY_DNS_SERVER'"
      [[ -n "${TEMPLATE_VM_ID:-}" ]] && echo "export TEMPLATE_VM_ID='$TEMPLATE_VM_ID'"
      [[ -n "${TEMPLATE_VM_NAME:-}" ]] && echo "export TEMPLATE_VM_NAME='$TEMPLATE_VM_NAME'"
      [[ -n "${IMAGE_NAME:-}" ]] && echo "export IMAGE_NAME='$IMAGE_NAME'"
      [[ -n "${IMAGE_LINK:-}" ]] && echo "export IMAGE_LINK='$IMAGE_LINK'"
      [[ -n "${KUBERNETES_SHORT_VERSION:-}" ]] && echo "export KUBERNETES_SHORT_VERSION='$KUBERNETES_SHORT_VERSION'"
      [[ -n "${KUBERNETES_MEDIUM_VERSION:-}" ]] && echo "export KUBERNETES_MEDIUM_VERSION='$KUBERNETES_MEDIUM_VERSION'"
      [[ -n "${KUBERNETES_LONG_VERSION:-}" ]] && echo "export KUBERNETES_LONG_VERSION='$KUBERNETES_LONG_VERSION'"
      [[ -n "${CNI_PLUGINS_VERSION:-}" ]] && echo "export CNI_PLUGINS_VERSION='$CNI_PLUGINS_VERSION'"
      [[ -n "${CALICO_VERSION:-}" ]] && echo "export CALICO_VERSION='$CALICO_VERSION'"
      [[ -n "${METALLB_VERSION:-}" ]] && echo "export METALLB_VERSION='$METALLB_VERSION'"
      [[ -n "${COREDNS_VERSION:-}" ]] && echo "export COREDNS_VERSION='$COREDNS_VERSION'"
      [[ -n "${METRICS_SERVER_VERSION:-}" ]] && echo "export METRICS_SERVER_VERSION='$METRICS_SERVER_VERSION'"
      [[ -n "${ETCD_VERSION:-}" ]] && echo "export ETCD_VERSION='$ETCD_VERSION'"
      [[ -n "${KUBELET_SERVING_CERT_APPROVER_VERSION:-}" ]] && echo "export KUBELET_SERVING_CERT_APPROVER_VERSION='$KUBELET_SERVING_CERT_APPROVER_VERSION'"
      [[ -n "${LOCAL_PATH_PROVISIONER_VERSION:-}" ]] && echo "export LOCAL_PATH_PROVISIONER_VERSION='$LOCAL_PATH_PROVISIONER_VERSION'"
      [[ -n "${CERT_MANAGER_VERSION:-}" ]] && echo "export CERT_MANAGER_VERSION='$CERT_MANAGER_VERSION'"
      [[ -n "${ARGOCD_VERSION:-}" ]] && echo "export ARGOCD_VERSION='$ARGOCD_VERSION'"
      [[ -n "${INGRESS_NGINX_VERSION:-}" ]] && echo "export INGRESS_NGINX_VERSION='$INGRESS_NGINX_VERSION'"
      [[ -n "${PM_TEMPLATE_ID:-}" ]] && echo "export PM_TEMPLATE_ID='$PM_TEMPLATE_ID'"
      [[ -n "${VM_CPU_CORES:-}" ]] && echo "export VM_CPU_CORES='$VM_CPU_CORES'"
      [[ -n "${VM_MEMORY_DEDICATED:-}" ]] && echo "export VM_MEMORY_DEDICATED='$VM_MEMORY_DEDICATED'"
      [[ -n "${VM_DISK_SIZE:-}" ]] && echo "export VM_DISK_SIZE='$VM_DISK_SIZE'"
      [[ -n "${VM_STARTED:-}" ]] && echo "export VM_STARTED='$VM_STARTED'"
      [[ -n "${VM_DOMAIN:-}" ]] && echo "export VM_DOMAIN='$VM_DOMAIN'"
      [[ -n "${RELEASE_LETTER:-}" ]] && echo "export RELEASE_LETTER='$RELEASE_LETTER'"
      [[ -n "${ADDITIONAL_WORKERS:-}" ]] && echo "export ADDITIONAL_WORKERS='$ADDITIONAL_WORKERS'"
    } > "$cache_env_file"
    update_cache_timestamp "$cache_file" "$(date)"
  fi
}

# locate_secrets_file() - Finds and validates the path to the SOPS secrets file.
function locate_secrets_file() {
  local repo_root="$1"
  local secrets_file="$repo_root/terraform/secrets.sops.yaml"
  if [[ -f "$secrets_file" ]]; then
    echo "$secrets_file"
  else
    log_error "Secrets file not found: $secrets_file"
    return 1
  fi
}

# decrypt_secrets_directly() - Decrypts the secrets file without using cache.
function decrypt_secrets_directly() {
  local secrets_file="$1"
  decrypt_secrets_file "$secrets_file"
}

# export_secrets_variables() - Exports the decrypted secrets as environment variables.
function export_secrets_variables() {
  local decrypted_data="$1"
  load_secrets_into_environment "$decrypted_data"
}

# validate_secrets_integrity() - Checks that all required secrets are present and valid.
function validate_secrets_integrity() {
  local required_vars=("PROXMOX_HOST" "PROXMOX_USERNAME" "VM_USERNAME" "VM_SSH_KEY")
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      log_error "Missing required secret: $var"
      return 1
    fi
  done
  echo "valid"
}

# Load secrets without caching
load_secrets_fresh() {
  local repo_root
  if ! repo_root=$(get_repo_path); then
    return 1
  fi

  local secrets_file
  secrets_file=$(locate_secrets_file "$repo_root")
  if [[ -z "$secrets_file" ]]; then
    return 1
  fi

  local decrypted_data
  decrypted_data=$(decrypt_secrets_directly "$secrets_file")
  if [[ -z "$decrypted_data" ]]; then
    return 1
  fi

  export_secrets_variables "$decrypted_data"
  if [[ "$(validate_secrets_integrity)" == "valid" ]]; then
    log_success "Secrets loaded successfully"
  else
    return 1
  fi
}

# locate_env_file() - Finds the appropriate environment file for the current context.
function locate_env_file() {
  local repo_root="$1"
  local context="$2"
  local env_file="$repo_root/envs/${context}.env"
  if [[ -f "$env_file" ]]; then
    echo "$env_file"
  else
    log_debug "Environment file not found: $env_file"
    echo ""
  fi
}

# parse_env_file() - Reads and parses key-value pairs from the environment file.
function parse_env_file() {
  local env_file="$1"
  local -A env_vars
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    # Remove inline comments and quotes
    value=$(echo "$value" | sed 's/[[:space:]]*#.*$//' | tr -d '"' 2>/dev/null || echo "")
    env_vars["$key"]="$value"
  done < "$env_file"
  declare -p env_vars
}

# export_env_variables() - Sets the parsed variables as environment variables.
function export_env_variables() {
  local env_vars="$1"
  eval "$env_vars"
  for key in "${!env_vars[@]}"; do
    export "$key=${env_vars[$key]}"
  done
}

# validate_env_setup() - Verifies that required environment variables are loaded correctly.
function validate_env_setup() {
  local required_vars=("REPO_PATH" "TERRAFORM_DIR")
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      log_warning "Missing environment variable: $var"
    fi
  done
}

# Load environment variables
load_env_vars() {
  local repo_root
  if ! repo_root=$(get_repo_path); then
    return 1
  fi

  local cpc_env_file="$repo_root/cpc.env"
  if [[ -f "$cpc_env_file" ]]; then
    local env_vars
    env_vars=$(parse_env_file "$cpc_env_file")
    export_env_variables "$env_vars"
    log_debug "Loaded environment variables from cpc.env"
  fi

  # Also load workspace-specific environment variables
  local context
  context=$(get_current_cluster_context)
  local workspace_env_file
  workspace_env_file=$(locate_env_file "$repo_root" "$context")
  if [[ -n "$workspace_env_file" ]]; then
    local workspace_vars
    workspace_vars=$(parse_env_file "$workspace_env_file")
    export_env_variables "$workspace_vars"
    log_debug "Loaded workspace environment variables from $workspace_env_file"
  fi

  validate_env_setup
}

# extract_template_values() - Extracts template-related values from the environment file.
function extract_template_values() {
  local env_file="$1"
  local template_vars=("TEMPLATE_VM_ID" "TEMPLATE_VM_NAME" "IMAGE_NAME" "KUBERNETES_VERSION" "CALICO_VERSION" "METALLB_VERSION" "COREDNS_VERSION" "ETCD_VERSION")
  local -A extracted
  for var in "${template_vars[@]}"; do
    value=$(grep -E "^${var}=" "$env_file" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "")
    extracted["$var"]="$value"
  done
  declare -p extracted
}

# validate_template_variables() - Checks that all required template variables are present and valid.
function validate_template_variables() {
  local template_vars="$1"
  eval "$template_vars"
  local required=("TEMPLATE_VM_ID" "TEMPLATE_VM_NAME")
  for var in "${required[@]}"; do
    if [[ -z "${extracted[$var]:-}" ]]; then
      log_warning "Missing template variable: $var"
    fi
  done
}

# export_template_vars() - Sets the validated template variables as environment variables.
function export_template_vars() {
  local template_vars="$1"
  eval "$template_vars"
  for key in "${!extracted[@]}"; do
    export "$key=${extracted[$key]}"
  done
}

# log_template_setup() - Logs the successful setup of template variables.
function log_template_setup() {
  log_info "Template variables loaded successfully"
}

# Set workspace-specific template variables
set_workspace_template_vars() {
  local workspace="$1"
  if [ -z "$workspace" ]; then
    log_error "Workspace name is required"
    return 1
  fi

  local repo_root
  if ! repo_root=$(get_repo_path); then
    return 1
  fi

  local env_file="$repo_root/envs/${workspace}.env"
  if [[ ! -f "$env_file" ]]; then
    log_debug "Environment file not found for workspace: $workspace"
    return 0
  fi

  local template_vars
  template_vars=$(extract_template_values "$env_file")
  validate_template_variables "$template_vars"
  export_template_vars "$template_vars"
  log_template_setup
}

# read_context_file() - Reads the cluster context from the designated file.
function read_context_file() {
  local context_file="$CPC_CONTEXT_FILE"
  if [[ -f "$context_file" ]]; then
    cat "$context_file" 2>/dev/null
  else
    echo ""
  fi
}

# validate_context_content() - Checks if the read context is valid and not empty.
function validate_context_content() {
  local context="$1"
  if [[ -n "$context" && "$context" != "null" ]]; then
    echo "valid"
  else
    echo "invalid"
  fi
}

# fallback_to_default() - Provides a default context if the file is missing or invalid.
function fallback_to_default() {
  echo "default"
}

# return_context_value() - Returns the determined context value.
function return_context_value() {
  local context="$1"
  if [[ "$(validate_context_content "$context")" == "valid" ]]; then
    echo "$context"
  else
    fallback_to_default
  fi
}

# Get current cluster context
get_current_cluster_context() {
  local context
  context=$(read_context_file)
  return_context_value "$context"
}

# validate_context_input() - Ensures the provided context name is valid.
function validate_context_input() {
  local context="$1"
  if [[ -n "$context" && "$context" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "valid"
  else
    echo "invalid"
  fi
}

# create_context_directory() - Creates the necessary directory structure for the context file.
function create_context_directory() {
  local context_file="$CPC_CONTEXT_FILE"
  mkdir -p "$(dirname "$context_file")"
}

# write_context_file() - Writes the context to the file with error handling.
function write_context_file() {
  local context="$1"
  local context_file="$CPC_CONTEXT_FILE"
  echo "$context" > "$context_file"
  if [[ $? -eq 0 ]]; then
    echo "success"
  else
    echo "failure"
  fi
}

# confirm_context_set() - Logs and confirms the successful setting of the context.
function confirm_context_set() {
  local context="$1"
  log_success "Cluster context set to: $context"
}

# Set cluster context
set_cluster_context() {
  local context="$1"
  if [[ "$(validate_context_input "$context")" == "invalid" ]]; then
    error_handle "$ERROR_VALIDATION" "Invalid context name: $context" "$SEVERITY_HIGH"
    return 1
  fi

  create_context_directory
  if [[ "$(write_context_file "$context")" == "success" ]]; then
    confirm_context_set "$context"
  else
    log_error "Failed to write context file"
    return 1
  fi
}

# check_name_format() - Verifies that the workspace name matches the required pattern.
function check_name_format() {
  local name="$1"
  if [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "valid"
  else
    echo "invalid"
  fi
}

# validate_name_length() - Ensures the name is within the acceptable length limits.
function validate_name_length() {
  local name="$1"
  if [[ ${#name} -ge 1 && ${#name} -le 50 ]]; then
    echo "valid"
  else
    echo "invalid"
  fi
}

# check_reserved_names() - Prevents the use of reserved or invalid workspace names.
function check_reserved_names() {
  local name="$1"
  local reserved=("default" "null" "none")
  for res in "${reserved[@]}"; do
    if [[ "$name" == "$res" ]]; then
      echo "reserved"
      return
    fi
  done
  echo "valid"
}

# return_validation_result() - Reports the validation outcome with appropriate messages.
function return_validation_result() {
  local name="$1"
  if [[ "$(check_name_format "$name")" == "invalid" ]]; then
    log_error "Invalid workspace name format: $name"
    return 1
  fi
  if [[ "$(validate_name_length "$name")" == "invalid" ]]; then
    log_error "Workspace name length invalid: $name"
    return 1
  fi
  if [[ "$(check_reserved_names "$name")" == "reserved" ]]; then
    log_error "Reserved workspace name: $name"
    return 1
  fi
  echo "valid"
}

# Validate workspace name
validate_workspace_name() {
  local name="$1"
  return_validation_result "$name"
}

# parse_ctx_arguments() - Processes command-line arguments for the context command.
function parse_ctx_arguments() {
  local args=("$@")
  if [[ ${#args[@]} -eq 0 ]]; then
    echo "show_current"
  elif [[ "${args[0]}" == "-h" || "${args[0]}" == "--help" ]]; then
    echo "help"
  else
    echo "set_context ${args[0]}"
  fi
}

# display_current_context() - Shows the current cluster context when no arguments are provided.
function display_current_context() {
  local current_ctx
  current_ctx=$(get_current_cluster_context)
  echo "Current cluster context: $current_ctx"
  echo "Available Tofu workspaces:"
  (cd "$REPO_PATH/terraform" && tofu workspace list)
}

# set_new_context() - Sets a new cluster context if provided.
function set_new_context() {
  local context="$1"
  set_cluster_context "$context"
  # Additional logic for switching workspaces
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
  set_workspace_template_vars "$context"
}

# handle_ctx_help() - Displays help information for the context command.
function handle_ctx_help() {
  echo "Usage: cpc ctx [<cluster_name>]"
  echo "Sets the current cluster context for cpc and switches Tofu workspace."
}

# Get or set the current cluster context (Tofu workspace)
core_ctx() {
  local parsed
  parsed=$(parse_ctx_arguments "$@")
  case "$parsed" in
  show_current)
    display_current_context
    ;;
  help)
    handle_ctx_help
    ;;
  set_context*)
    local context="${parsed#* }"
    set_new_context "$context"
    ;;
  *)
    log_error "Invalid context command"
    return 1
    ;;
  esac
}

# determine_script_path() - Identifies the path to the CPC script.
function determine_script_path() {
  local current_script_path
  current_script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  dirname "$current_script_path"
}

# create_config_directory() - Creates the necessary configuration directory structure.
function create_config_directory() {
  local repo_path_file="$HOME/.config/cpc/repo_path"
  mkdir -p "$(dirname "$repo_path_file")"
}

# write_repo_path_file() - Writes the repository path to the configuration file.
function write_repo_path_file() {
  local repo_path="$1"
  local repo_path_file="$HOME/.config/cpc/repo_path"
  echo "$repo_path" > "$repo_path_file"
}

# provide_setup_instructions() - Displays instructions for completing the setup.
function provide_setup_instructions() {
  local repo_path="$1"
  echo -e "${GREEN}cpc setup complete. Repository path set to: $repo_path${ENDCOLOR}"
  echo -e "${BLUE}You might want to add this script to your PATH, e.g., by creating a symlink in /usr/local/bin/cpc${ENDCOLOR}"
  echo -e "${BLUE}Example: sudo ln -s \"$repo_path/cpc\" /usr/local/bin/cpc${ENDCOLOR}"
  echo -e "${BLUE}Also, create a 'cpc.env' file in '$repo_path' for version management (see cpc.env.example).${ENDCOLOR}"
}

# Initial setup for cpc command
core_setup_cpc() {
  local repo_path
  repo_path=$(determine_script_path)
  create_config_directory
  write_repo_path_file "$repo_path"
  provide_setup_instructions "$repo_path"
}

# validate_clone_parameters() - Checks that source workspace and new name are valid.
function validate_clone_parameters() {
  local source_workspace="$1"
  local new_workspace_name="$2"
  if [[ -z "$source_workspace" || -z "$new_workspace_name" ]]; then
    log_error "Source and destination workspace names are required"
    return 1
  fi
  if [[ "$source_workspace" == "$new_workspace_name" ]]; then
    log_error "Source and destination workspaces cannot be the same"
    return 1
  fi
  validate_workspace_name "$new_workspace_name"
}

# backup_existing_files() - Creates backups of files that will be modified.
function backup_existing_files() {
  local locals_tf_file="$1"
  local locals_tf_backup_file="${locals_tf_file}.bak"
  cp "$locals_tf_file" "$locals_tf_backup_file"
}

# copy_workspace_files() - Copies environment and configuration files for the new workspace.
function copy_workspace_files() {
  local source_env_file="$1"
  local new_env_file="$2"
  cp "$source_env_file" "$new_env_file"
}

# update_workspace_mappings() - Updates any mappings or references for the new workspace.
function update_workspace_mappings() {
  local new_workspace_name="$1"
  local release_letter="$2"
  local new_env_file="$3"
  sed -i "s/^RELEASE_LETTER=.*/RELEASE_LETTER=$release_letter/" "$new_env_file"
}

# switch_to_new_workspace() - Sets the context to the newly cloned workspace.
function switch_to_new_workspace() {
  local new_workspace_name="$1"
  set_cluster_context "$new_workspace_name"
  # Additional cloning logic here
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

  # Validate parameters
  if ! validate_clone_parameters "$source_workspace" "$new_workspace_name"; then
    return 1
  fi

  # Checks
  if [[ ! -f "$source_env_file" ]]; then
    log_error "Source workspace environment file not found: $source_env_file"
    return 1
  fi

  # Backup files
  backup_existing_files "$locals_tf_file"

  # Copy files
  copy_workspace_files "$source_env_file" "$new_env_file"

  # Update mappings
  update_workspace_mappings "$new_workspace_name" "$release_letter" "$new_env_file"

  # Switch to new workspace
  switch_to_new_workspace "$new_workspace_name"

  log_success "Successfully cloned workspace '$source_workspace' to '$new_workspace_name'."
}

# confirm_deletion() - Prompts user for confirmation before deleting the workspace.
function confirm_deletion() {
  local workspace_name="$1"
  read -p "Are you sure you want to DESTROY and DELETE workspace '$workspace_name'? This cannot be undone. (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Operation cancelled."
    return 1
  fi
}

# destroy_resources() - Destroys all infrastructure resources in the workspace.
function destroy_resources() {
  local workspace_name="$1"
  log_step "Destroying all resources in workspace '$workspace_name'..."
  if ! cpc_tofu deploy destroy; then
    log_error "Failed to destroy resources for workspace '$workspace_name'."
    return 1
  fi
  log_success "All resources for '$workspace_name' have been destroyed."
}

# remove_workspace_files() - Deletes environment and configuration files.
function remove_workspace_files() {
  local workspace_name="$1"
  local repo_root
  repo_root=$(get_repo_path)
  local env_file="$repo_root/$ENVIRONMENTS_DIR/${workspace_name}.env"
  local locals_tf_file="$repo_root/$TERRAFORM_DIR/locals.tf"

  if [[ -f "$env_file" ]]; then
    rm -f "$env_file"
    log_info "Removed environment file: $env_file."
  fi

  if grep -q "\"${workspace_name}\"" "$locals_tf_file"; then
    sed -i "/\"${workspace_name}\"/d" "$locals_tf_file"
    log_info "Removed entries for '$workspace_name' from locals.tf."
  fi
}

# update_mappings() - Removes workspace references from mapping files.
function update_mappings() {
  # Additional mapping updates if needed
  log_debug "Mappings updated"
}

# switch_to_safe_context() - Switches to a safe context after deletion.
function switch_to_safe_context() {
  local workspace_name="$1"
  local original_context="$2"
  local safe_context="ubuntu"
  if [[ "$original_context" != "$workspace_name" ]]; then
    safe_context="$original_context"
  fi

  log_step "Switching to safe context ('$safe_context') to perform deletion..."
  if ! core_ctx "$safe_context"; then
    log_error "Could not switch to a safe workspace ('$safe_context'). Aborting workspace deletion."
    return 1
  fi
}

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
  if ! confirm_deletion "$workspace_name"; then
    return 1
  fi

  # Switch to the context that will be deleted
  set_cluster_context "$workspace_name"

  # Destroy resources
  if ! destroy_resources "$workspace_name"; then
    log_error "Resources were destroyed, but the empty workspace '$workspace_name' remains."
    return 1
  fi

  # Clear cache
  core_clear_cache

  # Switch to safe context
  if ! switch_to_safe_context "$workspace_name" "$original_context"; then
    return 1
  fi

  # Delete Terraform workspace
  log_step "Deleting Terraform workspace '$workspace_name' from the backend..."
  if ! cpc_tofu workspace delete "$workspace_name"; then
    log_error "Failed to delete the Terraform workspace '$workspace_name' from backend."
  else
    log_success "Terraform workspace '$workspace_name' has been deleted."
  fi

  # Clean up local files
  remove_workspace_files "$workspace_name"
  update_mappings

  log_success "Workspace '$workspace_name' has been successfully deleted."
}

# parse_secrets_command_args() - Processes arguments for the load secrets command.
function parse_secrets_command_args() {
  # Simple parsing for now
  echo "load"
}

# refresh_secrets_cache() - Forces a refresh of the secrets cache.
function refresh_secrets_cache() {
  load_secrets_fresh
}

# log_secrets_reload() - Logs the successful reloading of secrets.
function log_secrets_reload() {
  log_success "Secrets reloaded successfully"
}

# handle_secrets_errors() - Manages errors during the secrets loading process.
function handle_secrets_errors() {
  log_error "Failed to reload secrets"
}

# Command wrapper for load_secrets function
core_load_secrets_command() {
  log_info "Reloading secrets from SOPS..."
  if refresh_secrets_cache; then
    log_secrets_reload
  else
    handle_secrets_errors
    return 1
  fi
}

# core_auto_command() - Load all environment variables and output export commands for shell sourcing
function core_auto_command() {
  # Disable debug output temporarily to avoid function export errors
  local old_debug="$CPC_DEBUG"
  unset CPC_DEBUG
  
  # Load environment variables from cpc.env and workspace .env
  load_env_vars >/dev/null 2>&1
  
  # Load secrets
  if ! load_secrets_cached >/dev/null 2>&1; then
    return 1
  fi
  
  # Output export commands for shell sourcing
  echo "# CPC Environment Variables - Source this output in your shell"
  echo "# Example: eval \"\$(./cpc auto 2>/dev/null | grep '^export ')\""
  echo ""
  
  # Export secrets (excluding sensitive keys that may cause shell issues)
  [[ -n "${PROXMOX_HOST:-}" ]] && echo "export PROXMOX_HOST='$PROXMOX_HOST'"
  [[ -n "${PROXMOX_USERNAME:-}" ]] && echo "export PROXMOX_USERNAME='$PROXMOX_USERNAME'"
  [[ -n "${VM_USERNAME:-}" ]] && echo "export VM_USERNAME='$VM_USERNAME'"
  [[ -n "${PROXMOX_PASSWORD:-}" ]] && echo "export PROXMOX_PASSWORD='$PROXMOX_PASSWORD'"
  [[ -n "${VM_PASSWORD:-}" ]] && echo "export VM_PASSWORD='$VM_PASSWORD'"
  [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && echo "export AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID'"
  [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] && echo "export AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY'"
  [[ -n "${DOCKER_HUB_USERNAME:-}" ]] && echo "export DOCKER_HUB_USERNAME='$DOCKER_HUB_USERNAME'"
  [[ -n "${DOCKER_HUB_PASSWORD:-}" ]] && echo "export DOCKER_HUB_PASSWORD='$DOCKER_HUB_PASSWORD'"
  [[ -n "${HARBOR_HOSTNAME:-}" ]] && echo "export HARBOR_HOSTNAME='$HARBOR_HOSTNAME'"
  
  # Export environment variables from .env file
  [[ -n "${PRIMARY_DNS_SERVER:-}" ]] && echo "export PRIMARY_DNS_SERVER='$PRIMARY_DNS_SERVER'"
  [[ -n "${SECONDARY_DNS_SERVER:-}" ]] && echo "export SECONDARY_DNS_SERVER='$SECONDARY_DNS_SERVER'"
  [[ -n "${TEMPLATE_VM_ID:-}" ]] && echo "export TEMPLATE_VM_ID='$TEMPLATE_VM_ID'"
  [[ -n "${TEMPLATE_VM_NAME:-}" ]] && echo "export TEMPLATE_VM_NAME='$TEMPLATE_VM_NAME'"
  [[ -n "${IMAGE_NAME:-}" ]] && echo "export IMAGE_NAME='$IMAGE_NAME'"
  [[ -n "${IMAGE_LINK:-}" ]] && echo "export IMAGE_LINK='$IMAGE_LINK'"
  [[ -n "${KUBERNETES_SHORT_VERSION:-}" ]] && echo "export KUBERNETES_SHORT_VERSION='$KUBERNETES_SHORT_VERSION'"
  [[ -n "${KUBERNETES_MEDIUM_VERSION:-}" ]] && echo "export KUBERNETES_MEDIUM_VERSION='$KUBERNETES_MEDIUM_VERSION'"
  [[ -n "${KUBERNETES_LONG_VERSION:-}" ]] && echo "export KUBERNETES_LONG_VERSION='$KUBERNETES_LONG_VERSION'"
  [[ -n "${CNI_PLUGINS_VERSION:-}" ]] && echo "export CNI_PLUGINS_VERSION='$CNI_PLUGINS_VERSION'"
  [[ -n "${CALICO_VERSION:-}" ]] && echo "export CALICO_VERSION='$CALICO_VERSION'"
  [[ -n "${METALLB_VERSION:-}" ]] && echo "export METALLB_VERSION='$METALLB_VERSION'"
  [[ -n "${COREDNS_VERSION:-}" ]] && echo "export COREDNS_VERSION='$COREDNS_VERSION'"
  [[ -n "${METRICS_SERVER_VERSION:-}" ]] && echo "export METRICS_SERVER_VERSION='$METRICS_SERVER_VERSION'"
  [[ -n "${ETCD_VERSION:-}" ]] && echo "export ETCD_VERSION='$ETCD_VERSION'"
  [[ -n "${KUBELET_SERVING_CERT_APPROVER_VERSION:-}" ]] && echo "export KUBELET_SERVING_CERT_APPROVER_VERSION='$KUBELET_SERVING_CERT_APPROVER_VERSION'"
  [[ -n "${LOCAL_PATH_PROVISIONER_VERSION:-}" ]] && echo "export LOCAL_PATH_PROVISIONER_VERSION='$LOCAL_PATH_PROVISIONER_VERSION'"
  [[ -n "${CERT_MANAGER_VERSION:-}" ]] && echo "export CERT_MANAGER_VERSION='$CERT_MANAGER_VERSION'"
  [[ -n "${ARGOCD_VERSION:-}" ]] && echo "export ARGOCD_VERSION='$ARGOCD_VERSION'"
  [[ -n "${INGRESS_NGINX_VERSION:-}" ]] && echo "export INGRESS_NGINX_VERSION='$INGRESS_NGINX_VERSION'"
  [[ -n "${PM_TEMPLATE_ID:-}" ]] && echo "export PM_TEMPLATE_ID='$PM_TEMPLATE_ID'"
  [[ -n "${VM_CPU_CORES:-}" ]] && echo "export VM_CPU_CORES='$VM_CPU_CORES'"
  [[ -n "${VM_MEMORY_DEDICATED:-}" ]] && echo "export VM_MEMORY_DEDICATED='$VM_MEMORY_DEDICATED'"
  [[ -n "${VM_DISK_SIZE:-}" ]] && echo "export VM_DISK_SIZE='$VM_DISK_SIZE'"
  [[ -n "${VM_STARTED:-}" ]] && echo "export VM_STARTED='$VM_STARTED'"
  [[ -n "${VM_DOMAIN:-}" ]] && echo "export VM_DOMAIN='$VM_DOMAIN'"
  [[ -n "${RELEASE_LETTER:-}" ]] && echo "export RELEASE_LETTER='$RELEASE_LETTER'"
  [[ -n "${ADDITIONAL_WORKERS:-}" ]] && echo "export ADDITIONAL_WORKERS='$ADDITIONAL_WORKERS'"
  
  # Restore debug setting
  [[ -n "$old_debug" ]] && export CPC_DEBUG="$old_debug"
}

# core_clear_cache() - Clear all cached files
function core_clear_cache() {
  log_info "Clearing all cached files..."
  
  # Remove cache files
  rm -f /tmp/cpc_secrets_cache 2>/dev/null || true
  rm -f /tmp/cpc_env_cache.sh 2>/dev/null || true
  rm -f /tmp/cpc_status_cache_* 2>/dev/null || true
  rm -f /tmp/cpc_ssh_cache_* 2>/dev/null || true
  rm -f /tmp/cpc_tofu_output_cache_* 2>/dev/null || true
  rm -f /tmp/cpc_workspace_cache 2>/dev/null || true
  
  log_success "Cache cleared successfully"
}
# Export core functions
export -f get_repo_path load_secrets_fresh load_secrets_cached load_env_vars set_workspace_template_vars
export -f get_current_cluster_context set_cluster_context validate_workspace_name
export -f core_setup_cpc core_ctx core_clone_workspace core_delete_workspace core_load_secrets_command core_clear_cache core_auto_command
export -f parse_core_command route_core_command handle_core_errors
export -f determine_script_directory navigate_to_parent_directory validate_repo_path
export -f check_cache_freshness decrypt_secrets_file load_secrets_into_environment update_cache_timestamp
export -f locate_secrets_file decrypt_secrets_directly export_secrets_variables validate_secrets_integrity
export -f locate_env_file parse_env_file export_env_variables validate_env_setup
export -f extract_template_values validate_template_variables export_template_vars
export -f cpc_core

log_debug "Module 00_core.sh loaded successfully"
