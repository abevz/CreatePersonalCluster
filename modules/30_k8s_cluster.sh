#!/bin/bash

# modules/30_k8s_cluster.sh - Kubernetes Cluster Lifecycle Management Module
# Part of CPC (Create Personal Cluster) - Modular Architecture
#
# This module provides Kubernetes cluster lifecycle management functionality.
# 
# Functions provided:
# - cpc_k8s_cluster()          - Main entry point for K8s cluster commands
# - k8s_bootstrap()            - Bootstrap complete Kubernetes cluster
# - k8s_get_kubeconfig()       - Retrieve and merge cluster kubeconfig
# - k8s_upgrade()              - Upgrade Kubernetes control plane
# - k8s_reset_all_nodes()      - Reset all nodes in cluster
# - k8s_show_bootstrap_help()  - Display bootstrap help
# - k8s_show_kubeconfig_help() - Display get-kubeconfig help
# - k8s_show_upgrade_help()    - Display upgrade-k8s help
#
# Dependencies:
# - lib/logging.sh for logging functions  
# - modules/00_core.sh for core utilities like get_repo_path, get_current_cluster_context
# - modules/20_ansible.sh for ansible_run_playbook function
# - Kubernetes cluster infrastructure (deployed VMs)
# - Ansible playbooks for cluster operations

#----------------------------------------------------------------------
# Kubernetes Cluster Lifecycle Management Functions
#----------------------------------------------------------------------

# Main entry point for CPC kubernetes cluster functionality
cpc_k8s_cluster() {
    case "${1:-}" in
        bootstrap)
            shift
            k8s_bootstrap "$@"
            ;;
        get-kubeconfig)
            shift
            k8s_get_kubeconfig "$@"
            ;;
        upgrade-k8s)
            shift
            k8s_upgrade "$@"
            ;;
        reset-all-nodes)
            shift
            k8s_reset_all_nodes "$@"
            ;;
        status|cluster-status)
            shift
            k8s_cluster_status "$@"
            ;;
        *)
            log_error "Unknown k8s cluster command: ${1:-}"
            log_info "Available commands: bootstrap, get-kubeconfig, upgrade-k8s, reset-all-nodes, status"
            return 1
            ;;
    esac
}

# Bootstrap a complete Kubernetes cluster on deployed VMs
k8s_bootstrap() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_bootstrap_help
        return 0
    fi

    # Parse command line arguments
    local skip_check=false
    local force_bootstrap=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-check)
                skip_check=true
                shift
                ;;
            --force)
                force_bootstrap=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Check if secrets are loaded
    check_secrets_loaded || return 1

    local current_ctx
    current_ctx=$(get_current_cluster_context) || return 1
    local repo_root
    repo_root=$(get_repo_path) || return 1
    
    log_info "Starting Kubernetes bootstrap for context '$current_ctx'..."

    # Verify that VMs are deployed and accessible
    if [ "$skip_check" = false ]; then
        log_info "Checking VM connectivity..."
        pushd "$repo_root/terraform" > /dev/null || { 
            log_error "Failed to change to terraform directory"
            return 1
        }
        
        # Check if we're in the right workspace
        if ! tofu workspace select "$current_ctx" &>/dev/null; then
            log_error "Failed to select Tofu workspace '$current_ctx'"
            log_error "Please ensure VMs are deployed with 'cpc deploy apply'"
            popd > /dev/null
            return 1
        fi

        # Check if VMs exist
        local vm_ips
        vm_ips=$(tofu output -json k8s_node_ips 2>/dev/null)
        if [ -z "$vm_ips" ] || [ "$vm_ips" = "null" ]; then
            log_error "No VMs found in Tofu output. Please deploy VMs first with 'cpc deploy apply'"
            popd > /dev/null
            return 1
        fi

        popd > /dev/null
        log_success "VM connectivity check passed"
    fi

    # Check if cluster is already initialized (unless forced)
    if [ "$force_bootstrap" = false ]; then
        log_info "Checking if cluster is already initialized..."
        
        # Try to connect to potential control plane and check if Kubernetes is running
        pushd "$repo_root/terraform" > /dev/null || return 1
        local control_plane_ip
        control_plane_ip=$(tofu output -json k8s_node_ips 2>/dev/null | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value' | head -1)
        popd > /dev/null
        
        if [ -n "$control_plane_ip" ] && [ "$control_plane_ip" != "null" ]; then
            # Check if kubeconfig exists on control plane
            local ansible_dir="$repo_root/ansible"
            local remote_user
            remote_user=$(grep -Po '^remote_user\s*=\s*\K.*' "$ansible_dir/ansible.cfg" 2>/dev/null || echo 'root')
            
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null \
                 "${remote_user}@${control_plane_ip}" \
                 "test -f /etc/kubernetes/admin.conf" 2>/dev/null; then
                log_warning "Kubernetes cluster appears to already be initialized on $control_plane_ip"
                log_warning "Use --force to bootstrap anyway (this will reset the cluster)"
                return 1
            fi
        fi
    fi

    # Run the bootstrap playbooks
    log_success "Starting Kubernetes cluster bootstrap..."
    local ansible_dir="$repo_root/ansible"
    local inventory_file="$ansible_dir/inventory/tofu_inventory.py"

    # Check if inventory exists
    if [ ! -f "$inventory_file" ]; then
        log_error "Ansible inventory not found at $inventory_file"
        return 1
    fi

    # First, verify connectivity to all nodes
    log_info "Testing Ansible connectivity to all nodes..."
    pushd "$ansible_dir" > /dev/null || return 1
    if ! ansible all -i "$inventory_file" -m ping --ssh-extra-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"; then
        log_error "Failed to connect to all nodes via Ansible"
        log_error "Please check SSH access and ensure VMs are running"
        popd > /dev/null
        return 1
    fi
    popd > /dev/null

    log_success "Ansible connectivity test passed"

    # Step 1: Install Kubernetes components
    log_info "Step 1: Installing Kubernetes components (kubelet, kubeadm, kubectl, containerd)..."
    if ! ansible_run_playbook "install_kubernetes_cluster.yml"; then
        log_error "Failed to install Kubernetes components"
        return 1
    fi

    # Step 2: Initialize cluster and setup CNI with DNS hostname support
    log_info "Step 2: Initializing Kubernetes cluster with DNS hostname support and installing Calico CNI..."
    if ! ansible_run_playbook "initialize_kubernetes_cluster_with_dns.yml"; then
        log_error "Failed to initialize Kubernetes cluster with DNS support"
        return 1
    fi

    # Step 3: Validate cluster
    log_info "Step 3: Validating cluster installation..."
    if ! ansible_run_playbook "validate_cluster.yml" -l control_plane; then
        log_warning "Cluster validation failed, but continuing..."
    fi

    log_success "Kubernetes cluster bootstrap completed successfully!"
    log_info "Next steps:"
    log_info "  1. Get cluster access: cpc get-kubeconfig"
    log_info "  2. Install addons: cpc upgrade-addons"
    log_info "  3. Verify cluster: kubectl get nodes -o wide"
}

# Retrieve and merge Kubernetes cluster config into local kubeconfig
k8s_get_kubeconfig() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_kubeconfig_help
        return 0
    fi

    local current_ctx
    current_ctx=$(get_current_cluster_context) || return 1
    local repo_root
    repo_root=$(get_repo_path) || return 1

    log_info "Retrieving kubeconfig for cluster context '$current_ctx'..."

    # Get control plane IP from Terraform output
    pushd "$repo_root/terraform" > /dev/null || {
        log_error "Failed to change to terraform directory"
        return 1
    }

    # Ensure we're in the correct workspace
    if ! tofu workspace select "$current_ctx" &>/dev/null; then
        log_error "Failed to select Tofu workspace '$current_ctx'"
        popd > /dev/null
        return 1
    fi

    local control_plane_ip
    control_plane_ip=$(tofu output -json k8s_node_ips 2>/dev/null | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value' | head -1)
    
    if [ -z "$control_plane_ip" ] || [ "$control_plane_ip" = "null" ]; then
        log_error "No control plane IP found. Ensure VMs are deployed with 'cpc deploy apply'"
        popd > /dev/null
        return 1
    fi

    popd > /dev/null

    # Get ansible user from configuration
    local ansible_dir="$repo_root/ansible"
    local remote_user
    remote_user=$(grep -Po '^remote_user\s*=\s*\K.*' "$ansible_dir/ansible.cfg" 2>/dev/null || echo 'root')

    log_info "Connecting to control plane at $control_plane_ip..."

    # Check if kubeconfig exists on control plane
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null \
         "${remote_user}@${control_plane_ip}" \
         "test -f /etc/kubernetes/admin.conf" 2>/dev/null; then
        log_error "Kubeconfig not found on control plane. Cluster may not be initialized."
        log_error "Run 'cpc bootstrap' to initialize the cluster first."
        return 1
    fi

    # Create local kubeconfig directory if it doesn't exist
    mkdir -p ~/.kube

    # Download kubeconfig from control plane
    local temp_kubeconfig="/tmp/kubeconfig-${current_ctx}"
    if ! scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         "${remote_user}@${control_plane_ip}:/etc/kubernetes/admin.conf" \
         "$temp_kubeconfig" >/dev/null 2>&1; then
        log_error "Failed to download kubeconfig from control plane"
        return 1
    fi

    # Update server address in kubeconfig to use control plane IP
    sed -i "s|server: https://.*:6443|server: https://${control_plane_ip}:6443|g" "$temp_kubeconfig"

    # Rename cluster and context to include our context name
    sed -i "s|cluster: kubernetes|cluster: ${current_ctx}|g" "$temp_kubeconfig"
    sed -i "s|name: kubernetes|name: ${current_ctx}|g" "$temp_kubeconfig"
    sed -i "s|context: kubernetes-admin@kubernetes|context: kubernetes-admin@${current_ctx}|g" "$temp_kubeconfig"
    sed -i "s|current-context: kubernetes-admin@kubernetes|current-context: kubernetes-admin@${current_ctx}|g" "$temp_kubeconfig"

    # Merge with existing kubeconfig
    if [ -f ~/.kube/config ]; then
        # Backup existing config
        cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d_%H%M%S)
        log_info "Backed up existing kubeconfig"
        
        # Merge configurations
        KUBECONFIG="$temp_kubeconfig:~/.kube/config" kubectl config view --flatten > ~/.kube/config.new
        mv ~/.kube/config.new ~/.kube/config
    else
        # No existing config, just copy
        cp "$temp_kubeconfig" ~/.kube/config
    fi

    # Set current context
    kubectl config use-context "kubernetes-admin@${current_ctx}"

    # Cleanup
    rm -f "$temp_kubeconfig"

    log_success "Kubeconfig retrieved and merged successfully!"
    log_info "Current context set to: kubernetes-admin@${current_ctx}"
    log_info "Test cluster access with: kubectl get nodes"
}

# Upgrade Kubernetes control plane components
k8s_upgrade() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_upgrade_help
        return 0
    fi

    # Parse command line arguments
    local target_version=""
    local skip_etcd_backup="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target-version)
                target_version="$2"
                shift 2
                ;;
            --skip-etcd-backup)
                skip_etcd_backup="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Confirmation prompt
    local current_ctx
    current_ctx=$(get_current_cluster_context) || return 1
    
    log_warning "This will upgrade the Kubernetes control plane for context '$current_ctx'."
    read -r -p "Are you sure you want to continue? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log_info "Operation cancelled."
        return 0
    fi

    log_info "Upgrading Kubernetes control plane..."
    
    local extra_args=()
    extra_args+=("-e" "skip_etcd_backup=$skip_etcd_backup")
    
    if [ -n "$target_version" ]; then
        extra_args+=("-e" "target_k8s_version=$target_version")
    fi

    ansible_run_playbook "pb_upgrade_k8s_control_plane.yml" -l control_plane "${extra_args[@]}"
}

# Reset all nodes in the cluster
k8s_reset_all_nodes() {
    local current_ctx
    current_ctx=$(get_current_cluster_context) || return 1
    
    read -r -p "Are you sure you want to reset Kubernetes on ALL nodes in context '$current_ctx'? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log_warning "Resetting all Kubernetes nodes..."
        ansible_run_playbook "pb_reset_all_nodes.yml"
    else
        log_info "Operation cancelled."
    fi
}

#----------------------------------------------------------------------
# Help Functions
#----------------------------------------------------------------------

# Display help for bootstrap command
k8s_show_bootstrap_help() {
    echo "Usage: cpc bootstrap [--skip-check] [--force]"
    echo ""
    echo "Bootstrap a complete Kubernetes cluster on the deployed VMs."
    echo ""
    echo "The bootstrap process includes:"
    echo "  1. Install Kubernetes components (kubelet, kubeadm, kubectl, containerd)"
    echo "  2. Initialize control plane with kubeadm"
    echo "  3. Install Calico CNI plugin"
    echo "  4. Join worker nodes to the cluster"
    echo "  5. Configure kubectl access for the cluster"
    echo ""
    echo "Options:"
    echo "  --skip-check   Skip VM connectivity check before starting"
    echo "  --force        Force bootstrap even if cluster appears already initialized"
    echo ""
    echo "Prerequisites:"
    echo "  - VMs must be deployed and accessible (use 'cpc deploy apply')"
    echo "  - SSH access configured to all nodes"
    echo "  - SOPS secrets loaded for VM authentication"
    echo ""
    echo "Example workflow:"
    echo "  cpc ctx ubuntu           # Set context"
    echo "  cpc deploy apply         # Deploy VMs"
    echo "  cpc bootstrap           # Bootstrap Kubernetes cluster"
    echo "  cpc get-kubeconfig      # Get cluster access"
}

# Display help for get-kubeconfig command
k8s_show_kubeconfig_help() {
    echo "Usage: cpc get-kubeconfig"
    echo ""
    echo "Retrieve and merge Kubernetes cluster config into local kubeconfig."
    echo ""
    echo "This command will:"
    echo "  1. Connect to the control plane node"
    echo "  2. Download the admin kubeconfig"
    echo "  3. Update server address to use control plane IP"
    echo "  4. Merge with existing ~/.kube/config (backing up original)"
    echo "  5. Set the current context to the cluster"
    echo ""
    echo "Prerequisites:"
    echo "  - Kubernetes cluster must be bootstrapped ('cpc bootstrap')"
    echo "  - SSH access to control plane node"
    echo "  - kubectl command available locally"
    echo ""
    echo "Example:"
    echo "  cpc get-kubeconfig      # Get cluster access"
    echo "  kubectl get nodes       # Test cluster access"
}

# Display help for upgrade-k8s command
k8s_show_upgrade_help() {
    echo "Usage: cpc upgrade-k8s [--target-version <version>] [--skip-etcd-backup]"
    echo ""
    echo "Upgrade Kubernetes control plane components."
    echo ""
    echo "Options:"
    echo "  --target-version <version>  Target Kubernetes version (default: from environment)"
    echo "  --skip-etcd-backup         Skip etcd backup before upgrade"
    echo ""
    echo "The upgrade process will:"
    echo "  1. Backup etcd (unless --skip-etcd-backup is specified)"
    echo "  2. Upgrade control plane components on each control plane node"
    echo "  3. Verify cluster health after upgrade"
    echo ""
    echo "Warning: This will upgrade the control plane. Ensure you have backups!"
}

# Check Kubernetes cluster status and health
k8s_cluster_status() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: cpc status|cluster-status"
        echo ""
        echo "Check Kubernetes cluster status and health in the current workspace."
        echo "This command will:"
        echo "1. Check if VMs are running"
        echo "2. Test SSH connectivity to nodes"
        echo "3. Check Kubernetes cluster status"
        echo "4. Verify core components"
        echo "5. Show cluster info (nodes, pods, services)"
        echo ""
        echo "No options required - uses current workspace context."
        return 0
    fi

    local current_ctx
    current_ctx=$(get_current_cluster_context) || return 1
    
    log_info "=== Kubernetes Cluster Status Check ==="
    log_info "Workspace: $current_ctx"
    echo ""
    
    # 1. Check VM infrastructure status
    log_info "📋 1. Checking VM infrastructure..."
    
    # Use the same mechanism as cluster-info to get cluster data
    local tf_dir="$REPO_PATH/terraform"
    local cluster_data=""
    
    pushd "$tf_dir" >/dev/null 2>&1 || { 
        log_error "Failed to change to terraform directory"
        return 1
    }
    
    # Ensure we're in the correct workspace
    if tofu workspace select "$current_ctx" &>/dev/null; then
        cluster_data=$(tofu output -json cluster_summary 2>/dev/null)
        if [ $? -eq 0 ] && [ "$cluster_data" != "null" ] && [ -n "$cluster_data" ]; then
            # Extract the actual data (handle both .value and direct JSON)
            local json_data
            if echo "$cluster_data" | jq -e '.value' >/dev/null 2>&1; then
                json_data=$(echo "$cluster_data" | jq '.value')
            else
                json_data="$cluster_data"
            fi
            
            local vm_count
            vm_count=$(echo "$json_data" | jq '. | length' 2>/dev/null || echo "0")
            
            if [[ "$vm_count" -gt 0 ]]; then
                log_success "VMs deployed: $vm_count"
                # Show brief cluster info
                echo ""
                echo -e "${GREEN}Cluster VMs:${ENDCOLOR}"
                echo "$json_data" | jq -r 'to_entries[] | "  ✓ \(.key) (\(.value.hostname)) - \(.value.IP)"'
            else
                log_error "No VMs found in cluster summary"
                popd >/dev/null
                return 1
            fi
        else
            log_error "No VMs found or unable to get cluster info"
            log_info "Run 'cpc deploy apply' to create infrastructure"
            popd >/dev/null
            return 1
        fi
    else
        log_error "Failed to select Tofu workspace '$current_ctx'"
        popd >/dev/null
        return 1
    fi
    
    popd >/dev/null
    echo ""
    
    # 2. Check SSH connectivity
    log_info "🔗 2. Testing SSH connectivity..."
    if command -v ansible-inventory &> /dev/null; then
        local hosts_reachable=0
        local hosts_total=0
        
        # Get all hosts from inventory
        while IFS= read -r host; do
            if [[ -n "$host" && "$host" != "null" ]]; then
                hosts_total=$((hosts_total + 1))
                if timeout 5 ansible "$host" -m ping &>/dev/null; then
                    hosts_reachable=$((hosts_reachable + 1))
                    log_success "✓ $host - reachable"
                else
                    log_error "✗ $host - unreachable"
                fi
            fi
        done < <(ansible-inventory --list 2>/dev/null | jq -r '.all.hosts[]?' 2>/dev/null || echo "")
        
        if [[ $hosts_total -eq 0 ]]; then
            log_warning "No hosts found in inventory. Run 'cpc update-inventory' first."
        elif [[ $hosts_reachable -eq $hosts_total ]]; then
            log_success "All $hosts_total hosts reachable via SSH"
        else
            log_warning "$hosts_reachable/$hosts_total hosts reachable"
        fi
    else
        log_warning "ansible-inventory not available, skipping SSH check"
    fi
    echo ""
    
    # 3. Check Kubernetes cluster
    log_info "⚙️ 3. Checking Kubernetes cluster status..."
    if command -v kubectl &> /dev/null; then
        # Try to get cluster info
        if kubectl cluster-info &>/dev/null; then
            log_success "Kubernetes cluster is accessible"
            
            # Get nodes status
            local nodes_ready=0
            local nodes_total=0
            
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    nodes_total=$((nodes_total + 1))
                    if echo "$line" | grep -q "Ready"; then
                        nodes_ready=$((nodes_ready + 1))
                        log_success "✓ $(echo "$line" | awk '{print $1}') - Ready"
                    else
                        log_warning "⚠ $(echo "$line" | awk '{print $1}') - $(echo "$line" | awk '{print $2}')"
                    fi
                fi
            done < <(kubectl get nodes --no-headers 2>/dev/null | grep -v '^$' || echo "")
            
            if [[ $nodes_total -eq 0 ]]; then
                log_error "No nodes found in cluster"
            elif [[ $nodes_ready -eq $nodes_total ]]; then
                log_success "All $nodes_total nodes are Ready"
            else
                log_warning "$nodes_ready/$nodes_total nodes are Ready"
            fi
            
        else
            log_error "Cannot connect to Kubernetes cluster"
            log_info "Try running 'cpc get-kubeconfig' to retrieve cluster config"
        fi
    else
        log_warning "kubectl not available, skipping Kubernetes check"
    fi
    echo ""
    
    # 4. Show summary
    log_info "📊 4. Cluster Summary:"
    if kubectl get nodes &>/dev/null; then
        echo "Nodes:"
        kubectl get nodes 2>/dev/null || log_error "Failed to get nodes"
        echo ""
        echo "System Pods:"
        kubectl get pods -n kube-system --no-headers 2>/dev/null | awk '{print $1, $3}' | head -10 || log_error "Failed to get system pods"
        echo ""
        echo "Cluster version:"
        kubectl version --short 2>/dev/null || log_error "Failed to get cluster version"
    else
        log_error "Kubernetes cluster not accessible"
        log_info ""
        log_info "💡 Next steps:"
        log_info "  1. If VMs are running but cluster is not accessible:"
        log_info "     → cpc get-kubeconfig"
        log_info "  2. If cluster is not bootstrapped:"
        log_info "     → cpc bootstrap"
        log_info "  3. If VMs are not deployed:"
        log_info "     → cpc deploy apply"
    fi
}

#----------------------------------------------------------------------
# Export functions for use by other modules
#----------------------------------------------------------------------
export -f cpc_k8s_cluster
export -f k8s_bootstrap
export -f k8s_get_kubeconfig
export -f k8s_upgrade
export -f k8s_reset_all_nodes
export -f k8s_cluster_status
export -f k8s_show_bootstrap_help
export -f k8s_show_kubeconfig_help
export -f k8s_show_upgrade_help

#----------------------------------------------------------------------
# Module help function
#----------------------------------------------------------------------
k8s_cluster_help() {
    echo "Kubernetes Cluster Module (modules/30_k8s_cluster.sh)"
    echo "  bootstrap [opts]           - Bootstrap complete Kubernetes cluster"
    echo "  get-kubeconfig            - Retrieve and merge cluster kubeconfig"
    echo "  upgrade-k8s [opts]        - Upgrade Kubernetes control plane"
    echo "  reset-all-nodes           - Reset all nodes in cluster"
    echo "  status|cluster-status     - Check cluster status and health"
    echo ""
    echo "Functions:"
    echo "  cpc_k8s_cluster()         - Main cluster command dispatcher"
    echo "  k8s_bootstrap()           - Complete cluster bootstrap process"
    echo "  k8s_get_kubeconfig()      - Retrieve and merge kubeconfig"
    echo "  k8s_upgrade()             - Upgrade control plane components"
    echo "  k8s_reset_all_nodes()     - Reset all cluster nodes"
    echo "  k8s_cluster_status()      - Check cluster status and health"
}

export -f k8s_cluster_help
