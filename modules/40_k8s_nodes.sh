#!/bin/bash

#================================================================================#
#                         Kubernetes Node Management (40)                          #
#================================================================================#

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

  local target_hosts=""
  local node_type="worker" # Default node type
  local extra_ansible_args=()

  # Enhanced parser that understands all the necessary arguments
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
        log_error "Argument for --target-hosts is missing"
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
        log_error "Argument for --node-type is missing"
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
    log_error "Missing required argument: --target-hosts"
    return 1
  fi

  log_step "$action_desc for node: $target_hosts"

  local all_tofu_outputs_json
  all_tofu_outputs_json=$(_get_terraform_outputs_json)
  if [[ $? -ne 0 ]]; then
    log_error "Failed to get infrastructure data from Tofu."
    return 1
  fi

  local target_hostname
  target_hostname=$(_get_hostname_by_ip "$target_hosts" "$all_tofu_outputs_json")

  if [[ -z "$target_hostname" ]]; then
    log_error "Could not find a host with IP '$target_hosts' in the current workspace."
    return 1
  fi

  log_info "Found host '$target_hostname' for IP '$target_hosts'. Proceeding..."

  # Pass node_type as a variable to Ansible, not as an argument
  ansible_run_playbook "$playbook_name" -l "$target_hostname" -e "node_type=$node_type" "${extra_ansible_args[@]}"
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
  ansible_run_playbook "pb_reset_all_nodes.yml" -e "reset_all_nodes=true"
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
