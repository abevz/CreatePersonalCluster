#!/bin/bash
# =============================================================================
# CPC Core Module (00_core.sh)
# =============================================================================
# Core functionality: context management, secrets, workspaces, setup

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
  *)
    log_error "Unknown core command: ${1:-}"
    log_info "Available commands: setup-cpc, ctx, clone-workspace, delete-workspace, load_secrets"
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

# Load secrets from SOPS
load_secrets() {
  local repo_root
  repo_root=$(get_repo_path)
  local secrets_file="$repo_root/terraform/secrets.sops.yaml"

  if [ ! -f "$secrets_file" ]; then
    log_error "secrets.sops.yaml not found at $secrets_file"
    return 1
  fi

  # Check if sops is installed
  if ! command -v sops &>/dev/null; then
    log_error "'sops' is required but not installed. Please install it before proceeding."
    return 1
  fi

  # Check if jq is installed
  if ! command -v jq &>/dev/null; then
    log_error "'jq' is required but not installed. Please install it before proceeding."
    return 1
  fi

  log_debug "Loading secrets from secrets.sops.yaml..."

  # Export sensitive variables from SOPS
  export PROXMOX_HOST
  export PROXMOX_USERNAME
  export PROXMOX_PASSWORD
  export VM_USERNAME
  export VM_PASSWORD
  export VM_SSH_KEY
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_DEFAULT_REGION

  # Load secrets using sops, convert to JSON, then parse with jq
  local secrets_json
  secrets_json=$(sops -d "$secrets_file" 2>/dev/null | python3 -c "import sys, yaml, json; json.dump(yaml.safe_load(sys.stdin), sys.stdout)")

  if [ $? -ne 0 ]; then
    log_error "Failed to decrypt secrets.sops.yaml. Check your SOPS configuration."
    return 1
  fi

  # Parse secrets from JSON
  PROXMOX_HOST=$(echo "$secrets_json" | jq -r '.virtual_environment_endpoint' | sed 's|https://||' | sed 's|:8006/api2/json||')
  PROXMOX_USERNAME=$(echo "$secrets_json" | jq -r '.proxmox_username')
  PROXMOX_PASSWORD=$(echo "$secrets_json" | jq -r '.virtual_environment_password')
  VM_USERNAME=$(echo "$secrets_json" | jq -r '.vm_username')
  VM_PASSWORD=$(echo "$secrets_json" | jq -r '.vm_password')
  VM_SSH_KEY=$(echo "$secrets_json" | jq -r '.vm_ssh_keys[0]')

  # Parse MinIO/S3 credentials for Terraform backend
  AWS_ACCESS_KEY_ID=$(echo "$secrets_json" | jq -r '.minio_access_key')
  AWS_SECRET_ACCESS_KEY=$(echo "$secrets_json" | jq -r '.minio_secret_key')
  AWS_DEFAULT_REGION="us-east-1" # Set default region for MinIO

  # Verify that all required secrets were loaded
  if [ -z "$PROXMOX_HOST" ] || [ -z "$PROXMOX_USERNAME" ] || [ -z "$PROXMOX_PASSWORD" ] || [ -z "$VM_USERNAME" ] || [ -z "$VM_PASSWORD" ] || [ -z "$VM_SSH_KEY" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    log_error "Failed to load one or more required secrets from secrets.sops.yaml"
    log_info "Required secrets: PROXMOX_HOST, PROXMOX_USERNAME, PROXMOX_PASSWORD, VM_USERNAME, VM_PASSWORD, VM_SSH_KEY, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    return 1
  fi

  log_debug "Successfully loaded secrets (PROXMOX_HOST: $PROXMOX_HOST, VM_USERNAME: $VM_USERNAME)"
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
    cat "$CPC_CONTEXT_FILE"
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

  echo "$context" >"$CPC_CONTEXT_FILE"
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
  local cluster_context_file="$HOME/.config/cpc/cluster_context"
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

  # --- Проверки ---
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

  # --- Сохраняем текущий контекст, чтобы вернуться к нему в конце ---
  local original_context
  original_context=$(get_current_cluster_context)

  # --- Создаем резервную копию locals.tf для надежного отката ---
  cp "$locals_tf_file" "$locals_tf_backup_file"

  log_step "Cloning workspace '$source_workspace' to '$new_workspace_name'..."

  # 1. Создаем и модифицируем файлы
  cp "$source_env_file" "$new_env_file"
  sed -i "s/^RELEASE_LETTER=.*/RELEASE_LETTER=$release_letter/" "$new_env_file"
  log_info "New environment file created: $new_env_file"

  local template_var_name="pm_template_${source_workspace}_id"
  local new_entry="  \"${new_workspace_name}\" = var.${template_var_name}"
  sed -i "/template_vm_ids = {/a\\$new_entry" "$locals_tf_file"

  # --- ИСПРАВЛЕННЫЙ БЛОК ---
  log_info "Updating workspace_ip_map with the first available IP index..."

  # Extract all currently used IDs from the map, sort them uniquely
  local used_ids
  used_ids=$(grep -A 20 "workspace_ip_map = {" "$locals_tf_file" | grep -oP '=\s*\K[0-9]+' | sort -n | uniq)

  local next_id=1
  if [ -n "$used_ids" ]; then
    # Loop through the sorted list of used IDs to find the first gap
    for id in $used_ids; do
      if [ "$id" -eq "$next_id" ]; then
        # This ID is taken, check the next one
        next_id=$((next_id + 1))
      else
        # We found a gap. The current $next_id is free.
        break
      fi
    done
  fi
  # If no gaps were found, next_id will be one greater than the max used ID.

  # Add the new workspace to the map using the found available ID
  sed -i "/workspace_ip_map = {/a \\    \"$new_workspace_name\"      = ${next_id}  # Auto-added by clone-workspace" "$locals_tf_file"
  log_info "Added workspace_ip_map entry: \"$new_workspace_name\" = ${next_id}"

  # 2. Переключаем контекст на новый воркспейс
  set_cluster_context "$new_workspace_name"

  # 3. Создаем новый воркспейс в Terraform
  log_step "Creating Terraform workspace '$new_workspace_name'..."
  if ! cpc_tofu workspace new "$new_workspace_name"; then
    log_error "Failed to create Terraform workspace '$new_workspace_name'."
    log_error "Reverting changes..."
    # --- Откат изменений в случае ошибки ---
    rm -f "$new_env_file"
    mv "$locals_tf_backup_file" "$locals_tf_file"
    set_cluster_context "$original_context" # Возвращаем старый контекст
    log_warning "Changes have been reverted."
    return 1
  fi

  # 4. Успешное завершение и очистка
  rm -f "$locals_tf_backup_file" # Удаляем бэкап, так как он больше не нужен
  log_success "Successfully cloned workspace '$source_workspace' to '$new_workspace_name'."
  log_info "Switched context to '$new_workspace_name'."

}

# (в modules/00_core.sh)
# (в modules/00_core.sh)

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

  # 1. Переключаемся в контекст, который будем удалять, для уничтожения ресурсов
  set_cluster_context "$workspace_name"

  # 2. Уничтожаем все ресурсы
  log_step "Destroying all resources in workspace '$workspace_name'..."
  if ! cpc_tofu deploy destroy; then
    log_error "Failed to destroy resources for workspace '$workspace_name'."
    log_error "Workspace deletion aborted. Please destroy resources manually before trying again."
    set_cluster_context "$original_context" # Возвращаем исходный контекст в случае ошибки
    return 1
  fi
  log_success "All resources for '$workspace_name' have been destroyed."

  # 3. Переключаемся в БЕЗОПАСНЫЙ контекст ПЕРЕД удалением.
  #    Если мы удаляем не тот контекст, в котором были, возвращаемся в него.
  #    Иначе - переключаемся в 'ubuntu' (или 'default', если 'ubuntu' нет).
  local safe_context="ubuntu" # 'ubuntu' - хороший кандидат по умолчанию
  if [[ "$original_context" != "$workspace_name" ]]; then
    safe_context="$original_context"
  fi

  log_step "Switching to safe context ('$safe_context') to perform deletion..."
  # Используем твою же функцию для переключения
  if ! core_ctx "$safe_context"; then
    log_error "Could not switch to a safe workspace ('$safe_context'). Aborting workspace deletion."
    log_warning "Resources were destroyed, but the empty workspace '$workspace_name' remains."
    return 1
  fi

  # 4. Теперь, находясь в безопасном воркспейсе, удаляем целевой
  log_step "Deleting Terraform workspace '$workspace_name' from the backend..."
  if ! cpc_tofu workspace delete "$workspace_name"; then
    log_error "Failed to delete the Terraform workspace '$workspace_name' from backend."
  else
    log_success "Terraform workspace '$workspace_name' has been deleted."
  fi

  # 5. Подчищаем локальные файлы конфигурации
  log_step "Removing local configuration for '$workspace_name'..."
  if [[ -f "$env_file" ]]; then
    rm -f "$env_file"
    log_info "Removed environment file: $env_file."
  fi

  if grep -q "\"${workspace_name}\"" "$locals_tf_file"; then
    sed -i "/\"${workspace_name}\"/d" "$locals_tf_file"
    log_info "Removed entries for '$workspace_name' from locals.tf."
  fi

  log_success "Workspace '$workspace_name' has been successfully deleted."
}

# Command wrapper for load_secrets function
core_load_secrets_command() {
  log_step "Loading secrets from SOPS..."
  load_secrets
  log_success "Secrets loaded successfully!"
  log_info "Available variables:"
  log_info "  PROXMOX_HOST: $PROXMOX_HOST"
  log_info "  PROXMOX_USERNAME: $PROXMOX_USERNAME"
  log_info "  VM_USERNAME: $VM_USERNAME"
  log_info "  VM_SSH_KEY: ${VM_SSH_KEY:0:20}..."
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
  # Выводим JSON для захвата
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

  # Извлекаем строку с инвентарем из полного JSON
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
  log_debug "Creating temporary static Ansible inventory from Terraform output..."

  local raw_output
  raw_output=$("$REPO_PATH/cpc" deploy output -json 2>/dev/null)
  if [[ $? -ne 0 || -z "$raw_output" ]]; then
    log_error "Command 'cpc deploy output -json' failed or returned empty."
    return 1
  fi

  local all_tofu_outputs_json
  all_tofu_outputs_json=$(echo "$raw_output" | sed -n '/^{$/,/^}$/p')
  if [[ -z "$all_tofu_outputs_json" ]]; then
    log_error "Failed to extract JSON from Terraform output."
    return 1
  fi

  local dynamic_inventory_json
  # Сначала извлекаем JSON-строку, а затем парсим ее как JSON (fromjson)
  dynamic_inventory_json=$(echo "$all_tofu_outputs_json" | jq -r '.ansible_inventory.value | fromjson')
  if [[ -z "$dynamic_inventory_json" || "$dynamic_inventory_json" == "null" ]]; then
    log_error "Ansible inventory data is empty or invalid in Terraform outputs."
    return 1
  fi

  local temp_inventory_file
  temp_inventory_file=$(mktemp /tmp/cpc_inventory.XXXXXX.json)

  # Преобразуем динамический JSON в статический, который Ansible поймет
  jq '
      . as $inv |
      {
        "all": {
          "children": {
            "control_plane": {
              "hosts": ($inv.control_plane.hosts // []) | map({(.): $inv._meta.hostvars[.]}) | add
            },
            "workers": {
              "hosts": ($inv.workers.hosts // []) | map({(.): $inv._meta.hostvars[.]}) | add
            }
          }
        }
      }
    ' <<<"$dynamic_inventory_json" >"$temp_inventory_file"

  if [[ $? -ne 0 ]]; then
    log_error "Failed to create static inventory file using jq."
    rm -f "$temp_inventory_file"
    return 1
  fi

  log_debug "Temporary static inventory created at $temp_inventory_file"
  echo "$temp_inventory_file"
  return 0
}

# Export core functions
export -f get_repo_path load_secrets load_env_vars set_workspace_template_vars
export -f get_current_cluster_context set_cluster_context validate_workspace_name
export -f cpc_setup cpc_core
export -f core_setup_cpc core_ctx core_clone_workspace core_delete_workspace core_load_secrets_command
export -f _get_terraform_outputs_json _get_hostname_by_ip ansible_create_temp_inventory
