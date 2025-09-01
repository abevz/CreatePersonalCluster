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

function k8s_show_add_nodes_help() {
  log_header "Usage: cpc add-nodes --target-hosts <IP_ADDRESS> [--node-type <TYPE>]"
  log_info "Adds a new node to the Kubernetes cluster."
  log_info "\nArguments:"
  log_info "  --target-hosts <IP>    (Required) The IP address of the new VM to be added."
  log_info "  --node-type <TYPE>       (Optional) The type of node ('worker' or 'control-plane'). Defaults to 'worker'."
}

function k8s_show_remove_nodes_help() {
  log_header "Usage: cpc remove-nodes --target-hosts <IP_ADDRESS>"
  log_info "Drains and removes a node from the Kubernetes cluster."
  log_info "\nArguments:"
  log_info "  --target-hosts <IP>    (Required) The IP address of the node to remove."
}

function k8s_show_drain_node_help() {
  log_header "Usage: cpc drain-node --target-hosts <IP_ADDRESS>"
  log_info "Safely drains a node by evicting all pods before maintenance."
  log_info "\nArguments:"
  log_info "  --target-hosts <IP>    (Required) The IP address of the node to drain."
}

function k8s_show_upgrade_node_help() {
  log_header "Usage: cpc upgrade-node --target-hosts <IP_ADDRESS>"
  log_info "Upgrades Kubernetes components on a specific node."
  log_info "\nArguments:"
  log_info "  --target-hosts <IP>    (Required) The IP address of the node to upgrade."
}

function k8s_show_reset_node_help() {
  log_header "Usage: cpc reset-node --target-hosts <IP_ADDRESS>"
  log_info "Resets a node to its pre-bootstrap state using 'kubeadm reset'."
  log_info "\nArguments:"
  log_info "  --target-hosts <IP>    (Required) The IP address of the node to reset."
}

function k8s_show_prepare_node_help() {
  log_header "Usage: cpc prepare-node --target-hosts <IP_ADDRESS>"
  log_info "Prepares a node for Kubernetes by installing required packages."
  log_info "\nArguments:"
  log_info "  --target-hosts <IP>    (Required) The IP address of the node to prepare."
}

# --- Internal Helper for Node Operations ---

function _execute_node_playbook() {
  local playbook_name="$1"
  local action_desc="$2"
  shift 2

  # Initialize recovery for node operations
  recovery_checkpoint "${action_desc// /_}_start" "Starting $action_desc operation"

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
  if ! [[ "$target_hosts" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error_handle "$ERROR_VALIDATION" "Invalid IP address format: $target_hosts" "$SEVERITY_HIGH"
    return 1
  fi

  log_step "$action_desc for node: $target_hosts"

  # Get Terraform outputs with error handling and retry
  local all_tofu_outputs_json
  if ! retry_execute \
       "_get_terraform_outputs_json" \
       3 \
       2 \
       30 \
       "" \
       "Get infrastructure data from Tofu"; then
    error_handle "$ERROR_EXECUTION" "Failed to get infrastructure data from Tofu after retries" "$SEVERITY_HIGH"
    return 1
  fi

  # Get hostname by IP with error handling
  local target_hostname
  if ! target_hostname=$(_get_hostname_by_ip "$target_hosts" "$all_tofu_outputs_json"); then
    error_handle "$ERROR_VALIDATION" "Could not find a host with IP '$target_hosts' in the current workspace" "$SEVERITY_HIGH"
    return 1
  fi

  if [[ -z "$target_hostname" ]]; then
    error_handle "$ERROR_VALIDATION" "Could not find a host with IP '$target_hosts' in the current workspace" "$SEVERITY_HIGH"
    return 1
  fi

  log_info "Found host '$target_hostname' for IP '$target_hosts'. Proceeding..."

  # Execute Ansible playbook with recovery
  if ! recovery_execute \
       "ansible_run_playbook '$playbook_name' -l '$target_hostname' -e 'node_type=$node_type' '${extra_ansible_args[*]}'" \
       "${action_desc// /_}" \
       "log_warning '$action_desc failed, manual cleanup may be needed'" \
       "validate_node_operation '$playbook_name' '$target_hostname'"; then
    error_handle "$ERROR_EXECUTION" "$action_desc failed for node $target_hostname" "$SEVERITY_HIGH"
    return 1
  fi

  recovery_checkpoint "${action_desc// /_}_complete" "$action_desc completed successfully"
  log_success "$action_desc completed successfully for node: $target_hostname"
}

# Helper function to get Terraform outputs with error handling
function _get_terraform_outputs_json() {
  local repo_root
  if ! repo_root=$(get_repo_path); then
    error_handle "$ERROR_CONFIG" "Failed to determine repository path" "$SEVERITY_HIGH"
    return 1
  fi

  local raw_output
  if ! raw_output=$("$repo_root/cpc" deploy output -json 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to get Terraform outputs" "$SEVERITY_HIGH"
    return 1
  fi

  # Extract clean JSON from all text
  all_tofu_outputs_json=$(echo "$raw_output" | sed -n '/^{$/,/^}$/p')
  if [[ -z "$all_tofu_outputs_json" ]]; then
    error_handle "$ERROR_VALIDATION" "Failed to extract JSON from Terraform output" "$SEVERITY_HIGH"
    return 1
  fi

  # Export for use in calling function
  echo "$all_tofu_outputs_json"
}

# Helper function to get hostname by IP with error handling
function _get_hostname_by_ip() {
  local target_ip="$1"
  local tofu_outputs_json="$2"

  if [[ -z "$target_ip" || -z "$tofu_outputs_json" ]]; then
    error_handle "$ERROR_VALIDATION" "Missing required parameters for hostname lookup" "$SEVERITY_HIGH"
    return 1
  fi

  # Extract cluster_summary and find hostname by IP
  local cluster_summary_json
  cluster_summary_json=$(echo "$tofu_outputs_json" | jq -r '.cluster_summary.value // empty' 2>/dev/null)

  if [[ -z "$cluster_summary_json" ]]; then
    error_handle "$ERROR_VALIDATION" "No cluster summary found in Terraform outputs" "$SEVERITY_HIGH"
    return 1
  fi

  # Find hostname by IP address
  local hostname
  hostname=$(echo "$cluster_summary_json" | jq -r --arg ip "$target_ip" '
    .[] | select(.ip == $ip) | .hostname // empty
  ' 2>/dev/null)

  if [[ -z "$hostname" || "$hostname" == "null" ]]; then
    return 1
  fi

  echo "$hostname"
}

# Helper function to validate node operation
function validate_node_operation() {
  local playbook_name="$1"
  local target_hostname="$2"

  case "$playbook_name" in
    "pb_add_nodes.yml")
      # Validate node was added successfully
      if timeout_kubectl_operation \
           "kubectl get nodes '$target_hostname' 2>/dev/null | grep -q Ready" \
           "Validate node addition" \
           30; then
        log_debug "Node $target_hostname successfully added and ready"
        return 0
      else
        log_warning "Node $target_hostname was added but not yet ready"
        return 1
      fi
      ;;
    "pb_delete_node.yml")
      # Validate node was removed
      if ! timeout_kubectl_operation \
             "kubectl get nodes '$target_hostname' 2>/dev/null" \
             "Check node removal" \
             10; then
        log_debug "Node $target_hostname successfully removed"
        return 0
      else
        log_warning "Node $target_hostname may still exist"
        return 1
      fi
      ;;
    "pb_drain_node.yml")
      # Validate node is drained (no pods except system pods)
      if timeout_kubectl_operation \
           "kubectl get pods -A -o wide | grep '$target_hostname' | grep -v kube-system | wc -l | grep -q '^0$'" \
           "Validate node drain" \
           30; then
        log_debug "Node $target_hostname successfully drained"
        return 0
      else
        log_warning "Node $target_hostname may still have non-system pods"
        return 1
      fi
      ;;
    *)
      log_debug "No specific validation for playbook: $playbook_name"
      return 0
      ;;
  esac
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
  _execute_node_playbook "pb_drain_node.yml" "Draining node" "$@"
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

export -f cpc_k8s_nodes k8s_add_nodes k8s_remove_nodes k8s_drain_node k8s_upgrade_node k8s_reset_node k8s_prepare_node k8s_reset_all_nodes
export -f k8s_show_add_nodes_help k8s_show_remove_nodes_help k8s_show_drain_node_help k8s_show_upgrade_node_help k8s_show_reset_node_help k8s_show_prepare_node_help
