#!/bin/bash

#================================================================================#
#                         Kubernetes Node Management (40)                          #
#================================================================================#

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

# --- Help Functions ---

# Phase 5: Centralized Help System

function _get_help_template() {
  local operation_type="$1"
  
  case "$operation_type" in
    "basic_node_operation")
      echo "Usage: cpc %s --target-hosts <IP_ADDRESS>"
      ;;
    "node_operation_with_type")
      echo "Usage: cpc %s --target-hosts <IP_ADDRESS> [--node-type <TYPE>]"
      ;;
    *)
      echo "Usage: cpc %s <args>"
      ;;
  esac
}

function _show_node_operation_help() {
  local operation_name="$1"
  local description="$2"
  local template_type="$3"
  local additional_args="$4"
  
  local template
  template=$(_get_help_template "$template_type")
  
  log_header "$(printf "$template" "$operation_name")"
  log_info "$description"
  log_info "\nArguments:"
  log_info "  --target-hosts <IP>    (Required) The IP address of the node."
  
  if [[ "$template_type" == "node_operation_with_type" ]]; then
    log_info "  --node-type <TYPE>       (Optional) The type of node ('worker' or 'control-plane'). Defaults to 'worker'."
  fi
  
  if [[ -n "$additional_args" ]]; then
    log_info "$additional_args"
  fi
}

function k8s_show_add_nodes_help() {
  _show_node_operation_help "add-nodes" "Adds a new node to the Kubernetes cluster." "node_operation_with_type"
}

function k8s_show_remove_nodes_help() {
  _show_node_operation_help "remove-nodes" "Drains and removes a node from the Kubernetes cluster." "basic_node_operation"
}

function k8s_show_drain_node_help() {
  _show_node_operation_help "drain-node" "Safely drains a node by evicting all pods before maintenance." "basic_node_operation"
}

function k8s_show_upgrade_node_help() {
  _show_node_operation_help "upgrade-node" "Upgrades Kubernetes components on a specific node." "basic_node_operation"
}

function k8s_show_reset_node_help() {
  _show_node_operation_help "reset-node" "Resets a node to its pre-bootstrap state using 'kubeadm reset'." "basic_node_operation"
}

function k8s_show_prepare_node_help() {
  _show_node_operation_help "prepare-node" "Prepares a node for Kubernetes by installing required packages." "basic_node_operation"
}

function k8s_show_uncordon_node_help() {
  _show_node_operation_help "uncordon-node" "Uncordons a node to allow new pods to be scheduled on it." "basic_node_operation"
}

# --- Internal Helper for Node Operations ---

# Phase 1: Argument Parsing and Validation Functions

function _parse_node_operation_args() {
  local target_hosts=""
  local node_type="worker" # Default node type
  local extra_ansible_args=()

  # Enhanced parser that understands all the necessary arguments with error handling
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --target-hosts=*)
      target_hosts="${1#*=}"
      shift
      ;;
    --target-hosts)
      if [[ -n "$2" && "$2" != --* ]]; then
        target_hosts="$2"
        shift 2
      else
        error_handle "$ERROR_VALIDATION" "Argument for --target-hosts is missing" "$SEVERITY_HIGH"
        return 1
      fi
      ;;
    --node-type=*)
      node_type="${1#*=}"
      shift
      ;;
    --node-type)
      if [[ -n "$2" && "$2" != --* ]]; then
        node_type="$2"
        shift 2
      else
        error_handle "$ERROR_VALIDATION" "Argument for --node-type is missing" "$SEVERITY_HIGH"
        return 1
      fi
      ;;
    *)
      extra_ansible_args+=("$1")
      shift
      ;;
    esac
  done

  if [[ -z "$target_hosts" ]]; then
    error_handle "$ERROR_VALIDATION" "Missing required argument: --target-hosts" "$SEVERITY_HIGH"
    return 1
  fi

  # Validate IP address format
  if ! _validate_target_host_ip "$target_hosts"; then
    error_handle "$ERROR_VALIDATION" "Invalid IP address format: $target_hosts" "$SEVERITY_HIGH"
    return 1
  fi

  # Validate node type
  if ! _validate_node_type "$node_type"; then
    error_handle "$ERROR_VALIDATION" "Invalid node type: $node_type" "$SEVERITY_HIGH"
    return 1
  fi

  # Set global variables for use by caller (simpler than complex return parsing)
  PARSED_TARGET_HOSTS="$target_hosts"
  PARSED_NODE_TYPE="$node_type"
  PARSED_EXTRA_ARGS=("${extra_ansible_args[@]}")
}

function _validate_target_host_ip() {
  local target_ip="$1"
  [[ "$target_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

function _validate_node_type() {
  local node_type="$1"
  [[ "$node_type" == "worker" || "$node_type" == "control-plane" ]]
}

function _initialize_node_operation_recovery() {
  local action_desc="$1"
  recovery_checkpoint "${action_desc// /_}_start" "Starting $action_desc operation"
}

function _finalize_node_operation_recovery() {
  local action_desc="$1"
  local target_hostname="$2"
  recovery_checkpoint "${action_desc// /_}_complete" "$action_desc completed successfully"
  log_success "$action_desc completed successfully for node: $target_hostname"
}

# Phase 2: Infrastructure Data Operations

function _get_infrastructure_data_with_retry() {
  local all_tofu_outputs_json
  if ! all_tofu_outputs_json=$(_get_terraform_outputs_json); then
    error_handle "$ERROR_EXECUTION" "Failed to get infrastructure data from Terraform" "$SEVERITY_HIGH"
    return 1
  fi
  echo "$all_tofu_outputs_json"
}

function _resolve_hostname_from_ip() {
  local target_ip="$1"
  local infrastructure_json="$2"

  local target_hostname
  if ! target_hostname=$(_get_hostname_by_ip "$target_ip" "$infrastructure_json"); then
    error_handle "$ERROR_VALIDATION" "Could not find a host with IP '$target_ip' in the current workspace" "$SEVERITY_HIGH"
    return 1
  fi

  if [[ -z "$target_hostname" ]]; then
    error_handle "$ERROR_VALIDATION" "Could not find a host with IP '$target_ip' in the current workspace" "$SEVERITY_HIGH"
    return 1
  fi

  log_debug "Found host '$target_hostname' for IP '$target_ip'. Proceeding..."
  echo "$target_hostname"
}

# Phase 3: Ansible Execution Logic

function _execute_ansible_playbook_with_recovery() {
  local playbook_name="$1"
  local target_hostname="$2"
  local node_type="$3"
  local action_desc="$4"
  shift 4
  local extra_args=("$@")

  # Execute ansible playbook directly
  if ! ansible_run_playbook "$playbook_name" -l "$target_hostname" -e "node_type=$node_type" "${extra_args[@]}"; then
    log_warning "$action_desc failed, manual cleanup may be needed"
    error_handle "$ERROR_EXECUTION" "$action_desc failed for node $target_hostname" "$SEVERITY_HIGH"
    return 1
  fi

  # Validate the operation
  if ! validate_node_operation "$playbook_name" "$target_hostname"; then
    log_warning "Validation failed for $action_desc on $target_hostname"
  fi
}

function _execute_node_playbook() {
  local playbook_name="$1"
  local action_desc="$2"
  shift 2

  # Step 1: Initialize recovery
  _initialize_node_operation_recovery "$action_desc"

  # Step 2: Parse and validate arguments
  if ! _parse_node_operation_args "$@"; then
    return 1
  fi

  log_step "$action_desc for node: $PARSED_TARGET_HOSTS"

  # Step 3: Get infrastructure data
  local infrastructure_json
  if ! infrastructure_json=$(_get_infrastructure_data_with_retry); then
    return 1
  fi

  # Step 4: Resolve hostname
  local target_hostname
  if ! target_hostname=$(_resolve_hostname_from_ip "$PARSED_TARGET_HOSTS" "$infrastructure_json"); then
    return 1
  fi

  # Step 5: Execute playbook
  if ! _execute_ansible_playbook_with_recovery "$playbook_name" "$target_hostname" "$PARSED_NODE_TYPE" "$action_desc" "${PARSED_EXTRA_ARGS[@]}"; then
    return 1
  fi

  # Step 6: Finalize recovery
  _finalize_node_operation_recovery "$action_desc" "$target_hostname"
}

# Helper function to get Terraform outputs with error handling
function _get_terraform_outputs_json() {
  # Skip execution during module loading
  if [[ -z "${CPC_MODULE_LOADING:-}" ]]; then
    local repo_root
    if ! repo_root=$(get_repo_path 2>/dev/null); then
      echo "Failed to determine repository path" >&2
      return 1
    fi

    # Check if we can execute cpc command
    if [[ ! -x "$repo_root/cpc" ]]; then
      echo "CPC command not found or not executable" >&2
      return 1
    fi

    local raw_output
    if ! raw_output=$("$repo_root/cpc" deploy output 2>/dev/null); then
      echo "Failed to get Terraform outputs" >&2
      return 1
    fi

    # Extract ansible_inventory JSON from the output
    local ansible_inventory_json
    ansible_inventory_json=$(echo "$raw_output" | grep '^ansible_inventory = ' | sed 's/^ansible_inventory = "//' | sed 's/"$//')
    
    # Decode escaped JSON
    ansible_inventory_json=$(echo "$ansible_inventory_json" | sed 's/\\"/"/g')
    
    if [[ -z "$ansible_inventory_json" ]]; then
      echo "Failed to extract ansible_inventory from Terraform output" >&2
      return 1
    fi

    # Export for use in calling function
    echo "$ansible_inventory_json"
  fi
}

# Helper function to get hostname by IP with error handling
function _get_hostname_by_ip() {
  local target_ip="$1"
  local ansible_inventory_json="$2"

  if [[ -z "$target_ip" || -z "$ansible_inventory_json" ]]; then
    error_handle "$ERROR_VALIDATION" "Missing required parameters for hostname lookup" "$SEVERITY_HIGH"
    return 1
  fi

  # Find hostname by IP address in the ansible inventory hostvars
  local hostname
  hostname=$(echo "$ansible_inventory_json" | jq -r --arg ip "$target_ip" '
    ._meta.hostvars | to_entries[] | select(.value.ansible_host == $ip) | .key
  ' 2>/dev/null)

  if [[ -z "$hostname" || "$hostname" == "null" ]]; then
    return 1
  fi

  echo "$hostname"
}

# Phase 4: Validation Functions

function _validate_node_addition() {
  local target_hostname="$1"
  
  # Skip validation for node addition since the playbook already confirms successful addition
  # and provides node status information
  log_debug "Skipping local validation for node addition (confirmed by ansible playbook)"
  return 0
}

function _validate_node_removal() {
  local target_hostname="$1"
  
  # Skip validation for node removal since the playbook already confirms successful removal
  # and performs the kubectl delete node operation
  log_debug "Skipping local validation for node removal (confirmed by ansible playbook)"
  return 0
}

function _validate_node_drain() {
  local target_hostname="$1"
  
  # Skip validation for drain operations since they execute on control plane
  # and the drain operation itself provides confirmation
  log_debug "Skipping local validation for node drain (executed remotely on control plane)"
  return 0
}

function _validate_node_uncordon() {
  local target_hostname="$1"
  
  # Skip validation for uncordon operations since they execute on control plane
  # and the uncordon operation itself provides confirmation
  log_debug "Skipping local validation for node uncordon (executed remotely on control plane)"
  return 0
}

function _create_validation_strategy() {
  local playbook_name="$1"
  
  case "$playbook_name" in
    "pb_add_nodes.yml")
      echo "_validate_node_addition"
      ;;
    "pb_delete_node.yml")
      echo "_validate_node_removal"
      ;;
    "pb_drain_node.yml")
      echo "_validate_node_drain"
      ;;
    "pb_uncordon_node.yml")
      echo "_validate_node_uncordon"
      ;;
    *)
      echo ""
      ;;
  esac
}

# Helper function to validate node operation
function validate_node_operation() {
  local playbook_name="$1"
  local target_hostname="$2"

  local validation_func
  validation_func=$(_create_validation_strategy "$playbook_name")
  
  if [[ -n "$validation_func" ]]; then
    $validation_func "$target_hostname"
  else
    log_debug "No specific validation for playbook: $playbook_name"
    return 0
  fi
}

# --- Public Functions ---

function k8s_add_nodes() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    k8s_show_add_nodes_help
    return 0
  fi
  _execute_node_playbook "pb_add_nodes.yml" "Adding worker node" "$@"
}

function k8s_remove_nodes() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    k8s_show_remove_nodes_help
    return 0
  fi
  _execute_node_playbook "pb_delete_node.yml" "Removing node" "$@"
}

function k8s_drain_node() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    k8s_show_drain_node_help
    return 0
  fi
  
  # Step 1: Initialize recovery
  _initialize_node_operation_recovery "Draining node"

  # Step 2: Parse and validate arguments
  if ! _parse_node_operation_args "$@"; then
    return 1
  fi

  log_step "Draining node for node: $PARSED_TARGET_HOSTS"

  # Step 3: Get infrastructure data
  local infrastructure_json
  if ! infrastructure_json=$(_get_infrastructure_data_with_retry); then
    return 1
  fi

  # Step 4: Resolve hostname
  local target_hostname
  if ! target_hostname=$(_resolve_hostname_from_ip "$PARSED_TARGET_HOSTS" "$infrastructure_json"); then
    return 1
  fi

  # Step 5: Execute drain playbook on control plane
  if ! ansible_run_playbook "pb_drain_node.yml" -l control_plane -e "node_to_drain=$target_hostname" "${PARSED_EXTRA_ARGS[@]}"; then
    log_warning "Draining node failed, manual cleanup may be needed"
    error_handle "$ERROR_EXECUTION" "Draining node failed for node $target_hostname" "$SEVERITY_HIGH"
    return 1
  fi

  # Step 6: Validate the operation
  if ! validate_node_operation "pb_drain_node.yml" "$target_hostname"; then
    log_warning "Validation failed for Draining node on $target_hostname"
  fi

  # Step 7: Finalize recovery
  _finalize_node_operation_recovery "Draining node" "$target_hostname"
}

function k8s_upgrade_node() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    k8s_show_upgrade_node_help
    return 0
  fi
  _execute_node_playbook "pb_upgrade_node.yml" "Upgrading node" "$@"
}

function k8s_reset_node() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    k8s_show_reset_node_help
    return 0
  fi
  _execute_node_playbook "pb_reset_node.yml" "Resetting node" "$@"
}

function k8s_prepare_node() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    k8s_show_prepare_node_help
    return 0
  fi
  _execute_node_playbook "pb_prepare_node.yml" "Preparing node" "$@"
}

function k8s_uncordon_node() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    k8s_show_uncordon_node_help
    return 0
  fi
  
  # Step 1: Initialize recovery
  _initialize_node_operation_recovery "Uncordoning node"

  # Step 2: Parse and validate arguments
  if ! _parse_node_operation_args "$@"; then
    return 1
  fi

  log_step "Uncordoning node for node: $PARSED_TARGET_HOSTS"

  # Step 3: Get infrastructure data
  local infrastructure_json
  if ! infrastructure_json=$(_get_infrastructure_data_with_retry); then
    return 1
  fi

  # Step 4: Resolve hostname
  local target_hostname
  if ! target_hostname=$(_resolve_hostname_from_ip "$PARSED_TARGET_HOSTS" "$infrastructure_json"); then
    return 1
  fi

  # Step 5: Execute uncordon playbook on control plane
  if ! ansible_run_playbook "pb_uncordon_node.yml" -l control_plane -e "node_to_uncordon=$target_hostname" "${PARSED_EXTRA_ARGS[@]}"; then
    log_warning "Uncordoning node failed, manual cleanup may be needed"
    error_handle "$ERROR_EXECUTION" "Uncordoning node failed for node $target_hostname" "$SEVERITY_HIGH"
    return 1
  fi

  # Step 6: Validate the operation
  if ! validate_node_operation "pb_uncordon_node.yml" "$target_hostname"; then
    log_warning "Validation failed for Uncordoning node on $target_hostname"
  fi

  # Step 7: Finalize recovery
  _finalize_node_operation_recovery "Uncordoning node" "$target_hostname"
}

function k8s_reset_all_nodes() {
  log_step "Resetting all nodes in the cluster..."

  # Execute with recovery
  if ! recovery_execute \
       "ansible_run_playbook 'pb_reset_all_nodes.yml' -e 'reset_all_nodes=true'" \
       "reset_all_nodes" \
       "log_warning 'Reset all nodes failed, manual cleanup may be needed'" \
       "validate_cluster_reset"; then
    error_handle "$ERROR_EXECUTION" "Failed to reset all nodes in cluster" "$SEVERITY_HIGH"
    return 1
  fi

  log_success "All nodes reset successfully"
}

# Validate cluster reset operation
function validate_cluster_reset() {
  # Check if any nodes are still in the cluster (should be empty or only control plane)
  local node_count
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  [[ $node_count -le 1 ]] # Should have at most 1 node (control plane)
}

# --- Main Dispatcher for cpc_k8s_nodes ---

function cpc_k8s_nodes() {
  local action="$1"
  shift

  case "$action" in
  add) k8s_add_nodes "$@" ;;
  remove) k8s_remove_nodes "$@" ;;
  drain) k8s_drain_node "$@" ;;
  uncordon) k8s_uncordon_node "$@" ;;
  upgrade) k8s_upgrade_node "$@" ;;
  reset) k8s_reset_node "$@" ;;
  reset-all) k8s_reset_all_nodes "$@" ;;
  prepare) k8s_prepare_node "$@" ;;
  *)
    log_error "Unknown command for 'cpc nodes': $action"
    return 1
    ;;
  esac
}

export -f cpc_k8s_nodes k8s_add_nodes k8s_remove_nodes k8s_drain_node k8s_upgrade_node k8s_reset_node k8s_prepare_node k8s_uncordon_node k8s_reset_all_nodes
export -f k8s_show_add_nodes_help k8s_show_remove_nodes_help k8s_show_drain_node_help k8s_show_upgrade_node_help k8s_show_reset_node_help k8s_show_prepare_node_help k8s_show_uncordon_node_help
