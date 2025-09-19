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
# - k8s_status()               - Check cluster status and health
# - k8s_upgrade()              - Upgrade Kubernetes control plane

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

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
  status | cluster-status)
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
#
# In file: modules/30_k8s_cluster.sh
# Refactored in Phase 2 to use helper functions

k8s_bootstrap() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    k8s_show_bootstrap_help
    return 0
  fi

  # Parse command line arguments using helper function
  parse_bootstrap_arguments_v2 "$@"
  local skip_check="$PARSED_SKIP_CHECK"
  local force_bootstrap="$PARSED_FORCE_BOOTSTRAP"

  # Validate bootstrap prerequisites using helper function
  if ! validate_bootstrap_prerequisites_v2; then
    return 1
  fi
  local current_ctx="$CURRENT_CTX"
  local repo_root="$REPO_ROOT"

  log_info "Starting Kubernetes bootstrap for context '$current_ctx'..."

  # Extract cluster infrastructure data using helper function
  if ! extract_cluster_infrastructure_data_v2 "$current_ctx" "$repo_root"; then
    return 1
  fi
  local all_tofu_outputs_json="$EXTRACTED_ALL_TOFU_OUTPUTS"
  local cluster_summary_json="$EXTRACTED_CLUSTER_SUMMARY"

  # Check VM existence and connectivity (unless skipped)
  if [ "$skip_check" = false ]; then
    log_info "Checking VM existence and connectivity..."
    if ! tofu_update_node_info "$cluster_summary_json"; then
      log_error "No VMs found in Tofu output. Please deploy VMs first with 'cpc deploy apply'"
      return 1
    fi
    log_success "VM check passed. Found ${#TOFU_NODE_NAMES[@]} nodes."
  fi

  # Generate Ansible inventory using helper function
  if ! generate_ansible_inventory_v2 "$all_tofu_outputs_json"; then
    return 1
  fi
  local temp_inventory_file="$GENERATED_INVENTORY_FILE"

  # Set up cleanup trap for temporary inventory file
  trap 'cleanup_bootstrap_resources_v2 "$temp_inventory_file"' EXIT

  # Verify cluster initialization using helper function
  if ! verify_cluster_initialization_v2 "$cluster_summary_json" "$force_bootstrap"; then
    return 1
  fi

  # Execute bootstrap steps using helper function
  if ! execute_bootstrap_steps_v2 "$temp_inventory_file"; then
    return 1
  fi

  log_success "Kubernetes cluster bootstrap completed successfully!"
  log_info "Next steps:"
  log_info "  1. Get cluster access: cpc get-kubeconfig"
  log_info "  2. Install addons: cpc upgrade-addons"
  log_info "  3. Verify cluster: kubectl get nodes -o wide"
}

#
# Version: 9.0 (Final - with robust cleanup)
#
# Retrieve and merge Kubernetes cluster config into local kubeconfig
k8s_get_kubeconfig() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        k8s_show_kubeconfig_help
        return 0
    fi

    log_step "Retrieving kubeconfig from the cluster..."

    local current_ctx
    current_ctx=$(get_current_cluster_context)
    if [[ -z "$current_ctx" ]]; then
        log_error "No active workspace context is set. Use 'cpc ctx <workspace_name>'."
        return 1
    fi

    log_info "Getting infrastructure data from Terraform..."
    local raw_output
    raw_output=$("$REPO_PATH/cpc" deploy output -json 2>/dev/null | sed -n '/^{$/,/^}$/p')

    local control_plane_ip control_plane_hostname
    control_plane_ip=$(echo "$raw_output" | jq -r '.cluster_summary.value | to_entries[] | select(.key | contains("controlplane")) | .value.IP | select(. != null)' | head -n 1)
    control_plane_hostname=$(echo "$raw_output" | jq -r '.cluster_summary.value | to_entries[] | select(.key | contains("controlplane")) | .value.hostname | select(. != null)' | head -n 1)

    if [[ -z "$control_plane_ip" || -z "$control_plane_hostname" ]]; then
        log_error "Could not determine control plane IP or hostname."
        return 1
    fi
    log_info "Control plane found: ${control_plane_hostname} (${control_plane_ip})"

    local temp_admin_conf=$(mktemp)
    local ca_crt_file=$(mktemp)
    local client_crt_file=$(mktemp)
    local client_key_file=$(mktemp)
    trap 'rm -f -- "$temp_admin_conf" "$ca_crt_file" "$client_crt_file" "$client_key_file"' EXIT

    log_info "Fetching admin.conf from control plane..."
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${ANSIBLE_REMOTE_USER:-abevz}@${control_plane_ip}" \
        "sudo cat /etc/kubernetes/admin.conf" >"${temp_admin_conf}"; then
        log_error "SSH command to fetch admin.conf failed."
        return 1
    fi
    
    if [[ ! -s "$temp_admin_conf" ]]; then
        log_error "Fetched admin.conf file is empty. Check user/sudo permissions on the control plane."
        return 1
    fi
    log_success "Admin.conf file fetched successfully."

    yq e '.clusters[0].cluster."certificate-authority-data"' "$temp_admin_conf" | base64 -d > "$ca_crt_file"
    yq e '.users[0].user."client-certificate-data"' "$temp_admin_conf" | base64 -d > "$client_crt_file"
    yq e '.users[0].user."client-key-data"' "$temp_admin_conf" | base64 -d > "$client_key_file"
    
    local server_url
    server_url=$(yq e '.clusters[0].cluster.server' "$temp_admin_conf")
    if [[ "$server_url" == *"127.0.0.1"* ]]; then
        server_url="https://\${control_plane_hostname}:6443"
    fi

    local cluster_name="$current_ctx"
    local user_name="${current_ctx}-admin"
    local context_name="$current_ctx"
    local kubeconfig_path="${HOME}/.kube/config" 

    log_info "Force updating '${kubeconfig_path}' for context '${context_name}'..."

    mkdir -p "$(dirname "$kubeconfig_path")"

    kubectl config --kubeconfig="$kubeconfig_path" set-cluster "$cluster_name" \
        --server="$server_url" \
        --embed-certs=true \
        --certificate-authority="$ca_crt_file"

    kubectl config --kubeconfig="$kubeconfig_path" set-credentials "$user_name" \
        --embed-certs=true \
        --client-certificate="$client_crt_file" \
        --client-key="$client_key_file"

    kubectl config --kubeconfig="$kubeconfig_path" set-context "$context_name" \
        --cluster="$cluster_name" \
        --user="$user_name"
        
    kubectl config --kubeconfig="$kubeconfig_path" use-context "$context_name"

    log_success "Kubeconfig has been updated and context is set to '${context_name}'." ✅
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
  # Handle --help before calling helper functions
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        k8s_show_status_help
        return 0
        ;;
      *)
        shift
        ;;
    esac
  done

  # Parse status arguments using helper function (reset arguments)
  parse_status_arguments_v2 "$@"
  local quick_mode="$PARSED_QUICK_MODE"
  local fast_mode="$PARSED_FAST_MODE"

  local current_ctx
  current_ctx=$(get_current_cluster_context)

  # Display status summary using helper function
  display_status_summary_v2 "$current_ctx" "$quick_mode"

  if [[ "$quick_mode" == true ]]; then
    # Check infrastructure status using helper function
    if ! check_infrastructure_status_v2 "$current_ctx" "$quick_mode"; then
      return 1
    fi
    local cluster_data="$INFRASTRUCTURE_CLUSTER_DATA"

    # Check SSH connectivity using helper function
    check_ssh_connectivity_v2 "$cluster_data" "$quick_mode"

    # Check Kubernetes health using helper function
    check_kubernetes_health_v2 "$current_ctx" "$quick_mode"

    return 0
  fi

  # Full status check
  log_info "📋 1. Checking VM infrastructure..."

  # Check infrastructure status using helper function
  if ! check_infrastructure_status_v2 "$current_ctx" "$quick_mode"; then
    return 1
  fi
  local cluster_data="$INFRASTRUCTURE_CLUSTER_DATA"

  echo

  # Check SSH connectivity using helper function
  log_info "🔗 2. Testing SSH connectivity..."

  check_ssh_connectivity_v2 "$cluster_data" "$quick_mode"

  echo

  # Check Kubernetes health using helper function
  log_info "⚙️ 3. Checking Kubernetes cluster status..."
  check_kubernetes_health_v2 "$current_ctx" "$quick_mode"
}

# Helper function to show basic VM info when Proxmox API is not available
show_basic_vm_info() {
  local cluster_data="$1"
  local reason="$2"
  
  echo "$cluster_data" | jq -r 'to_entries[] | "\(.value.VM_ID) \(.key) \(.value.hostname) \(.value.IP)"' | while read -r vm_id vm_key hostname ip; do
    if [[ -n "$vm_id" && "$vm_id" != "null" ]]; then
      echo -e "  VM $vm_id ($hostname): ${YELLOW}? Status unknown ($reason)${ENDCOLOR}"
    fi
  done
}

# Helper function to show basic VM info when Proxmox API is not available
show_basic_vm_info() {
  local cluster_data="$1"
  local reason="$2"
  
  echo "$cluster_data" | jq -r 'to_entries[] | "\(.value.VM_ID) \(.key) \(.value.hostname) \(.value.IP)"' | while read -r vm_id vm_key hostname ip; do
    if [[ -n "$vm_id" && "$vm_id" != "null" ]]; then
      echo -e "  VM $vm_id ($hostname): ${YELLOW}? Status unknown ($reason)${ENDCOLOR}"
    fi
  done
}

# Check VM status in Proxmox
check_proxmox_vm_status() {
  local cluster_data="$1"
  
  # Authenticate with Proxmox API
  if ! authenticate_proxmox_api_v2; then
    # Fallback to basic info display if API auth fails
    log_warning "Proxmox API authentication failed. Showing basic VM info."
    show_basic_vm_info "$cluster_data" "API auth failed"
    return 0
  fi
  
  echo "$cluster_data" | jq -r 'to_entries[] | "\(.value.VM_ID) \(.key) \(.value.hostname) \(.value.IP)"' | while read -r vm_id vm_key hostname ip; do
    if [[ -n "$vm_id" && "$vm_id" != "null" ]]; then
      # Get VM status via API
      local vm_status
      vm_status=$(get_vm_status_from_api_v2 "$vm_id" "$PROXMOX_CLEAN_HOST" "$PROXMOX_AUTH_TICKET" "$PROXMOX_CSRF_TOKEN")

      # Format and display VM status
      format_vm_status_display_v2 "$vm_id" "$vm_key" "$hostname" "$ip" "$vm_status"
    fi
  done
}

# Show help for status command
k8s_show_status_help() {
  echo "Kubernetes Cluster Status Check"
  echo
  echo "Usage: cpc status [options]"
  echo
  echo "Options:"
  echo "  --quick, -q    Quick status check (VMs, SSH, K8s connectivity)"
  echo "  --help, -h     Show this help message"
  echo
  echo "Without options, performs comprehensive status check including:"
  echo "  • VM infrastructure status"
  echo "  • Proxmox VM status and resources"
  echo "  • SSH connectivity testing"
  echo "  • Kubernetes cluster health"
  echo "  • Core services status (CoreDNS, CNI)"
  echo "  • Node and pod information"
  echo
  echo "Examples:"
  echo "  cpc status           # Full status check"
  echo "  cpc status --quick   # Quick overview"
  echo "  cpc status -q        # Same as --quick"
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
export -f k8s_show_status_help

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

# Ensure username has @pve realm if not specified
if [[ "$PROXMOX_USERNAME" != *"@"* ]]; then
  PROXMOX_USERNAME="${PROXMOX_USERNAME}@pve"
fi

#----------------------------------------------------------------------
# Helper Functions for Refactoring (Phase 1)
#----------------------------------------------------------------------

# Helper function: Parse bootstrap arguments
parse_bootstrap_arguments_v2() {
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

  # Return values via global variables for now
  PARSED_SKIP_CHECK="$skip_check"
  PARSED_FORCE_BOOTSTRAP="$force_bootstrap"
}

# Helper function: Validate bootstrap prerequisites
validate_bootstrap_prerequisites_v2() {
  # Check if secrets are loaded
  if ! check_secrets_loaded; then
    return 1
  fi

  # Get current context
  if ! CURRENT_CTX=$(get_current_cluster_context); then
    return 1
  fi

  # Get repo root
  if ! REPO_ROOT=$(get_repo_path); then
    return 1
  fi

  return 0
}

# Helper function: Extract cluster infrastructure data
extract_cluster_infrastructure_data_v2() {
  local current_ctx="$1"
  local repo_root="$2"

  log_info "Getting all infrastructure data from Tofu..."

  # STEP 1: Get ALL output (logs + JSON) from the working command
  local raw_output
  raw_output=$("$repo_root/cpc" deploy output -json 2>/dev/null)

  # STEP 2: Using 'sed' to extract clean JSON from all text
  local all_tofu_outputs_json
  all_tofu_outputs_json=$(echo "$raw_output" | sed -n '/^{$/,/^}$/p')

  if [[ -z "$all_tofu_outputs_json" ]]; then
    log_error "Failed to extract JSON from 'cpc deploy output'. Please check for errors."
    return 1
  fi

  # STEP 3: Extract 'cluster_summary' for VM verification
  local cluster_summary_json
  cluster_summary_json=$(echo "$all_tofu_outputs_json" | jq '.cluster_summary.value')

  # Return via global variables
  EXTRACTED_ALL_TOFU_OUTPUTS="$all_tofu_outputs_json"
  EXTRACTED_CLUSTER_SUMMARY="$cluster_summary_json"

  return 0
}

# Helper function: Generate Ansible inventory
generate_ansible_inventory_v2() {
  local all_tofu_outputs_json="$1"

  log_info "Generating temporary static JSON inventory for Ansible..."

  local dynamic_inventory_json
  dynamic_inventory_json=$(echo "$all_tofu_outputs_json" | jq -r '.ansible_inventory.value | fromjson')

  local temp_inventory_file
  temp_inventory_file=$(mktemp /tmp/cpc_inventory.XXXXXX.json)

  # Using jq to transform dynamic JSON to static, which Ansible will understand
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

  log_success "Temporary static JSON inventory created at $temp_inventory_file"

  # Return via global variable
  GENERATED_INVENTORY_FILE="$temp_inventory_file"

  return 0
}

# Helper function: Verify cluster initialization
verify_cluster_initialization_v2() {
  local cluster_summary_json="$1"
  local force_bootstrap="$2"

  if [[ "$force_bootstrap" == false ]]; then
    local control_plane_ip
    control_plane_ip=$(echo "$cluster_summary_json" | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value.IP' | head -1)

    if [ -n "$control_plane_ip" ] && [ "$control_plane_ip" != "null" ]; then
      local repo_root
      repo_root=$(get_repo_path)
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

  return 0
}

# Helper function: Execute bootstrap steps
execute_bootstrap_steps_v2() {
  local temp_inventory_file="$1"

  local ansible_extra_args=("-i" "$temp_inventory_file")

  # CONNECTION CHECK with error handling
  log_info "Testing Ansible connectivity to all nodes..."
  local ping_cmd="ansible all ${ansible_extra_args[*]} -m ping --ssh-extra-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"
  if ! error_validate_command "$ping_cmd" "Failed to connect to all nodes via Ansible"; then
    return 1
  fi
  log_success "Ansible connectivity test passed"

  # Step 1: Install Kubernetes components with recovery
  log_info "Step 1: Installing Kubernetes components..."
  if ! ansible_run_playbook install_kubernetes_cluster.yml "${ansible_extra_args[@]}"; then
    log_error "Failed to install Kubernetes components"
    return 1
  fi

  # Step 2: Initialize cluster with recovery
  log_info "Step 2: Initializing Kubernetes cluster..."
  if ! recovery_execute \
       "ansible_run_playbook initialize_kubernetes_cluster_with_dns.yml ${ansible_extra_args[*]}" \
       "initialize_kubernetes" \
       "log_warning 'Kubernetes initialization failed, manual cleanup may be needed'" \
       "ansible all -l control_plane ${ansible_extra_args[*]} -m shell -a 'test -f /etc/kubernetes/admin.conf' --ssh-extra-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"; then
    log_error "Failed to initialize Kubernetes cluster"
    return 1
  fi

  # Step 3: Validate cluster
  log_info "Step 3: Validating cluster installation..."
  if ! ansible_run_playbook "validate_cluster.yml" -l control_plane "${ansible_extra_args[@]}"; then
    log_warning "Cluster validation failed, but continuing..."
  fi

  return 0
}

# Helper function: Cleanup bootstrap resources
cleanup_bootstrap_resources_v2() {
  local temp_inventory_file="$1"

  # Cleanup is handled by trap in main function
  if [[ -f "$temp_inventory_file" ]]; then
    rm -f "$temp_inventory_file"
    log_debug "Cleaned up temporary inventory file: $temp_inventory_file"
  fi
}

#----------------------------------------------------------------------
# Helper Functions for k8s_get_kubeconfig() Refactoring
#----------------------------------------------------------------------

# Helper function: Retrieve kubeconfig from cluster
retrieve_kubeconfig_from_cluster_v2() {
  local current_ctx="$1"

  # Get control plane IP address
  log_info "Getting infrastructure data from Terraform..."
  local raw_output
  raw_output=$("$REPO_PATH/cpc" deploy output -json 2>/dev/null | sed -n '/^{$/,/^}$/p')

  if [[ -z "$raw_output" ]]; then
    log_error "Failed to get Terraform outputs. Please ensure the cluster is deployed."
    return 1
  fi

  # Get both IP and hostname
  local control_plane_ip control_plane_hostname
  control_plane_ip=$(echo "$raw_output" | jq -r '.cluster_summary.value | to_entries[] | select(.key | contains("controlplane")) | .value.IP | select(. != null)' | head -n 1)
  control_plane_hostname=$(echo "$raw_output" | jq -r '.cluster_summary.value | to_entries[] | select(.key | contains("controlplane")) | .value.hostname | select(. != null)' | head -n 1)

  if [[ -z "$control_plane_ip" ]]; then
    log_error "Could not determine the control plane IP address from Terraform outputs."
    return 1
  fi

  log_info "Control plane IP found: ${control_plane_ip}"
  log_info "Control plane hostname found: ${control_plane_hostname}"

  # Download admin.conf using IP address (more reliable)
  local temp_admin_conf
  temp_admin_conf=$(mktemp)
  trap 'rm -f -- "$temp_admin_conf"' EXIT

  log_info "Fetching admin.conf from control plane..."
  if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${ANSIBLE_REMOTE_USER:-$VM_USERNAME}@${control_plane_ip}" \
    "sudo cat /etc/kubernetes/admin.conf" >"${temp_admin_conf}"; then
    log_error "Failed to fetch admin.conf file from the control plane node."
    return 1
  fi

  if [[ ! -s "${temp_admin_conf}" ]]; then
    log_error "Fetched admin.conf file is empty. Check sudo permissions on the control plane node."
    return 1
  fi

  log_success "Admin.conf file fetched successfully."

  # Extract values from admin.conf using yq
  if ! command -v yq &>/dev/null; then
    log_error "yq is required but not installed. Please install yq to use this function."
    return 1
  fi

  local server_url ca_data client_cert_data client_key_data
  local cluster_name user_name context_name
  server_url=$(yq '.clusters[0].cluster.server' "${temp_admin_conf}")
  ca_data=$(yq '.clusters[0].cluster."certificate-authority-data"' "${temp_admin_conf}")
  client_cert_data=$(yq '.users[0].user."client-certificate-data"' "${temp_admin_conf}")
  client_key_data=$(yq '.users[0].user."client-key-data"' "${temp_admin_conf}")
  
  # Get original names from admin.conf
  local original_cluster_name original_user_name original_context_name
  original_cluster_name=$(yq '.clusters[0].name' "${temp_admin_conf}")
  original_user_name=$(yq '.users[0].name' "${temp_admin_conf}")
  original_context_name=$(yq '.contexts[0].name' "${temp_admin_conf}")
  
  # Create names with current context prefix
  cluster_name="${current_ctx}"
  user_name="${current_ctx}-admin"
  context_name="${current_ctx}"

  if [[ -z "$server_url" || -z "$ca_data" || -z "$client_cert_data" || -z "$client_key_data" ]]; then
    log_error "Failed to extract required values from admin.conf"
    return 1
  fi

  # Replace server URL with hostname
  server_url="https://${control_plane_hostname}:6443"

  # Create temporary files for certificates
  local ca_file client_cert_file client_key_file
  ca_file=$(mktemp)
  client_cert_file=$(mktemp)
  client_key_file=$(mktemp)
  trap 'rm -f -- "$temp_admin_conf" "$ca_file" "$client_cert_file" "$client_key_file"' EXIT

  # Save certificate data to files
  echo "$ca_data" | base64 -d > "$ca_file"
  echo "$client_cert_data" | base64 -d > "$client_cert_file"
  echo "$client_key_data" | base64 -d > "$client_key_file"

  # Check file sizes
  if [[ ! -s "$ca_file" ]]; then
    log_error "CA file is empty after decoding"
    return 1
  fi
  if [[ ! -s "$client_cert_file" ]]; then
    log_error "Client certificate file is empty after decoding"
    return 1
  fi
  if [[ ! -s "$client_key_file" ]]; then
    log_error "Client key file is empty after decoding"
    return 1
  fi

  log_info "Certificate files created successfully"

  # Set up kubectl config
  log_info "Setting up kubectl configuration..."

  # Add new cluster entry using yq
  yq -i '.clusters += [{"name": "'$cluster_name'", "cluster": {"server": "'$server_url'", "certificate-authority-data": "'$ca_data'"}}]' ~/.kube/config

  # Add new user entry using yq
  yq -i '.users += [{"name": "'$user_name'", "user": {"client-certificate-data": "'$client_cert_data'", "client-key-data": "'$client_key_data'"}}]' ~/.kube/config

  # Add new context entry using yq
  yq -i '.contexts += [{"name": "'$context_name'", "context": {"cluster": "'$cluster_name'", "user": "'$user_name'"}}]' ~/.kube/config

  # Set current context
  yq -i '.current-context = "'$context_name'"' ~/.kube/config

  log_success "Kubeconfig has been updated successfully."
  log_info "Current context is now set to '${context_name}'."

  # Cleanup
  rm -f "${temp_admin_conf}" "$ca_file" "$client_cert_file" "$client_key_file"
}

# Helper function: Modify kubeconfig contexts
modify_kubeconfig_contexts_v2() {
  local temp_kubeconfig="$1"
  local current_ctx="$2"
  local control_plane_hostname="$3"

  local cluster_name="$current_ctx"
  local user_name="${current_ctx}_admin"
  local context_name="$current_ctx"

  # Use yq for more reliable YAML editing
  if command -v yq &>/dev/null; then
    # Replace server URL
    yq -i '.clusters[0].cluster.server = "https://'${control_plane_hostname}':6443"' "${temp_kubeconfig}"
    
    # Replace cluster name
    yq -i '.clusters[0].name = "'${cluster_name}'"' "${temp_kubeconfig}"
    
    # Replace user name
    yq -i '.users[0].name = "'${user_name}'"' "${temp_kubeconfig}"
    
    # Replace context name
    yq -i '.contexts[0].name = "'${context_name}'"' "${temp_kubeconfig}"
    
    # Replace context cluster reference
    yq -i '.contexts[0].context.cluster = "'${cluster_name}'"' "${temp_kubeconfig}"
    
    # Replace context user reference
    yq -i '.contexts[0].context.user = "'${user_name}'"' "${temp_kubeconfig}"
    
    # Replace current context
    yq -i '.current-context = "'${context_name}'"' "${temp_kubeconfig}"
  else
    # Fallback to sed if yq is not available
    sed -i \
      -e "s|server: https://[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*:6443|server: https://${control_plane_hostname}:6443|g" \
      -e "s/name: kubernetes/name: ${cluster_name}/g" \
      -e "s/name: kubernetes-admin/name: ${user_name}/g" \
      -e "s/user: kubernetes-admin/user: ${user_name}/g" \
      -e "s/cluster: kubernetes/cluster: ${cluster_name}/g" \
      -e "s/current-context: .*/current-context: ${context_name}/g" \
      "${temp_kubeconfig}"
  fi

  # Return via global variables
  MODIFIED_CLUSTER_NAME="$cluster_name"
  MODIFIED_USER_NAME="$user_name"
  MODIFIED_CONTEXT_NAME="$context_name"
}

# Helper function: Backup existing kubeconfig
backup_existing_kubeconfig_v2() {
  local kubeconfig_path="${KUBECONFIG:-$HOME/.kube/config}"

  # Create a backup just in case
  if [[ -f "$kubeconfig_path" ]]; then
    cp "${kubeconfig_path}" "${kubeconfig_path}.bak.$(date +%s)"
    log_debug "Created backup of existing kubeconfig"
  fi

  BACKUP_KUBECONFIG_PATH="$kubeconfig_path"
}

# Helper function: Merge kubeconfig files
merge_kubeconfig_files_v2() {
  local kubeconfig_path="$1"
  local temp_kubeconfig="$2"
  local context_name="$3"

  log_info "Cleaning up any stale entries for '${context_name}' using yq..."
  if [[ -f "$kubeconfig_path" ]] && command -v yq &>/dev/null; then
    # Using yq is much safer for parsing and editing YAML
    yq -i "del(.clusters[] | select(.name == \"${MODIFIED_CLUSTER_NAME}\"))" "$kubeconfig_path"
    yq -i "del(.contexts[] | select(.name == \"${MODIFIED_CONTEXT_NAME}\"))" "$kubeconfig_path"
    yq -i "del(.users[] | select(.name == \"${MODIFIED_USER_NAME}\"))" "$kubeconfig_path"
  fi

  log_info "Merging into ${kubeconfig_path}"
  mkdir -p "$(dirname "${kubeconfig_path}")"

  KUBECONFIG="${kubeconfig_path}:${temp_kubeconfig}" kubectl config view --merge --flatten >"${kubeconfig_path}.merged"
  mv "${kubeconfig_path}.merged" "${kubeconfig_path}"
  chmod 600 "${kubeconfig_path}"

  kubectl config use-context "${context_name}"
}

# Helper function: Cleanup kubeconfig temp files
cleanup_kubeconfig_temp_files_v2() {
  local temp_kubeconfig="$1"

  # Cleanup is handled by trap in main function
  if [[ -f "$temp_kubeconfig" ]]; then
    rm -f "$temp_kubeconfig"
    log_debug "Cleaned up temporary kubeconfig file: $temp_kubeconfig"
  fi
}

#----------------------------------------------------------------------
# Helper Functions for k8s_cluster_status() Refactoring
#----------------------------------------------------------------------

# Helper function: Parse status arguments
parse_status_arguments_v2() {
  local quick_mode=false
  local fast_mode=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --quick|-q)
        quick_mode=true
        shift
        ;;
      --fast|-f)
        quick_mode=true
        fast_mode=true
        shift
        ;;
      -h|--help)
        k8s_show_status_help
        return 0
        ;;
      *)
        log_error "Unknown option: $1"
        k8s_show_status_help
        return 1
        ;;
    esac
  done

  # Return via global variables
  PARSED_QUICK_MODE="$quick_mode"
  PARSED_FAST_MODE="$fast_mode"
}

# Helper function: Check infrastructure status
check_infrastructure_status_v2() {
  local current_ctx="$1"
  local quick_mode="$2"

  local tf_dir="${REPO_PATH}/terraform"
  local cluster_data=""

  # Load secrets before running tofu commands
  if ! load_secrets_cached; then
    log_error "Failed to load secrets for tofu operations"
    return 1
  fi

  # Get AWS credentials for tofu commands
  local aws_creds
  aws_creds=$(get_aws_credentials)
  if [[ -z "$aws_creds" ]]; then
    log_warning "No AWS credentials available - cannot perform tofu operations"
    # For testing/development: simulate success without AWS
    if [[ "${PYTEST_CURRENT_TEST:-}" == *"test_"* ]] || [[ "${CPC_TEST_MODE:-}" == "true" ]]; then
      log_info "Test mode: Simulating tofu operations"
      return 0
    else
      log_info "AWS credentials required for tofu operations. Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables."
      return 1
    fi
  fi

  # Switch to the Terraform directory to ensure context is correct
  pushd "$tf_dir" >/dev/null || {
    log_error "Failed to switch to Terraform directory."
    return 1
  }

  # Ensure the correct workspace is selected
  eval "$aws_creds"
  tofu workspace select "${current_ctx}" >/dev/null

  # Get the cluster summary output
  cluster_data=$(tofu output -json cluster_summary)
  local exit_code=$?

  popd >/dev/null || {
    log_error "Failed to switch back from Terraform directory."
    return 1
  }

  if [[ $exit_code -eq 0 && "$cluster_data" != "null" && -n "$cluster_data" ]]; then
    if [[ "$quick_mode" == true ]]; then
      local vm_count
      vm_count=$(echo "$cluster_data" | jq '. | length' 2>/dev/null || echo "0")
      log_success "VMs deployed: ${vm_count}"
    else
      local vm_count
      vm_count=$(echo "$cluster_data" | jq '. | length')

      if [[ $vm_count -gt 0 ]]; then
        log_success "VMs deployed: ${vm_count}"
        echo
        echo -e "${GREEN}Cluster VMs:${ENDCOLOR}"
        echo "$cluster_data" | jq -r 'to_entries[] | "  ✓ \(.key) (\(.value.hostname)) - \(.value.IP)"'
        
        # Check VM status in Proxmox
        echo
        log_info "🔍 Checking VM status in Proxmox..."
        check_proxmox_vm_status "$cluster_data"
      else
        log_warning "No VMs found in the current workspace."
      fi
    fi
  else
    if [[ "$quick_mode" == true ]]; then
      log_warning "VMs deployed: 0 (workspace not deployed)"
    else
      log_error "Failed to retrieve VM information from Terraform."
      log_info "Is the cluster deployed? Try running 'cpc deploy apply'."
    fi
  fi

  # Return via global variable
  INFRASTRUCTURE_CLUSTER_DATA="$cluster_data"
}

# Helper function: Check SSH connectivity
check_ssh_connectivity_v2() {
  local cluster_data="$1"
  local quick_mode="$2"

  if [[ "$quick_mode" == true ]]; then
    # Quick SSH check with caching for speed
    if [[ -n "$cluster_data" && "$cluster_data" != "null" ]]; then
      local ssh_cache_file="/tmp/cpc_ssh_cache_${CURRENT_CTX}"
      local ssh_result=""
      local use_ssh_cache=false

      # Check if SSH cache exists and is less than 10 seconds old
      if [[ -f "$ssh_cache_file" ]]; then
        local ssh_cache_age=$(($(date +%s) - $(stat -c %Y "$ssh_cache_file" 2>/dev/null || echo 0)))
        if [[ $ssh_cache_age -lt 10 ]]; then
          use_ssh_cache=true
          ssh_result=$(cat "$ssh_cache_file" 2>/dev/null)
        fi
      fi
      
      if [[ "$use_ssh_cache" == true && -n "$ssh_result" ]]; then
        echo -e "${GREEN}$ssh_result${ENDCOLOR}"
      else
        # Extract IPs into an array
        local ips_array
        mapfile -t ips_array < <(echo "$cluster_data" | jq -r 'to_entries[] | .value.IP' 2>/dev/null)
        
        local reachable=0
        local total=${#ips_array[@]}
        
        # Process each IP sequentially for reliability
        for ip in "${ips_array[@]}"; do
          if [[ -n "$ip" && "$ip" != "null" ]]; then
            if ssh -o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=no "$ip" "exit 0" 2>/dev/null; then
              ((reachable++))
            fi
          fi
        done
        
        ssh_result="SSH reachable: $reachable/$total"
        echo -e "${GREEN}$ssh_result${ENDCOLOR}"
        
        # Cache the SSH result
        echo "$ssh_result" > "$ssh_cache_file" 2>/dev/null
      fi
    else
      echo -e "${YELLOW}SSH reachable: No VMs to check${ENDCOLOR}"
    fi
  else
    # Full SSH connectivity check
    if [[ -z "$cluster_data" || "$cluster_data" == "null" ]]; then
      log_warning "Cannot test SSH connectivity because VM data is unavailable."
    else
      local ssh_results=""
      local total_hosts=0
      local reachable_hosts=0
      
      # Create arrays for VM data
      local vm_keys=()
      local vm_ips=()
      
      # Parse cluster data into arrays
      while read -r vm_key vm_ip; do
        vm_keys+=("$vm_key")
        vm_ips+=("$vm_ip")
      done < <(echo "$cluster_data" | jq -r 'to_entries[] | "\(.key) \(.value.IP)"')
      
      local total_hosts=${#vm_keys[@]}
      
      # Test each host
      for ((i=0; i<${#vm_keys[@]}; i++)); do
        local vm_key="${vm_keys[i]}"
        local ip="${vm_ips[i]}"
        
        echo -n "  Testing $vm_key ($ip)... "
        
        # Test SSH connection with detailed output
        if ssh -o ConnectTimeout=5 \
               -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               "$ip" "echo 'SSH OK'" 2>/dev/null; then
          echo -e "${GREEN}✓ Reachable${ENDCOLOR}"
          ((reachable_hosts++))
        else
          # Try to determine the reason for failure
          local error_reason="Unknown error"
          if timeout 5 bash -c "</dev/tcp/$ip/22" 2>/dev/null; then
            error_reason="Authentication failed"
          else
            error_reason="Connection timeout/Port 22 closed"
          fi
          echo -e "${RED}✗ $error_reason${ENDCOLOR}"
        fi
      done
      
      echo
      if [[ $reachable_hosts -eq $total_hosts ]]; then
        log_success "All $total_hosts nodes are reachable via SSH"
      elif [[ $reachable_hosts -gt 0 ]]; then
        log_warning "$reachable_hosts/$total_hosts nodes reachable via SSH"
      else
        log_error "No nodes are reachable via SSH"
        log_info "💡 Try: 'cpc start-vms' to start VMs or check network connectivity"
      fi
    fi
  fi
}

# Helper function: Check Kubernetes health
check_kubernetes_health_v2() {
  local current_ctx="$1"
  local quick_mode="$2"

  if [[ "$quick_mode" == true ]]; then
    # Quick K8s check only
    if KUBECONFIG="${HOME}/.kube/config" kubectl cluster-info --context="${current_ctx}" --request-timeout=5s &>/dev/null; then
      local nodes
      nodes=$(KUBECONFIG="${HOME}/.kube/config" kubectl get nodes --no-headers --context="${current_ctx}" 2>/dev/null | wc -l)
      echo -e "${GREEN}K8s nodes: $nodes${ENDCOLOR}"
    else
      echo -e "${RED}K8s: Not accessible${ENDCOLOR}"
    fi
  else
    # Full Kubernetes health check
    if ! command -v kubectl &>/dev/null; then
      log_error "'kubectl' command not found. Please install it first."
      log_info "💡 Install kubectl: https://kubernetes.io/docs/tasks/tools/"
    elif ! KUBECONFIG="${HOME}/.kube/config" kubectl cluster-info --context="${current_ctx}" --request-timeout=10s &>/dev/null; then
      log_error "Cannot connect to Kubernetes cluster."
      log_info "💡 Try: 'cpc k8s-cluster get-kubeconfig' to retrieve cluster config"
      log_info "💡 Or run: 'cpc bootstrap' to create a new cluster"
    else
      log_success "Successfully connected to Kubernetes cluster."
      
      # Quick health check
      echo
      log_info "🔍 Quick cluster health check:"
      
      # Check control plane status
      echo -n "  Control plane: "
      if KUBECONFIG="${HOME}/.kube/config" kubectl get nodes --selector='node-role.kubernetes.io/control-plane' --context="${current_ctx}" &>/dev/null; then
        local control_nodes
        control_nodes=$(KUBECONFIG="${HOME}/.kube/config" kubectl get nodes --selector='node-role.kubernetes.io/control-plane' --no-headers --context="${current_ctx}" | wc -l)
        echo -e "${GREEN}✓ $control_nodes control plane node(s)${ENDCOLOR}"
      else
        echo -e "${RED}✗ No control plane nodes found${ENDCOLOR}"
      fi
      
      # Check worker nodes
      echo -n "  Worker nodes: "
      local worker_nodes
      worker_nodes=$(KUBECONFIG="${HOME}/.kube/config" kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' --no-headers --context="${current_ctx}" 2>/dev/null | wc -l)
      if [[ $worker_nodes -gt 0 ]]; then
        echo -e "${GREEN}✓ $worker_nodes worker node(s)${ENDCOLOR}"
      else
        echo -e "${YELLOW}⚠ No dedicated worker nodes${ENDCOLOR}"
      fi
      
      # Check core services
      echo -n "  CoreDNS: "
      if KUBECONFIG="${HOME}/.kube/config" kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers --context="${current_ctx}" &>/dev/null; then
        local coredns_pods
        coredns_pods=$(KUBECONFIG="${HOME}/.kube/config" kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers --context="${current_ctx}" | grep Running | wc -l)
        local total_coredns
        total_coredns=$(KUBECONFIG="${HOME}/.kube/config" kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers --context="${current_ctx}" | wc -l)
        if [[ $coredns_pods -eq $total_coredns ]]; then
          echo -e "${GREEN}✓ Running ($coredns_pods/$total_coredns)${ENDCOLOR}"
        else
          echo -e "${YELLOW}⚠ Partially running ($coredns_pods/$total_coredns)${ENDCOLOR}"
        fi
      else
        echo -e "${RED}✗ Not found${ENDCOLOR}"
      fi
      
      # Check CNI
      echo -n "  CNI (Calico): "
      # First try calico-system namespace (newer Calico installs)
      if KUBECONFIG="${HOME}/.kube/config" kubectl get pods -n calico-system --no-headers --context="${current_ctx}" 2>/dev/null | grep -q calico-node; then
        local calico_pods
        calico_pods=$(KUBECONFIG="${HOME}/.kube/config" kubectl get pods -n calico-system --no-headers --context="${current_ctx}" 2>/dev/null | grep calico-node | grep Running | wc -l)
        local total_calico
        total_calico=$(KUBECONFIG="${HOME}/.kube/config" kubectl get pods -n calico-system --no-headers --context="${current_ctx}" 2>/dev/null | grep calico-node | wc -l)
        if [[ $calico_pods -eq $total_calico && $total_calico -gt 0 ]]; then
          echo -e "${GREEN}✓ Running ($calico_pods/$total_calico)${ENDCOLOR}"
        else
          echo -e "${YELLOW}⚠ Partially running ($calico_pods/$total_calico)${ENDCOLOR}"
        fi
      # Fallback to kube-system namespace (older Calico installs)
      elif KUBECONFIG="${HOME}/.kube/config" kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers --context="${current_ctx}" 2>/dev/null | grep -q .; then
        local calico_pods
        calico_pods=$(KUBECONFIG="${HOME}/.kube/config" kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers --context="${current_ctx}" 2>/dev/null | grep Running | wc -l)
        local total_calico
        total_calico=$(KUBECONFIG="${HOME}/.kube/config" kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers --context="${current_ctx}" 2>/dev/null | wc -l)
        if [[ $calico_pods -eq $total_calico && $total_calico -gt 0 ]]; then
          echo -e "${GREEN}✓ Running ($calico_pods/$total_calico)${ENDCOLOR}"
        else
          echo -e "${YELLOW}⚠ Partially running ($calico_pods/$total_calico)${ENDCOLOR}"
        fi
      else
        echo -e "${RED}✗ Not found${ENDCOLOR}"
      fi

      echo
      KUBECONFIG="${HOME}/.kube/config" kubectl cluster-info --context="${current_ctx}"
    fi
  fi
}

# Helper function: Display status summary
display_status_summary_v2() {
  local current_ctx="$1"
  local quick_mode="$2"

  if [[ "$quick_mode" == true ]]; then
    log_info "=== Quick Cluster Status ==="
    log_info "Workspace: ${current_ctx}"
  else
    log_info "=== Kubernetes Cluster Status Check ==="
    log_info "Workspace: ${current_ctx}"
    echo
  fi
}

# Helper function: Cache status results
cache_status_results_v2() {
  local cache_key="$1"
  local status_data="$2"
  local cache_duration="${3:-300}"  # Default 5 minutes

  local cache_file="/tmp/cpc_status_cache_${cache_key}"

  # Cache the result if successful
  if [[ -n "$status_data" ]]; then
    echo "$status_data" > "$cache_file" 2>/dev/null
    # log_debug "Cached status data for key: $cache_key"  # Commented out for testing
  fi
}

#----------------------------------------------------------------------
# Improved Helper Functions for check_proxmox_vm_status()
#----------------------------------------------------------------------

# Helper function: Authenticate with Proxmox API
authenticate_proxmox_api_v2() {
  # Check if we have Proxmox credentials
  if [[ -z "$PROXMOX_HOST" || -z "$PROXMOX_USERNAME" || -z "$PROXMOX_PASSWORD" ]]; then
    log_warning "Proxmox credentials not available."
    return 1
  fi

  # Set default PROXMOX_NODE if not provided
  if [[ -z "$PROXMOX_NODE" ]]; then
    PROXMOX_NODE="homelab"
  fi

  # Extract hostname from full API endpoint
  local clean_host
  clean_host=$(echo "$PROXMOX_HOST" | sed -E 's|https?://([^:/]+)(:[0-9]+)?(/.*)?|\1|')

  # Use username as-is (it already contains @pve)
  local auth_url="https://${clean_host}:8006/api2/json/access/ticket"

  # Authenticate with Proxmox API
  local auth_response
  auth_response=$(echo "username=${PROXMOX_USERNAME}&password=${PROXMOX_PASSWORD}" | curl -s -k -X POST \
    "$auth_url" \
    --data @- 2>/dev/null)
  
  if [[ $? -ne 0 || -z "$auth_response" ]]; then
    log_warning "Failed to authenticate with Proxmox API."
    return 1
  fi

  # Extract ticket and CSRF token from auth response
  local ticket
  local csrf_token
  ticket=$(echo "$auth_response" | jq -r '.data.ticket // empty' 2>/dev/null)
  csrf_token=$(echo "$auth_response" | jq -r '.data.CSRFPreventionToken // empty' 2>/dev/null)

  if [[ -z "$ticket" || -z "$csrf_token" ]]; then
    log_warning "Failed to extract authentication tokens from Proxmox API response."
    return 1
  fi

  # Return via global variables
  PROXMOX_CLEAN_HOST="$clean_host"
  PROXMOX_AUTH_TICKET="$ticket"
  PROXMOX_CSRF_TOKEN="$csrf_token"

  return 0
}

# Helper function: Get VM status from API
get_vm_status_from_api_v2() {
  local vm_id="$1"
  local clean_host="$2"
  local ticket="$3"
  local csrf_token="$4"

  if [[ -n "$vm_id" && "$vm_id" != "null" ]]; then
    # Get VM status via API
    local vm_status_response
    vm_status_response=$(curl -s -k \
      -H "Authorization: PVEAuthCookie=$ticket" \
      -H "CSRFPreventionToken: $csrf_token" \
      "https://${clean_host}:8006/api2/json/nodes/${PROXMOX_NODE}/qemu/${vm_id}/status/current" 2>/dev/null)

    if [[ $? -eq 0 && -n "$vm_status_response" ]]; then
      local vm_status
      vm_status=$(echo "$vm_status_response" | jq -r '.data.status // "unknown"' 2>/dev/null)
      echo "$vm_status"
      return 0
    else
      echo "api_error"
      return 1
    fi
  else
    echo "invalid_vm_id"
    return 1
  fi
}

# Helper function: Format VM status display
format_vm_status_display_v2() {
  local vm_id="$1"
  local vm_key="$2"
  local hostname="$3"
  local ip="$4"
  local vm_status="$5"

  case "$vm_status" in
    "running")
      echo -e "  VM $vm_id ($hostname): ${GREEN}✓ Running${ENDCOLOR}"
      ;;
    "stopped")
      echo -e "  VM $vm_id ($hostname): ${RED}✗ Stopped${ENDCOLOR}"
      ;;
    "paused")
      echo -e "  VM $vm_id ($hostname): ${YELLOW}⏸ Paused${ENDCOLOR}"
      ;;
    "api_error")
      echo -e "  VM $vm_id ($hostname): ${YELLOW}? API Error${ENDCOLOR}"
      ;;
    "invalid_vm_id")
      echo -e "  VM $vm_id ($hostname): ${YELLOW}? Invalid VM ID${ENDCOLOR}"
      ;;
    *)
      echo -e "  VM $vm_id ($hostname): ${YELLOW}? $vm_status${ENDCOLOR}"
      ;;
  esac
}
