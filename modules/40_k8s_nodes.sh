#!/bin/bash

# modules/40_k8s_nodes.sh - Kubernetes Node Management Module
# Part of CPC (Create Personal Cluster) - Modular Architecture
#
# This module provides individual Kubernetes node management functionality.
# 
# Functions provided:
# - cpc_k8s_nodes()            - Main entry point for node management commands
# - k8s_add_nodes()            - Add new worker or control plane nodes to cluster
# - k8s_remove_nodes()         - Remove nodes from Kubernetes cluster
# - k8s_drain_node()           - Drain workloads from a specific node
# - k8s_upgrade_node()         - Upgrade Kubernetes on a specific node
# - k8s_reset_node()           - Reset Kubernetes on a specific node
# - k8s_prepare_node()         - Install Kubernetes components on new VM
# - k8s_show_*_help()          - Display help for various node commands
#
# Dependencies:
# - lib/logging.sh for logging functions  
# - modules/00_core.sh for core utilities like get_repo_path, get_current_cluster_context
# - modules/20_ansible.sh for ansible_run_playbook function
# - Kubernetes cluster infrastructure
# - Ansible playbooks for node operations

#----------------------------------------------------------------------
# Kubernetes Node Management Functions
#----------------------------------------------------------------------

# Main entry point for CPC kubernetes node functionality
cpc_k8s_nodes() {
    case "${1:-}" in
        add-nodes)
            shift
            k8s_add_nodes "$@"
            ;;
        remove-nodes)
            shift
            k8s_remove_nodes "$@"
            ;;
        drain-node)
            shift
            k8s_drain_node "$@"
            ;;
        upgrade-node)
            shift
            k8s_upgrade_node "$@"
            ;;
        reset-node)
            shift
            k8s_reset_node "$@"
            ;;
        prepare-node)
            shift
            k8s_prepare_node "$@"
            ;;
        *)
            log_error "Unknown k8s node command: ${1:-}"
            log_info "Available commands: add-nodes, remove-nodes, drain-node, upgrade-node, reset-node, prepare-node"
            return 1
            ;;
    esac
}

# Add new worker or control plane nodes to the cluster
k8s_add_nodes() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_add_nodes_help
        return 0
    fi

    # Parse command line arguments
    local target_hosts="new_workers"
    local node_type="worker"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target-hosts)
                target_hosts="$2"
                shift 2
                ;;
            --node-type)
                node_type="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    log_info "Adding $node_type nodes to the cluster..."
    ansible_run_playbook "pb_add_nodes.yml" -l "$target_hosts" -e "node_type=$node_type"
}

# Remove nodes from the Kubernetes cluster
k8s_remove_nodes() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_remove_nodes_help
        return 0
    fi

    local target_hosts=""

    # Handle single host argument (no flag)
    if [[ $# -eq 1 && "$1" != --* ]]; then
        target_hosts="$1"
    else
        # Parse command line arguments
        while [[ $# -gt 0 ]]; do
            case $1 in
                --target-hosts)
                    target_hosts="$2"
                    shift 2
                    ;;
                *)
                    log_error "Unknown option: $1"
                    return 1
                    ;;
            esac
        done
    fi

    if [ -z "$target_hosts" ]; then
        log_error "--target-hosts is required"
        log_info "Use: cpc remove-nodes --target-hosts \"<node-name>\""
        return 1
    fi

    log_info "Removing nodes from the cluster: $target_hosts"
    
    # First drain the nodes
    log_info "Draining nodes..."
    for host in $(echo "$target_hosts" | tr ',' ' '); do
        log_info "Draining node: $host"
        ansible_run_playbook "pb_drain_node.yml" -e "node_to_drain=$host"
    done
    
    # Then delete from cluster
    log_info "Deleting nodes from cluster..."
    for host in $(echo "$target_hosts" | tr ',' ' '); do
        log_info "Deleting node: $host"
        ansible_run_playbook "pb_delete_node.yml" -e "node_to_delete=$host"
    done

    log_success "Nodes removed from cluster: $target_hosts"
}

# Drain workloads from a specific node
k8s_drain_node() {
    if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_drain_node_help
        return 1
    fi

    local node_name="$1"
    shift
    local extra_cli_opts="$*" # Pass through any remaining options like --force

    log_info "Draining node: $node_name"
    ansible_run_playbook "pb_drain_node.yml" -e "node_to_drain=$node_name" -e "drain_options=$extra_cli_opts"
}

# Upgrade Kubernetes on a specific node
k8s_upgrade_node() {
    if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_upgrade_node_help
        return 1
    fi
    
    local node_name="$1"
    shift
    
    # Parse remaining arguments
    local target_version=""
    local skip_drain="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target-version)
                target_version="$2"
                shift 2
                ;;
            --skip-drain)
                skip_drain="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local extra_vars="-e target_node=$node_name -e skip_drain=$skip_drain"
    if [ -n "$target_version" ]; then
        # Split version into major.minor and patch parts if needed
        if [[ "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # Full version like 1.33.0
            local k8s_major_minor k8s_patch
            k8s_major_minor=$(echo "$target_version" | cut -d'.' -f1-2)
            k8s_patch=$(echo "$target_version" | cut -d'.' -f3)
            extra_vars="$extra_vars -e target_k8s_version=$k8s_major_minor -e kubernetes_patch_version=$k8s_patch"
        else
            # Just major.minor like 1.33
            extra_vars="$extra_vars -e target_k8s_version=$target_version"
        fi
    fi

    log_info "Upgrading Kubernetes on node: $node_name"
    ansible_run_playbook "pb_upgrade_node.yml" -l "$node_name" $extra_vars
}

# Reset Kubernetes on a specific node
k8s_reset_node() {
    if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_reset_node_help
        return 1
    fi

    local node_name="$1"
    log_info "Resetting Kubernetes on node: $node_name"
    ansible_run_playbook "pb_reset_node.yml" -l "$node_name"
}

# Install Kubernetes components on a new VM before joining cluster
k8s_prepare_node() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_prepare_node_help
        return 0
    fi

    if [[ $# -eq 0 ]]; then
        log_error "hostname or IP address required"
        log_info "Usage: cpc prepare-node <hostname|IP>"
        log_info "Use 'cpc prepare-node --help' for more information."
        return 1
    fi

    local target_node="$1"
    log_info "Preparing node '$target_node' with Kubernetes components..."
    log_info "Installing kubelet, kubeadm, kubectl, and containerd..."
    
    if ansible_run_playbook "install_kubernetes_cluster.yml" -l "$target_node"; then
        log_success "Node '$target_node' successfully prepared!"
        log_info "Next step: Join to cluster with 'cpc add-nodes --target-hosts $target_node'"
    else
        log_error "Failed to prepare node '$target_node'"
        return 1
    fi
}

#----------------------------------------------------------------------
# Help Functions
#----------------------------------------------------------------------

# Display help for add-nodes command
k8s_show_add_nodes_help() {
    echo "Usage: cpc add-nodes [--target-hosts <hosts>] [--node-type <worker|control>]"
    echo ""
    echo "Add new nodes to the Kubernetes cluster."
    echo ""
    echo "Options:"
    echo "  --target-hosts <hosts>  Specify target hosts (default: new_workers)"
    echo "  --node-type <type>      Node type: worker or control (default: worker)"
    echo ""
    echo "Note: Ensure new nodes are added to your Terraform configuration first."
}

# Display help for remove-nodes command
k8s_show_remove_nodes_help() {
    echo "Usage: cpc remove-nodes [--target-hosts <hosts>]"
    echo "   or: cpc remove-nodes <single-host>"
    echo ""
    echo "Remove nodes from the Kubernetes cluster."
    echo "This will drain the nodes and remove them from the cluster."
    echo ""
    echo "Options:"
    echo "  --target-hosts <hosts>  Specify target hosts (comma-separated for multiple)"
    echo "  <single-host>          Single hostname to remove (without --target-hosts)"
    echo ""
    echo "Examples:"
    echo "  cpc remove-nodes worker3"
    echo "  cpc remove-nodes --target-hosts \"worker3,worker4\""
    echo ""
    echo "Note: This only removes from Kubernetes cluster."
    echo "Use 'cpc remove-vm' to destroy VMs."
}

# Display help for drain-node command
k8s_show_drain_node_help() {
    echo "Usage: cpc drain-node <node_name> [--force] [--delete-emptydir-data]"
    echo ""
    echo "Drain workloads from a specific node to prepare for maintenance."
    echo ""
    echo "Arguments:"
    echo "  <node_name>               Name of the node to drain"
    echo ""
    echo "Options:"
    echo "  --force                   Force drain even if there are standalone pods"
    echo "  --delete-emptydir-data    Delete pods using emptyDir volumes"
    echo ""
    echo "This command will safely move workloads from the specified node"
    echo "to other available nodes in the cluster."
}

# Display help for upgrade-node command
k8s_show_upgrade_node_help() {
    echo "Usage: cpc upgrade-node <node_name> [--target-version <version>] [--skip-drain]"
    echo ""
    echo "Upgrade Kubernetes on a specific node."
    echo ""
    echo "Options:"
    echo "  --target-version <version>  Target Kubernetes version (default: from environment)"
    echo "  --skip-drain               Skip draining the node before upgrade"
    echo ""
    echo "The upgrade process will:"
    echo "  1. Drain the node (unless --skip-drain is specified)"
    echo "  2. Upgrade Kubernetes packages"
    echo "  3. Restart kubelet service"
    echo "  4. Uncordon the node"
}

# Display help for reset-node command
k8s_show_reset_node_help() {
    echo "Usage: cpc reset-node <node_name_or_ip>"
    echo ""
    echo "Reset Kubernetes on a specific node."
    echo ""
    echo "Arguments:"
    echo "  <node_name_or_ip>  Name or IP address of the node to reset"
    echo ""
    echo "Warning: This will completely reset Kubernetes on the specified node."
    echo "The node will need to be rejoined to the cluster after reset."
}

# Display help for prepare-node command
k8s_show_prepare_node_help() {
    echo "Usage: cpc prepare-node <hostname|IP>"
    echo ""
    echo "Install Kubernetes components (kubelet, kubeadm, kubectl, containerd) on a new VM"
    echo "before joining it to the cluster. This prepares VMs created with 'add-vm' for cluster membership."
    echo ""
    echo "Arguments:"
    echo "  <hostname|IP>  Target VM hostname or IP address"
    echo ""
    echo "Examples:"
    echo "  cpc prepare-node wk3.bevz.net"
    echo "  cpc prepare-node 10.10.10.112"
    echo ""
    echo "After preparation, use 'cpc add-nodes --target-hosts <hostname|IP>' to join the cluster."
}

#----------------------------------------------------------------------
# Export functions for use by other modules
#----------------------------------------------------------------------
export -f cpc_k8s_nodes
export -f k8s_add_nodes
export -f k8s_remove_nodes
export -f k8s_drain_node
export -f k8s_upgrade_node
export -f k8s_reset_node
export -f k8s_prepare_node
export -f k8s_show_add_nodes_help
export -f k8s_show_remove_nodes_help
export -f k8s_show_drain_node_help
export -f k8s_show_upgrade_node_help
export -f k8s_show_reset_node_help
export -f k8s_show_prepare_node_help

#----------------------------------------------------------------------
# Module help function
#----------------------------------------------------------------------
k8s_nodes_help() {
    echo "Kubernetes Nodes Module (modules/40_k8s_nodes.sh)"
    echo "  add-nodes [opts]           - Add new worker or control plane nodes"
    echo "  remove-nodes [opts]        - Remove nodes from cluster"
    echo "  drain-node <name> [opts]   - Drain workloads from specific node"
    echo "  upgrade-node <name> [opts] - Upgrade Kubernetes on specific node"
    echo "  reset-node <name>          - Reset Kubernetes on specific node"
    echo "  prepare-node <host>        - Install K8s components on new VM"
    echo ""
    echo "Functions:"
    echo "  cpc_k8s_nodes()           - Main node command dispatcher"
    echo "  k8s_add_nodes()           - Add nodes to cluster"
    echo "  k8s_remove_nodes()        - Remove nodes from cluster"
    echo "  k8s_drain_node()          - Drain specific node"
    echo "  k8s_upgrade_node()        - Upgrade specific node"
    echo "  k8s_reset_node()          - Reset specific node"
    echo "  k8s_prepare_node()        - Prepare new VM for cluster"
}

export -f k8s_nodes_help
