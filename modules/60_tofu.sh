#!/bin/bash
# modules/60_tofu.sh - Terraform/OpenTofu management module
# Part of the modular CPC architecture

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

# Module: Terraform/OpenTofu functionality
log_debug "Loading module: 60_tofu.sh - Terraform/OpenTofu management"

# Function to handle all Terraform/OpenTofu commands
function cpc_tofu() {
  local command="$1"
  shift

  case "$command" in
  deploy)
    tofu_deploy "$@"
    ;;
  workspace)
    # Прямая обработка команд workspace
    local tf_dir
    tf_dir="$(get_repo_path)/$TERRAFORM_DIR"
    pushd "$tf_dir" >/dev/null || return 1
    log_command "tofu workspace $*"
    tofu workspace "$@"
    local exit_code=$?
    popd >/dev/null
    return $exit_code
    ;;
  start-vms)
    tofu_start_vms "$@"
    ;;
  stop-vms)
    tofu_stop_vms "$@"
    ;;
  generate-hostnames | gen_hostnames)
    tofu_generate_hostnames "$@"
    ;;
  cluster-info)
    tofu_show_cluster_info "$@"
    ;;
  *)
    log_error "Unknown tofu command: $command"
    return 1
    ;;
  esac
}

# Deploy command - runs OpenTofu/Terraform commands in context

function tofu_deploy() {
  if [[ "$1" == "-h" || "$1" == "--help" ]] || [[ $# -eq 0 ]]; then
    echo "Usage: cpc deploy <tofu_cmd> [options]"
    echo ""
    echo "Run any OpenTofu/Terraform command in the current cpc context."
    echo ""
    echo "Common commands:"
    echo "  plan       Generate and show an execution plan"
    echo "  apply      Build or change infrastructure"
    echo "  destroy    Destroy infrastructure"
    echo "  output     Show output values"
    echo "  init       Initialize a working directory"
    echo "  validate   Validate the configuration files"
    echo "  refresh    Update state file against real resources"
    echo ""
    echo "Examples:"
    echo "  cpc deploy plan"
    echo "  cpc deploy apply -auto-approve"
    echo "  cpc deploy destroy -auto-approve"
    echo "  cpc deploy output k8s_node_ips"
    echo ""
    echo "The command will:"
    echo "  - Load workspace environment variables"
    echo "  - Set appropriate Terraform variables"
    echo "  - Select the correct workspace"
    echo "  - Generate hostname configurations (for plan/apply)"
    echo "  - Execute the OpenTofu command with context-specific tfvars"
    return 0
  fi

  check_secrets_loaded
  current_ctx=$(get_current_cluster_context)

  tf_dir="$REPO_PATH/terraform"
  tfvars_file="$tf_dir/environments/${current_ctx}.tfvars"

  log_info "Preparing to run 'tofu $*' for context '$current_ctx' in $tf_dir..."

  # Load RELEASE_LETTER from workspace environment file if it exists
  env_file="$REPO_PATH/envs/$current_ctx.env"
  if [ -f "$env_file" ]; then
    RELEASE_LETTER=$(grep -E "^RELEASE_LETTER=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$RELEASE_LETTER" ]; then
      export TF_VAR_release_letter="$RELEASE_LETTER"
      log_info "Using RELEASE_LETTER='$RELEASE_LETTER' from workspace environment file"
    fi

    ADDITIONAL_WORKERS=$(grep -E "^ADDITIONAL_WORKERS=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$ADDITIONAL_WORKERS" ]; then
      export TF_VAR_additional_workers="$ADDITIONAL_WORKERS"
      log_info "Using ADDITIONAL_WORKERS='$ADDITIONAL_WORKERS' from workspace environment file"
    fi

    ADDITIONAL_CONTROLPLANES=$(grep -E "^ADDITIONAL_CONTROLPLANES=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$ADDITIONAL_CONTROLPLANES" ]; then
      export TF_VAR_additional_controlplanes="$ADDITIONAL_CONTROLPLANES"
      log_info "Using ADDITIONAL_CONTROLPLANES='$ADDITIONAL_CONTROLPLANES' from workspace environment file"
    fi

    # Static IP configuration variables
    STATIC_IP_BASE=$(grep -E "^STATIC_IP_BASE=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$STATIC_IP_BASE" ]; then
      export TF_VAR_static_ip_base="$STATIC_IP_BASE"
      log_info "Using STATIC_IP_BASE='$STATIC_IP_BASE' from workspace environment file"
    fi

    STATIC_IP_GATEWAY=$(grep -E "^STATIC_IP_GATEWAY=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$STATIC_IP_GATEWAY" ]; then
      export TF_VAR_static_ip_gateway="$STATIC_IP_GATEWAY"
      log_info "Using STATIC_IP_GATEWAY='$STATIC_IP_GATEWAY' from workspace environment file"
    fi

    STATIC_IP_START=$(grep -E "^STATIC_IP_START=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$STATIC_IP_START" ]; then
      export TF_VAR_static_ip_start="$STATIC_IP_START"
      log_info "Using STATIC_IP_START='$STATIC_IP_START' from workspace environment file"
    fi

    # Advanced IP block system variables
    NETWORK_CIDR=$(grep -E "^NETWORK_CIDR=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$NETWORK_CIDR" ]; then
      export TF_VAR_network_cidr="$NETWORK_CIDR"
      log_info "Using NETWORK_CIDR='$NETWORK_CIDR' from workspace environment file"
    fi

    WORKSPACE_IP_BLOCK_SIZE=$(grep -E "^WORKSPACE_IP_BLOCK_SIZE=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$WORKSPACE_IP_BLOCK_SIZE" ]; then
      export TF_VAR_workspace_ip_block_size="$WORKSPACE_IP_BLOCK_SIZE"
      log_info "Using WORKSPACE_IP_BLOCK_SIZE='$WORKSPACE_IP_BLOCK_SIZE' from workspace environment file"
    fi
  fi

  pushd "$tf_dir" >/dev/null || {
    log_error "Failed to change to directory $tf_dir"
    exit 1
  }

  selected_workspace=$(tofu workspace show)
  if [ "$selected_workspace" != "$current_ctx" ]; then
    log_validation "Warning: Current Tofu workspace ('$selected_workspace') does not match cpc context ('$current_ctx')."
    log_validation "Attempting to select workspace '$current_ctx'..."
    tofu workspace select "$current_ctx"
    if [ $? -ne 0 ]; then
      log_error "Error selecting Tofu workspace '$current_ctx'. Please check your Tofu setup."
      popd >/dev/null
      exit 1
    fi
  fi

  tofu_subcommand="$1"
  shift # Remove subcommand, rest are its arguments

  final_tofu_cmd_array=(tofu "$tofu_subcommand")

  # Generate node hostname configurations for Proxmox if applying or planning
  if [ "$tofu_subcommand" = "apply" ] || [ "$tofu_subcommand" = "plan" ]; then
    log_info "Generating node hostname configurations..."
    if [ -x "$REPO_PATH/scripts/generate_node_hostnames.sh" ]; then
      pushd "$REPO_PATH/scripts" >/dev/null
      ./generate_node_hostnames.sh
      HOSTNAME_SCRIPT_STATUS=$?
      popd >/dev/null

      if [ $HOSTNAME_SCRIPT_STATUS -ne 0 ]; then
        log_validation "Warning: Hostname generation script returned non-zero status. Some VMs may have incorrect hostnames."
      else
        log_success "Hostname configurations generated successfully."
      fi
    else
      log_validation "Warning: Hostname generation script not found or not executable. Some VMs may have incorrect hostnames."
    fi
  fi

  # Check if the subcommand is one that accepts -var-file and -var
  case "$tofu_subcommand" in
  apply | plan | destroy | import | console)
    if [ -f "$tfvars_file" ]; then
      final_tofu_cmd_array+=("-var-file=$tfvars_file")
      log_info "Using tfvars file: $tfvars_file"
    else
      log_validation "Warning: No specific tfvars file found for context '$current_ctx' at $tfvars_file. Using defaults if applicable."
    fi

    # --- ИЗМЕНЕНИЕ ЗДЕСЬ: Переменные DNS добавляются только для нужных команд ---
    local dns_servers_list="[]"
    if [[ -n "$PRIMARY_DNS_SERVER" ]]; then
      # Создаём JSON-массив из переменных DNS
      dns_servers_list=$(jq -n \
        --arg primary "$PRIMARY_DNS_SERVER" \
        --arg secondary "$SECONDARY_DNS_SERVER" \
        '[ $primary, $secondary | select(. != null and . != "") ]')
    fi
    # Add the variable to the tofu command array
    final_tofu_cmd_array+=("-var" "dns_servers=${dns_servers_list}")
    ;;
  esac

  # Append remaining user-provided arguments
  if [[ $# -gt 0 ]]; then
    final_tofu_cmd_array+=("$@")
  fi

  log_info "Executing: ${final_tofu_cmd_array[*]}"
  "${final_tofu_cmd_array[@]}"
  cmd_exit_code=$?

  popd >/dev/null || exit 1

  if [ $cmd_exit_code -ne 0 ]; then
    log_error "'${final_tofu_cmd_array[*]}' failed with exit code $cmd_exit_code."
    exit 1
  fi
  log_success "'${final_tofu_cmd_array[*]}' completed successfully for context '$current_ctx'."
}

# Start VMs in current context
function tofu_start_vms() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: cpc start-vms"
    echo ""
    echo "Start all VMs in the current cpc context by running 'tofu apply' with vm_started=true."
    echo ""
    echo "This command will:"
    echo "  - Set vm_started=true for all VMs in the workspace"
    echo "  - Apply the changes automatically"
    echo "  - Start all VMs defined in the current context"
    return 0
  fi

  current_ctx=$(get_current_cluster_context)
  log_info "Starting VMs for context '$current_ctx'..."

  # Call the deploy command internally to start VMs
  tofu_deploy apply -var="vm_started=true" -auto-approve
  if [ $? -ne 0 ]; then
    log_error "Error starting VMs for context '$current_ctx'."
    exit 1
  fi
  log_success "VMs in context '$current_ctx' should now be starting."
}

# Stop VMs in current context
function tofu_stop_vms() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: cpc stop-vms"
    echo ""
    echo "Stop all VMs in the current cpc context by running 'tofu apply' with vm_started=false."
    echo ""
    echo "This command will:"
    echo "  - Set vm_started=false for all VMs in the workspace"
    echo "  - Apply the changes automatically"
    echo "  - Stop all VMs defined in the current context"
    return 0
  fi

  current_ctx=$(get_current_cluster_context)
  log_info "Stopping VMs for context '$current_ctx'..."

  # Ask for confirmation before stopping VMs
  read -r -p "Are you sure you want to stop all VMs in context '$current_ctx'? [y/N] " response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Operation cancelled."
    return 0
  fi

  # Call the deploy command internally to stop VMs
  tofu_deploy apply -var="vm_started=false" -auto-approve
  if [ $? -ne 0 ]; then
    log_error "Error stopping VMs for context '$current_ctx'."
    exit 1
  fi
  log_success "VMs in context '$current_ctx' should now be stopping."
}

# Display cluster information in table or JSON format
function tofu_show_cluster_info() {
  local format="table" # default format

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
    -h | --help)
      tofu_cluster_info_help
      return 0
      ;;
    --format)
      format="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      return 1
      ;;
    esac
  done

  if [[ "$format" != "table" && "$format" != "json" ]]; then
    log_error "Invalid format '$format'. Supported formats: table, json"
    return 1
  fi

  local current_ctx tf_dir
  current_ctx=$(get_current_cluster_context) || return 1
  tf_dir="$REPO_PATH/terraform"

  if [ "$format" != "json" ]; then
    log_info "Getting cluster information for context '$current_ctx'..."
  fi

  # Export AWS credentials for terraform backend
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
  export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

  # Load workspace environment variables for proper Terraform context
  tofu_load_workspace_env_vars "$current_ctx"

  pushd "$tf_dir" >/dev/null || {
    log_error "Failed to change to terraform directory"
    return 1
  }

  # Ensure we're in the correct workspace
  if ! tofu workspace select "$current_ctx" &>/dev/null; then
    log_error "Failed to select Tofu workspace '$current_ctx'"
    popd >/dev/null
    return 1
  fi

  # Get the simplified cluster summary
  local cluster_summary
  cluster_summary=$(tofu output -json cluster_summary 2>/dev/null)
  if [ $? -eq 0 ] && [ "$cluster_summary" != "null" ]; then
    if [ "$format" = "json" ]; then
      # Output raw JSON - check if it has .value or is direct
      if echo "$cluster_summary" | jq -e '.value' >/dev/null 2>&1; then
        echo "$cluster_summary" | jq '.value'
      else
        echo "$cluster_summary"
      fi
    else
      # Table format - handle both .value and direct JSON
      local json_data
      if echo "$cluster_summary" | jq -e '.value' >/dev/null 2>&1; then
        json_data=$(echo "$cluster_summary" | jq '.value')
      else
        json_data="$cluster_summary"
      fi

      echo ""
      echo -e "${GREEN}=== Cluster Information ===${ENDCOLOR}"
      echo ""
      printf "%-25s %-15s %-20s %s\n" "NODE" "VM_ID" "HOSTNAME" "IP"
      printf "%-25s %-15s %-20s %s\n" "----" "-----" "--------" "--"

      # Parse JSON and display in a table format
      echo "$json_data" | jq -r 'to_entries[] | "\(.key) \(.value.VM_ID) \(.value.hostname) \(.value.IP)"' |
        while read -r node vm_id hostname ip; do
          printf "%-25s %-15s %-20s %s\n" "$node" "$vm_id" "$hostname" "$ip"
        done
      echo ""
    fi
  else
    log_error "Failed to get cluster summary. Make sure VMs are deployed."
    popd >/dev/null
    return 1
  fi

  popd >/dev/null
}

# Load workspace environment variables for Terraform context
function tofu_load_workspace_env_vars() {
  local current_ctx="$1"
  local env_file="$REPO_PATH/envs/$current_ctx.env"

  if [ ! -f "$env_file" ]; then
    return 0
  fi

  # Load workspace-specific variables
  local var_name var_value
  while IFS='=' read -r var_name var_value; do
    # Skip comments and empty lines
    [[ "$var_name" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$var_name" ]] && continue

    # Remove quotes from value
    var_value=$(echo "$var_value" | tr -d '"')

    case "$var_name" in
    RELEASE_LETTER)
      [ -n "$var_value" ] && export TF_VAR_release_letter="$var_value"
      ;;
    ADDITIONAL_WORKERS)
      [ -n "$var_value" ] && export TF_VAR_additional_workers="$var_value"
      ;;
    ADDITIONAL_CONTROLPLANES)
      [ -n "$var_value" ] && export TF_VAR_additional_controlplanes="$var_value"
      ;;
    STATIC_IP_BASE)
      [ -n "$var_value" ] && export TF_VAR_static_ip_base="$var_value"
      ;;
    STATIC_IP_GATEWAY)
      [ -n "$var_value" ] && export TF_VAR_static_ip_gateway="$var_value"
      ;;
    STATIC_IP_START)
      [ -n "$var_value" ] && export TF_VAR_static_ip_start="$var_value"
      ;;
    NETWORK_CIDR)
      [ -n "$var_value" ] && export TF_VAR_network_cidr="$var_value"
      ;;
    WORKSPACE_IP_BLOCK_SIZE)
      [ -n "$var_value" ] && export TF_VAR_workspace_ip_block_size="$var_value"
      ;;
    esac
  done < <(grep -E "^[A-Z_]+=" "$env_file" || true)
}

# Display help for cluster-info command
function tofu_cluster_info_help() {
  echo "Usage: cpc cluster-info [--format <format>]"
  echo ""
  echo "Display simplified cluster information showing only essential details:"
  echo "  - VM_ID: Proxmox VM identifier"
  echo "  - hostname: VM hostname (node name)"
  echo "  - IP: VM IP address"
  echo ""
  echo "Options:"
  echo "  --format <format>  Output format: 'table' (default) or 'json'"
  echo ""
  echo "This command provides a clean, concise view of your cluster infrastructure"
  echo "without the detailed debug information from 'cpc deploy output'."
}

function tofu_update_node_info() {
  local summary_json="$1"

  if [[ -z "$summary_json" || "$summary_json" == "null" ]]; then
    log_error "Received empty or null JSON in tofu_update_node_info."
    return 1
  fi

  # Разбираем JSON и экспортируем переменные
  TOFU_NODE_NAMES=($(echo "$summary_json" | jq -r 'keys_unsorted[]'))
  TOFU_NODE_IPS=($(echo "$summary_json" | jq -r '.[].IP'))
  TOFU_NODE_HOSTNAMES=($(echo "$summary_json" | jq -r '.[].hostname'))
  TOFU_NODE_VM_IDS=($(echo "$summary_json" | jq -r '.[].VM_ID'))

  if [ ${#TOFU_NODE_NAMES[@]} -eq 0 ]; then
    log_error "Parsed zero nodes from Tofu output."
    return 1
  fi

  return 0
}
export -f tofu_update_node_info

log_debug "Module 60_tofu.sh loaded successfully"
