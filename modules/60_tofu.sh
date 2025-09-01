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
    # Initialize recovery for workspace operations
    recovery_checkpoint "tofu_workspace_start" "Starting workspace operation"

    # Direct processing of workspace commands
    local tf_dir
    tf_dir="$(get_repo_path)/$TERRAFORM_DIR"

    if ! error_validate_directory "$tf_dir" "Terraform directory not found: $tf_dir"; then
      return 1
    fi

    if ! pushd "$tf_dir" >/dev/null; then
      error_handle "$ERROR_EXECUTION" "Failed to change to terraform directory" "$SEVERITY_HIGH" "abort"
      return 1
    fi

    log_command "tofu workspace $*"
    if ! tofu workspace "$@"; then
      error_handle "$ERROR_EXECUTION" "Tofu workspace command failed" "$SEVERITY_HIGH" "abort"
      popd >/dev/null
      return 1
    fi

    local exit_code=$?
    if ! popd >/dev/null; then
      error_handle "$ERROR_EXECUTION" "Failed to return to original directory" "$SEVERITY_HIGH" "abort"
      return 1
    fi
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
    error_handle "$ERROR_INPUT" "Unknown tofu command: $command" "$SEVERITY_LOW" "abort"
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

  # Initialize recovery for this operation
  recovery_checkpoint "tofu_deploy_start" "Starting Terraform deployment operation"

  # Validate secrets are loaded
  if ! check_secrets_loaded; then
    error_handle "$ERROR_CONFIG" "Failed to load secrets. Aborting Terraform deployment." "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  # Get current context with error handling
  if ! current_ctx=$(get_current_cluster_context); then
    error_handle "$ERROR_CONFIG" "Failed to get current cluster context" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  tf_dir="$REPO_PATH/terraform"
  tfvars_file="$tf_dir/environments/${current_ctx}.tfvars"

  log_info "Preparing to run 'tofu $*' for context '$current_ctx' in $tf_dir..."

  # Validate Terraform directory exists
  if ! error_validate_directory "$tf_dir" "Terraform directory not found: $tf_dir"; then
    return 1
  fi

  # Load environment variables with error handling
  env_file="$REPO_PATH/envs/$current_ctx.env"
  if [ -f "$env_file" ]; then
    # Load RELEASE_LETTER
    RELEASE_LETTER=$(grep -E "^RELEASE_LETTER=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$RELEASE_LETTER" ]; then
      export TF_VAR_release_letter="$RELEASE_LETTER"
      log_info "Using RELEASE_LETTER='$RELEASE_LETTER' from workspace environment file"
    fi

    # Load ADDITIONAL_WORKERS
    ADDITIONAL_WORKERS=$(grep -E "^ADDITIONAL_WORKERS=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$ADDITIONAL_WORKERS" ]; then
      export TF_VAR_additional_workers="$ADDITIONAL_WORKERS"
      log_info "Using ADDITIONAL_WORKERS='$ADDITIONAL_WORKERS' from workspace environment file"
    fi

    # Load ADDITIONAL_CONTROLPLANES
    ADDITIONAL_CONTROLPLANES=$(grep -E "^ADDITIONAL_CONTROLPLANES=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$ADDITIONAL_CONTROLPLANES" ]; then
      export TF_VAR_additional_controlplanes="$ADDITIONAL_CONTROLPLANES"
      log_info "Using ADDITIONAL_CONTROLPLANES='$ADDITIONAL_CONTROLPLANES' from workspace environment file"
    fi

    # Load static IP configuration
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

    # Load advanced IP block system variables
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

  # Change to terraform directory with error handling
  if ! pushd "$tf_dir" >/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to change to directory $tf_dir" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  selected_workspace=$(tofu workspace show)
  if [ "$selected_workspace" != "$current_ctx" ]; then
    log_validation "Warning: Current Tofu workspace ('$selected_workspace') does not match cpc context ('$current_ctx')."
    log_validation "Attempting to select workspace '$current_ctx'..."
    if ! tofu workspace select "$current_ctx"; then
      error_handle "$ERROR_EXECUTION" "Failed to select Tofu workspace '$current_ctx'" "$SEVERITY_HIGH" "retry"
      # Retry once more
      if ! tofu workspace select "$current_ctx"; then
        error_handle "$ERROR_EXECUTION" "Failed to select Tofu workspace '$current_ctx' after retry" "$SEVERITY_CRITICAL" "abort"
        popd >/dev/null || exit 1
        return 1
      fi
    fi
  fi

  tofu_subcommand="$1"
  shift # Remove subcommand, rest are its arguments

  final_tofu_cmd_array=(tofu "$tofu_subcommand")

  # Generate node hostname configurations for Proxmox if applying or planning
  if [ "$tofu_subcommand" = "apply" ] || [ "$tofu_subcommand" = "plan" ]; then
    log_info "Generating node hostname configurations..."
    if [ -x "$REPO_PATH/scripts/generate_node_hostnames.sh" ]; then
      pushd "$REPO_PATH/scripts" >/dev/null || {
        error_handle "$ERROR_EXECUTION" "Failed to change to scripts directory" "$SEVERITY_HIGH" "abort"
        popd >/dev/null || exit 1
        return 1
      }
      if ! ./generate_node_hostnames.sh; then
        error_handle "$ERROR_EXECUTION" "Hostname generation script failed" "$SEVERITY_MEDIUM" "continue"
        log_validation "Warning: Hostname generation script returned non-zero status. Some VMs may have incorrect hostnames."
      else
        log_success "Hostname configurations generated successfully."
      fi
      popd >/dev/null || {
        error_handle "$ERROR_EXECUTION" "Failed to return to terraform directory" "$SEVERITY_HIGH" "abort"
        return 1
      }
    else
      error_handle "$ERROR_CONFIG" "Hostname generation script not found or not executable" "$SEVERITY_LOW" "continue"
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
      error_handle "$ERROR_CONFIG" "No specific tfvars file found for context '$current_ctx'" "$SEVERITY_LOW" "continue"
      log_validation "Warning: No specific tfvars file found for context '$current_ctx' at $tfvars_file. Using defaults if applicable."
    fi

    # --- CHANGE HERE: DNS variables are added only for necessary commands ---
    local dns_servers_list="[]"
    if [[ -n "$PRIMARY_DNS_SERVER" ]]; then
      # Create JSON array from DNS variables
      if ! dns_servers_list=$(jq -n \
        --arg primary "$PRIMARY_DNS_SERVER" \
        --arg secondary "$SECONDARY_DNS_SERVER" \
        '[ $primary, $secondary | select(. != null and . != "") ]' 2>/dev/null); then
        error_handle "$ERROR_EXECUTION" "Failed to create DNS servers JSON array" "$SEVERITY_MEDIUM" "continue"
        dns_servers_list="[]"
      fi
    fi
    # Add variable to tofu command array
    final_tofu_cmd_array+=("-var" "dns_servers=${dns_servers_list}")
    
    # Add release_letter variable if it's set
    if [ -n "$RELEASE_LETTER" ]; then
      final_tofu_cmd_array+=("-var" "release_letter=$RELEASE_LETTER")
      log_info "Using release_letter='$RELEASE_LETTER' for hostname generation"
    fi
    ;;
  esac

  # Append remaining user-provided arguments
  if [[ $# -gt 0 ]]; then
    final_tofu_cmd_array+=("$@")
  fi

  log_info "Executing: ${final_tofu_cmd_array[*]}"

  # Execute tofu command with retry logic
  local max_retries=2
  local retry_count=0
  local cmd_exit_code=1
  local user_cancelled=false
  local cmd_timeout=300  # 5 minutes timeout for interactive commands

  while [ $retry_count -le $max_retries ]; do
    if [ $retry_count -gt 0 ]; then
      log_info "Retrying tofu command (attempt $((retry_count + 1))/$((max_retries + 1)))..."
      sleep 2
    fi

    # Execute command with timeout to prevent hanging
    local cmd_output
    if ! cmd_output=$(timeout "$cmd_timeout" "${final_tofu_cmd_array[@]}" 2>&1); then
      cmd_exit_code=$?
      # Check if command was killed by timeout
      if [ $cmd_exit_code -eq 124 ]; then
        log_warning "Tofu command timed out after ${cmd_timeout} seconds"
        user_cancelled=true
        break
      fi
    else
      cmd_exit_code=$?
    fi

    # Check if user cancelled the operation (only if command completed normally)
    if [ $cmd_exit_code -ne 124 ] && echo "$cmd_output" | grep -q "Apply cancelled\|cancelled\|no.*accepted\|Enter a value.*no" || [ $cmd_exit_code -eq 130 ]; then
      user_cancelled=true
      log_info "User cancelled the operation. Not retrying."
      break
    fi

    if [ $cmd_exit_code -eq 0 ]; then
      break
    fi

    # Special handling for 'plan' command - don't retry on exit code 1
    if [ "$tofu_subcommand" = "plan" ] && [ $cmd_exit_code -eq 1 ]; then
      log_info "Tofu plan completed with exit code 1 (this may be normal for plan operations)"
      break
    fi

    retry_count=$((retry_count + 1))

    if [ $retry_count -le $max_retries ] && [ "$user_cancelled" = false ]; then
      error_handle "$ERROR_EXECUTION" "Tofu command failed (attempt $retry_count), will retry" "$SEVERITY_MEDIUM" "retry"
    fi
  done

  # Return to original directory with error handling
  if ! popd >/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to return to original directory" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if [ $cmd_exit_code -ne 0 ] && [ "$user_cancelled" = false ] && ! ([ "$tofu_subcommand" = "plan" ] && [ $cmd_exit_code -eq 1 ]); then
    error_handle "$ERROR_EXECUTION" "Tofu command '${final_tofu_cmd_array[*]}' failed after $((retry_count)) attempts" "$SEVERITY_HIGH" "abort"
    return 1
  elif [ "$user_cancelled" = true ]; then
    log_info "Operation cancelled by user or timed out."
    return 1
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

  # Initialize recovery for this operation
  recovery_checkpoint "tofu_start_vms_start" "Starting VM start operation"

  # Get current context with error handling
  if ! current_ctx=$(get_current_cluster_context); then
    error_handle "$ERROR_CONFIG" "Failed to get current cluster context" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  log_info "Starting VMs for context '$current_ctx'..."

  # Call the deploy command internally to start VMs
  if ! tofu_deploy apply -var="vm_started=true" -auto-approve; then
    error_handle "$ERROR_EXECUTION" "Failed to start VMs for context '$current_ctx'" "$SEVERITY_HIGH" "retry"
    # Retry once more
    if ! tofu_deploy apply -var="vm_started=true" -auto-approve; then
      error_handle "$ERROR_EXECUTION" "Failed to start VMs for context '$current_ctx' after retry" "$SEVERITY_CRITICAL" "abort"
      return 1
    fi
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

  # Initialize recovery for this operation
  recovery_checkpoint "tofu_stop_vms_start" "Starting VM stop operation"

  # Get current context with error handling
  if ! current_ctx=$(get_current_cluster_context); then
    error_handle "$ERROR_CONFIG" "Failed to get current cluster context" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  log_info "Stopping VMs for context '$current_ctx'..."

  # Ask for confirmation before stopping VMs
  read -r -p "Are you sure you want to stop all VMs in context '$current_ctx'? [y/N] " response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    log_info "Operation cancelled by user."
    return 0
  fi

  # Call the deploy command internally to stop VMs
  if ! tofu_deploy apply -var="vm_started=false" -auto-approve; then
    error_handle "$ERROR_EXECUTION" "Failed to stop VMs for context '$current_ctx'" "$SEVERITY_HIGH" "retry"
    # Retry once more
    if ! tofu_deploy apply -var="vm_started=false" -auto-approve; then
      error_handle "$ERROR_EXECUTION" "Failed to stop VMs for context '$current_ctx' after retry" "$SEVERITY_CRITICAL" "abort"
      return 1
    fi
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
      error_handle "$ERROR_INPUT" "Unknown option: $1" "$SEVERITY_LOW" "abort"
      return 1
      ;;
    esac
  done

  if [[ "$format" != "table" && "$format" != "json" ]]; then
    error_handle "$ERROR_INPUT" "Invalid format '$format'. Supported formats: table, json" "$SEVERITY_LOW" "abort"
    return 1
  fi

  # Initialize recovery for this operation
  recovery_checkpoint "tofu_cluster_info_start" "Starting cluster info operation"

  local current_ctx tf_dir
  if ! current_ctx=$(get_current_cluster_context); then
    error_handle "$ERROR_CONFIG" "Failed to get current cluster context" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  tf_dir="$REPO_PATH/terraform"

  if [ "$format" != "json" ]; then
    log_info "Getting cluster information for context '$current_ctx'..."
  fi

  # Validate terraform directory
  if ! error_validate_directory "$tf_dir" "Terraform directory not found: $tf_dir"; then
    return 1
  fi

  # Export AWS credentials for terraform backend
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
  export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

  # Load workspace environment variables for proper Terraform context
  tofu_load_workspace_env_vars "$current_ctx"

  if ! pushd "$tf_dir" >/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to change to terraform directory" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Ensure we're in the correct workspace
  if ! tofu workspace select "$current_ctx" &>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to select Tofu workspace '$current_ctx'" "$SEVERITY_HIGH" "retry"
    # Retry once more
    if ! tofu workspace select "$current_ctx" &>/dev/null; then
      error_handle "$ERROR_EXECUTION" "Failed to select Tofu workspace '$current_ctx' after retry" "$SEVERITY_CRITICAL" "abort"
      popd >/dev/null
      return 1
    fi
  fi

  # Get the simplified cluster summary
  local cluster_summary
  if ! cluster_summary=$(tofu output -json cluster_summary 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to get cluster summary from tofu output" "$SEVERITY_HIGH" "abort"
    popd >/dev/null
    return 1
  fi

  if [ "$cluster_summary" = "null" ] || [ -z "$cluster_summary" ]; then
    error_handle "$ERROR_EXECUTION" "No cluster summary available. Make sure VMs are deployed." "$SEVERITY_MEDIUM" "abort"
    popd >/dev/null
    return 1
  fi

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
    if ! echo "$json_data" | jq -r 'to_entries[] | "\(.key) \(.value.VM_ID) \(.value.hostname) \(.value.IP)"' |
      while read -r node vm_id hostname ip; do
        printf "%-25s %-15s %-20s %s\n" "$node" "$vm_id" "$hostname" "$ip"
      done; then
      error_handle "$ERROR_EXECUTION" "Failed to parse cluster summary JSON" "$SEVERITY_MEDIUM" "abort"
      popd >/dev/null
      return 1
    fi
    echo ""
  fi

  if ! popd >/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to return to original directory" "$SEVERITY_HIGH" "abort"
    return 1
  fi
}

# Load workspace environment variables for Terraform context
function tofu_load_workspace_env_vars() {
  local current_ctx="$1"
  local env_file="$REPO_PATH/envs/$current_ctx.env"

  if [ ! -f "$env_file" ]; then
    log_debug "No environment file found for context '$current_ctx' at $env_file"
    return 0
  fi

  log_debug "Loading workspace environment variables from $env_file"

  # Load workspace-specific variables
  local var_name var_value line_count=0
  while IFS='=' read -r var_name var_value; do
    line_count=$((line_count + 1))

    # Skip comments and empty lines
    [[ "$var_name" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$var_name" ]] && continue

    # Remove quotes from value
    var_value=$(echo "$var_value" | tr -d '"' 2>/dev/null || echo "")

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
    *)
      log_debug "Skipping unknown variable: $var_name"
      ;;
    esac
  done < <(grep -E "^[A-Z_]+=" "$env_file" 2>/dev/null || true)

  if [ $line_count -eq 0 ]; then
    error_handle "$ERROR_CONFIG" "Environment file exists but contains no valid variables: $env_file" "$SEVERITY_LOW" "continue"
  else
    log_debug "Loaded $line_count environment variables from $env_file"
  fi
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
    error_handle "$ERROR_INPUT" "Received empty or null JSON in tofu_update_node_info" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Parse JSON and export variables
  if ! TOFU_NODE_NAMES=($(echo "$summary_json" | jq -r 'keys_unsorted[]' 2>/dev/null)); then
    error_handle "$ERROR_EXECUTION" "Failed to parse node names from JSON" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if ! TOFU_NODE_IPS=($(echo "$summary_json" | jq -r '.[].IP' 2>/dev/null)); then
    error_handle "$ERROR_EXECUTION" "Failed to parse node IPs from JSON" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if ! TOFU_NODE_HOSTNAMES=($(echo "$summary_json" | jq -r '.[].hostname' 2>/dev/null)); then
    error_handle "$ERROR_EXECUTION" "Failed to parse node hostnames from JSON" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if ! TOFU_NODE_VM_IDS=($(echo "$summary_json" | jq -r '.[].VM_ID' 2>/dev/null)); then
    error_handle "$ERROR_EXECUTION" "Failed to parse node VM IDs from JSON" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if [ ${#TOFU_NODE_NAMES[@]} -eq 0 ]; then
    error_handle "$ERROR_EXECUTION" "Parsed zero nodes from Tofu output" "$SEVERITY_MEDIUM" "abort"
    return 1
  fi

  log_debug "Successfully parsed ${#TOFU_NODE_NAMES[@]} nodes from Tofu output"
  return 0
}
export -f tofu_update_node_info

function tofu_generate_hostnames() {
  # Initialize recovery for this operation
  recovery_checkpoint "tofu_generate_hostnames_start" "Starting hostname generation operation"

  # Validate workspace is set
  if [[ -z "$CPC_WORKSPACE" ]]; then
    error_handle "$ERROR_CONFIG" "CPC_WORKSPACE environment variable not set" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  log_info "Preparing to generate hostnames for workspace '$CPC_WORKSPACE'..."

  # Validate script exists and is executable
  local script_path="$REPO_PATH/scripts/generate_node_hostnames.sh"
  if [[ ! -x "$script_path" ]]; then
    error_handle "$ERROR_CONFIG" "Hostname generation script not found or not executable: $script_path" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Execute the script that generates and copies snippets
  if ! "$script_path"; then
    error_handle "$ERROR_EXECUTION" "Hostname configuration generation failed" "$SEVERITY_HIGH" "retry"
    # Retry once more
    if ! "$script_path"; then
      error_handle "$ERROR_EXECUTION" "Hostname configuration generation failed after retry" "$SEVERITY_CRITICAL" "abort"
      return 1
    fi
  fi
  log_success "Hostname configurations generated successfully."
}
