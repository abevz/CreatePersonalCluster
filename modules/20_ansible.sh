#!/bin/bash

# modules/20_ansible.sh - Ansible Playbook Management Module
# Part of CPC (Create Personal Cluster) - Modular Architecture
#
# This module provides Ansible playbook execution and inventory management functionality.
# 
# Functions provided:
# - cpc_ansible()              - Main entry point for ansible command
# - ansible_run_playbook()     - Execute Ansible playbooks with proper inventory and context
# - ansible_show_help()        - Display help for run-ansible command
# - ansible_list_playbooks()   - List available playbooks in the repository
# - ansible_update_inventory_cache() - Update inventory cache from Terraform state
#
# Dependencies:
# - lib/logging.sh for logging functions  
# - modules/00_core.sh for core utilities like get_repo_path, get_current_cluster_context
# - Ansible installation and proper ansible.cfg configuration
# - Terraform/OpenTofu state for inventory generation

#----------------------------------------------------------------------
# Ansible Playbook Management Functions
#----------------------------------------------------------------------

# Main entry point for CPC ansible functionality
cpc_ansible() {
    case "${1:-}" in
        run-ansible)
            shift
            ansible_run_playbook_command "$@"
            ;;
        run-command)
            shift
            if [[ "$1" == "-h" || "$1" == "--help" ]] || [[ $# -lt 2 ]]; then
                ansible_show_run_command_help
                return 0
            fi
            ansible_run_shell_command "$@"
            ;;
        *)
            log_error "Unknown ansible command: ${1:-}"
            log_info "Available commands: run-ansible, run-command"
            return 1
            ;;
    esac
}

# Handle the run-ansible command with help and validation
ansible_run_playbook_command() {
    if [[ "$1" == "-h" || "$1" == "--help" ]] || [[ $# -eq 0 ]]; then
        ansible_show_help
        return 0
    fi

    local playbook_name="$1"
    shift # Remove playbook name, rest are ansible options

    # Validate playbook exists
    local repo_path
    repo_path=$(get_repo_path) || return 1
    local playbook_path="$repo_path/ansible/playbooks/$playbook_name"
    
    if [[ ! -f "$playbook_path" ]]; then
        log_error "Playbook '$playbook_name' not found at $playbook_path"
        log_info "Available playbooks:"
        ansible_list_playbooks
        return 1
    fi

    log_info "Running Ansible playbook: $playbook_name"
    ansible_run_playbook "$playbook_name" "$@"
}

# Display help information for the run-ansible command
ansible_show_help() {
    echo "Usage: cpc run-ansible <playbook_name> [ansible_options]"
    echo ""
    echo "Runs the specified Ansible playbook from the ansible/playbooks/ directory"
    echo "using the current cpc context for inventory and configuration."
    echo ""
    echo "Key features:"
    echo "  - Automatically uses the Tofu inventory for the current context"
    echo "  - Sets ansible_user from ansible.cfg configuration"
    echo "  - Passes current cluster context and Kubernetes version as variables"
    echo "  - Uses SSH settings optimized for VM connections"
    echo ""
    echo "Examples:"
    echo "  cpc run-ansible initialize_kubernetes_cluster_with_dns.yml"
    echo "  cpc run-ansible regenerate_certificates_with_dns.yml"
    echo "  cpc run-ansible deploy_kubernetes_cluster.yml"
    echo "  cpc run-ansible bootstrap_master_node.yml --check"
    echo ""
    echo "Available playbooks (run 'ls \$REPO_PATH/ansible/playbooks/' to see all):"
    ansible_list_playbooks
}

# List available Ansible playbooks in the repository
ansible_list_playbooks() {
    local repo_path
    repo_path=$(get_repo_path) || return 1
    
    if [ -d "$repo_path/ansible/playbooks" ]; then
        ls "$repo_path/ansible/playbooks"/*.yml "$repo_path/ansible/playbooks"/*.yaml 2>/dev/null | xargs -n1 basename | sed 's/^/  - /' || log_warning "No playbooks found in $repo_path/ansible/playbooks"
    else
        log_warning "Ansible playbooks directory not found at $repo_path/ansible/playbooks"
    fi
}

# Execute a shell command on target hosts using Ansible
ansible_run_shell_command() {
    if [[ $# -lt 2 ]]; then
        ansible_show_run_command_help
        return 1
    fi
    
    local target="$1"
    local shell_cmd="$2"
    
    log_info "Running command on $target: $shell_cmd"
    ansible_run_playbook "pb_run_command.yml" -l "$target" -e "command_to_run=$shell_cmd"
}

# Display help information for the run-command function
ansible_show_run_command_help() {
    echo "Usage: cpc run-command <target_hosts_or_group> \"<shell_command_to_run>\""
    echo ""
    echo "Runs a shell command on specified hosts or groups using Ansible."
    echo ""
    echo "Parameters:"
    echo "  target_hosts_or_group   - Target hosts or inventory groups"
    echo "  shell_command_to_run    - Shell command to execute"
    echo ""
    echo "Examples:"
    echo "  cpc run-command control_plane \"hostname -f\""
    echo "  cpc run-command all \"sudo apt update\""
    echo "  cpc run-command workers \"systemctl status kubelet\""
    echo ""
    echo "Available target groups: all, control_plane, workers"
}

# Execute Ansible playbooks with proper context and inventory
ansible_run_playbook() {
    local playbook_name="$1"
    shift # Remove playbook name, rest are ansible options

    local repo_root
    repo_root=$(get_repo_path) || return 1
    local ansible_dir="$repo_root/ansible"
    local inventory_file="$ansible_dir/inventory/tofu_inventory.py"

    # Validate inventory file exists and is executable
    if [ ! -f "$inventory_file" ]; then
        log_error "Ansible inventory file not found at $inventory_file"
        log_error "Ensure Tofu has been run and the inventory script is in place."
        return 1
    fi

    if [ ! -x "$inventory_file" ]; then
        log_warning "Inventory script $inventory_file is not executable. Attempting to chmod +x."
        chmod +x "$inventory_file"
        if [ ! -x "$inventory_file" ]; then
            log_error "Failed to make inventory script $inventory_file executable."
            return 1
        fi
    fi

    local current_cluster
    current_cluster=$(get_current_cluster_context) || return 1

    # Change to ansible directory
    pushd "$ansible_dir" > /dev/null || { 
        log_error "Failed to change directory to $ansible_dir"
        return 1
    }

    # Build ansible command array
    local ansible_cmd_array=(
        "ansible-playbook"
        "-i" "$inventory_file"
        "playbooks/$playbook_name"
        "--ssh-extra-args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    )

    # Add common extra vars
    local ansible_user
    ansible_user=$(grep -Po '^remote_user\s*=\s*\K.*' ansible.cfg || echo 'root')
    ansible_cmd_array+=("-e" "ansible_user=$ansible_user")
    ansible_cmd_array+=("-e" "current_cluster_context=$current_cluster")
    
    # Remove 'v' prefix from kubernetes version if present, default to 1.31
    local k8s_version="${KUBERNETES_VERSION:-v1.31}"
    k8s_version="${k8s_version#v}"  # Remove 'v' prefix
    ansible_cmd_array+=("-e" "kubernetes_version=$k8s_version")
    ansible_cmd_array+=("-e" "kubernetes_patch_version=${kubernetes_patch_version:-latest}")
    
    # Add version variables for addons (pass from workspace environment)
    ansible_cmd_array+=("-e" "calico_version=${CALICO_VERSION:-v3.28.0}")
    ansible_cmd_array+=("-e" "metallb_version=${METALLB_VERSION:-v0.14.8}")
    ansible_cmd_array+=("-e" "coredns_version=${COREDNS_VERSION:-v1.11.3}")
    ansible_cmd_array+=("-e" "metrics_server_version=${METRICS_SERVER_VERSION:-v0.7.2}")
    ansible_cmd_array+=("-e" "cert_manager_version=${CERT_MANAGER_VERSION:-v1.16.2}")
    ansible_cmd_array+=("-e" "argocd_version=${ARGOCD_VERSION:-v2.13.2}")
    ansible_cmd_array+=("-e" "ingress_nginx_version=${INGRESS_NGINX_VERSION:-v1.12.0}")
    ansible_cmd_array+=("-e" "kubelet_serving_cert_approver_version=${KUBELET_SERVING_CERT_APPROVER_VERSION:-v0.1.9}")
    ansible_cmd_array+=("-e" "local_path_provisioner_version=${LOCAL_PATH_PROVISIONER_VERSION:-v0.0.28}")
    ansible_cmd_array+=("-e" "cni_plugins_version=${CNI_PLUGINS_VERSION:-v1.5.0}")
    ansible_cmd_array+=("-e" "etcd_version=${ETCD_VERSION:-v3.5.15}")

    # Add all remaining user-provided arguments
    if [[ $# -gt 0 ]]; then
        ansible_cmd_array+=("$@")
    fi

    log_info "Running: ${ansible_cmd_array[*]}"
    
    # Update inventory cache before running ansible
    ansible_update_inventory_cache
    
    # Execute the ansible command
    "${ansible_cmd_array[@]}"
    local exit_code=$?

    popd > /dev/null || return 1

    if [ $exit_code -ne 0 ]; then
        log_error "Ansible playbook $playbook_name failed with exit code $exit_code."
        return 1
    fi
    
    log_success "Ansible playbook $playbook_name completed successfully"
    return 0
}

# Update Ansible inventory cache from Terraform state
ansible_update_inventory_cache() {
    log_info "Updating inventory cache..."
    local repo_root
    repo_root=$(get_repo_path) || return 1
    local cache_file="$repo_root/.ansible_inventory_cache.json"
    local terraform_dir="$repo_root/terraform"
    
    if [ -d "$terraform_dir" ]; then
        pushd "$terraform_dir" > /dev/null || true
        
        local cluster_summary
        cluster_summary=$(tofu output -json cluster_summary 2>/dev/null | jq -r '.value // empty')
        
        if [ -n "$cluster_summary" ]; then
            # Generate inventory from cluster_summary
            local inventory_json
            inventory_json=$(echo "$cluster_summary" | jq '{
                "_meta": {
                    "hostvars": (
                        to_entries | map({
                            key: .value.IP,
                            value: {
                                "ansible_host": .value.IP,
                                "node_name": .key,
                                "hostname": .value.hostname,
                                "vm_id": .value.VM_ID,
                                "k8s_role": (if (.key | contains("controlplane")) then "control-plane" else "worker" end)
                            }
                        }) | from_entries
                    )
                },
                "all": {
                    "children": ["control_plane", "workers"]
                },
                "control_plane": {
                    "hosts": [to_entries | map(select(.key | contains("controlplane")) | .value.IP) | .[]]
                },
                "workers": {
                    "hosts": [to_entries | map(select(.key | contains("worker")) | .value.IP) | .[]]
                }
            }')
            
            # Write to cache file
            echo "$inventory_json" > "$cache_file"
            log_success "Inventory cache updated"
        else
            log_warning "Could not get cluster_summary from terraform, using existing cache"
        fi
        
        popd > /dev/null || true
    else
        log_warning "Terraform directory not found at $terraform_dir"
    fi
}

#----------------------------------------------------------------------
# Export functions for use by other modules
#----------------------------------------------------------------------
export -f cpc_ansible
export -f ansible_run_playbook_command
export -f ansible_run_shell_command
export -f ansible_run_playbook
export -f ansible_show_help
export -f ansible_show_run_command_help
export -f ansible_list_playbooks
export -f ansible_update_inventory_cache

#----------------------------------------------------------------------
# Module help function
#----------------------------------------------------------------------
ansible_help() {
    echo "Ansible Module (modules/20_ansible.sh)"
    echo "  run-ansible <playbook> [opts] - Execute Ansible playbook with context"
    echo ""
    echo "Functions:"
    echo "  cpc_ansible()                  - Main ansible command dispatcher"
    echo "  ansible_run_playbook()         - Execute playbooks with inventory and context"
    echo "  ansible_show_help()            - Display run-ansible help"
    echo "  ansible_list_playbooks()       - List available playbooks"
    echo "  ansible_update_inventory_cache() - Update inventory cache from Terraform"
}

export -f ansible_help
