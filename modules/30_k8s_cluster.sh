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
# В файле: modules/30_k8s_cluster.sh

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

  # ШАГ 1: Получаем ВЕСЬ вывод (логи + JSON) от рабочей команды
  log_info "Getting all infrastructure data from Tofu..."
  local raw_output
  raw_output=$("$repo_root/cpc" deploy output -json 2>/dev/null)

  # ШАГ 2: С помощью 'sed' вырезаем чистый JSON из всего текста
  local all_tofu_outputs_json
  all_tofu_outputs_json=$(echo "$raw_output" | sed -n '/^{$/,/^}$/p')

  if [[ -z "$all_tofu_outputs_json" ]]; then
    log_error "Failed to extract JSON from 'cpc deploy output'. Please check for errors."
    return 1
  fi

  # ШАГ 3: Извлекаем 'cluster_summary' для проверки VM
  local cluster_summary_json
  cluster_summary_json=$(echo "$all_tofu_outputs_json" | jq '.cluster_summary.value')

  if [ "$skip_check" = false ]; then
    log_info "Checking VM existence and connectivity..."
    if ! tofu_update_node_info "$cluster_summary_json"; then
      log_error "No VMs found in Tofu output. Please deploy VMs first with 'cpc deploy apply'"
      return 1
    fi
    log_success "VM check passed. Found ${#TOFU_NODE_NAMES[@]} nodes."
  fi

  # ШАГ 4: Извлекаем 'ansible_inventory' и КОНВЕРТИРУЕМ его в СТАТИЧЕСКИЙ JSON
  log_info "Generating temporary static JSON inventory for Ansible..."
  local dynamic_inventory_json
  dynamic_inventory_json=$(echo "$all_tofu_outputs_json" | jq -r '.ansible_inventory.value | fromjson')

  local temp_inventory_file
  temp_inventory_file=$(mktemp /tmp/cpc_inventory.XXXXXX.json)

  # С помощью jq преобразуем динамический JSON в статический, который Ansible поймет
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

  # Check if cluster is already initialized (unless forced)
  if [ "$force_bootstrap" = false ]; then
    local control_plane_ip
    control_plane_ip=$(echo "$cluster_summary_json" | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value.IP' | head -1)

    if [ -n "$control_plane_ip" ] && [ "$control_plane_ip" != "null" ]; then
      local ansible_dir="$repo_root/ansible"
      local remote_user
      remote_user=$(grep -Po '^remote_user\s*=\s*\K.*' "$ansible_dir/ansible.cfg" 2>/dev/null || echo 'root')

      if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null \
        "${remote_user}@${control_plane_ip}" \
        "test -f /etc/kubernetes/admin.conf" 2>/dev/null; then
        log_warning "Kubernetes cluster appears to already be initialized on $control_plane_ip"
        log_warning "Use --force to bootstrap anyway (this will reset the cluster)"
        rm -f "$temp_inventory_file"
        return 1
      fi
    fi
  fi

  # Run the bootstrap playbooks
  log_success "Starting Kubernetes cluster bootstrap..."

  local ansible_extra_args=("-i" "$temp_inventory_file")

  # ПРОВЕРКА СВЯЗИ
  log_info "Testing Ansible connectivity to all nodes..."
  if ! ansible all "${ansible_extra_args[@]}" -m ping --ssh-extra-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"; then
    log_error "Failed to connect to all nodes via Ansible"
    rm -f "$temp_inventory_file"
    return 1
  fi
  log_success "Ansible connectivity test passed"

  # Step 1: Install Kubernetes components
  log_info "Step 1: Installing Kubernetes components..."
  if ! ansible_run_playbook "install_kubernetes_cluster.yml" "${ansible_extra_args[@]}"; then
    log_error "Failed to install Kubernetes components"
    rm -f "$temp_inventory_file"
    return 1
  fi

  # Step 2: Initialize cluster
  log_info "Step 2: Initializing Kubernetes cluster..."
  if ! ansible_run_playbook "initialize_kubernetes_cluster_with_dns.yml" "${ansible_extra_args[@]}"; then
    log_error "Failed to initialize Kubernetes cluster"
    rm -f "$temp_inventory_file"
    return 1
  fi

  # Step 3: Validate cluster
  log_info "Step 3: Validating cluster installation..."
  if ! ansible_run_playbook "validate_cluster.yml" -l control_plane "${ansible_extra_args[@]}"; then
    log_warning "Cluster validation failed, but continuing..."
  fi

  # Удаляем временный файл
  rm -f "$temp_inventory_file"

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

  log_step "Retrieving kubeconfig from the cluster..."

  local current_ctx
  current_ctx=$(get_current_cluster_context)
  if [[ -z "$current_ctx" ]]; then
    log_error "No active workspace context is set. Use 'cpc ctx <workspace_name>'."
    return 1
  fi

  # --- НАЧАЛО ИСПРАВЛЕНИЯ: Логика получения данных как в k8s_bootstrap ---
  log_info "Getting all infrastructure data..."
  local raw_output
  # Вызываем 'cpc deploy output' для получения полного вывода
  raw_output=$("$REPO_PATH/cpc" deploy output -json 2>/dev/null)

  # Вырезаем чистый JSON из всего текста
  local all_tofu_outputs_json
  all_tofu_outputs_json=$(echo "$raw_output" | sed -n '/^{$/,/^}$/p')

  if [[ -z "$all_tofu_outputs_json" ]]; then
    log_error "Failed to extract JSON from 'cpc deploy output'. Please check for errors."
    return 1
  fi

  # Извлекаем IP control-plane ноды из 'cluster_summary'
  local control_plane_ip
  control_plane_ip=$(echo "$all_tofu_outputs_json" | jq -r '.cluster_summary.value | to_entries[] | select(.key | contains("controlplane")) | .value.IP | select(. != null)' | head -n 1)
  # --- КОНЕЦ ИСПРАВЛЕНИЯ ---

  if [[ -z "$control_plane_ip" ]]; then
    log_error "Could not determine the control plane IP address from Terraform outputs."
    log_info "Ensure the cluster is deployed ('cpc deploy apply') and outputs are available."
    return 1
  fi

  log_info "Control plane IP found: ${control_plane_ip}"

  local temp_kubeconfig
  temp_kubeconfig=$(mktemp)

  log_info "Fetching kubeconfig from ${control_plane_ip}..."
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${ANSIBLE_REMOTE_USER:-$VM_USERNAME}@${control_plane_ip}" \
    "sudo cat /etc/kubernetes/admin.conf" >"${temp_kubeconfig}"; then

    # Check if the fetched file is not empty
    if [[ ! -s "${temp_kubeconfig}" ]]; then
      log_error "Fetched kubeconfig file is empty. Check sudo permissions for user ${ANSIBLE_REMOTE_USER:-$VM_USERNAME} on the control plane node."
      rm "${temp_kubeconfig}"
      return 1
    fi

    log_success "Kubeconfig file fetched successfully."

    sed -i "s/server: https:\/\/.*:6443/server: https:\/\/${control_plane_ip}:6443/" "${temp_kubeconfig}"

    local kubeconfig_path="${KUBECONFIG:-$HOME/.kube/config}"
    local backup_path="${kubeconfig_path}.bak"

    log_info "Merging into ${kubeconfig_path}"

    mkdir -p "$(dirname "${kubeconfig_path}")"

    if [[ -f "$kubeconfig_path" ]]; then
      cp "${kubeconfig_path}" "${backup_path}"
      log_info "Backup of existing kubeconfig created at ${backup_path}"
    fi

    KUBECONFIG="${kubeconfig_path}:${temp_kubeconfig}" kubectl config view --flatten >"${kubeconfig_path}.merged"
    mv "${kubeconfig_path}.merged" "${kubeconfig_path}"

    local context_name="cluster-${current_ctx}"
    # Rename the context if it exists, suppressing errors
    kubectl config get-contexts "kubernetes-admin@kubernetes" &>/dev/null && kubectl config rename-context "kubernetes-admin@kubernetes" "${context_name}"
    kubectl config use-context "${context_name}"

    log_success "Kubeconfig has been updated successfully."
    log_info "Current context is now set to '${context_name}'."

    rm "${temp_kubeconfig}"
  else
    log_error "Failed to fetch kubeconfig file from the control plane node."
    rm "${temp_kubeconfig}"
    return 1
  fi
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
    k8s_show_status_help
    return 0
  fi

  local current_ctx
  current_ctx=$(get_current_cluster_context)
  log_info "=== Kubernetes Cluster Status Check ==="
  log_info "Workspace: ${current_ctx}"
  echo

  log_info "📋 1. Checking VM infrastructure..."
  local tf_dir="${REPO_PATH}/terraform"
  local cluster_data=""

  # Switch to the Terraform directory to ensure context is correct
  pushd "$tf_dir" >/dev/null || {
    log_error "Failed to switch to Terraform directory."
    return 1
  }

  # Ensure the correct workspace is selected
  tofu workspace select "${current_ctx}" >/dev/null

  # Get the cluster summary output
  cluster_data=$(tofu output -json cluster_summary)
  local exit_code=$?

  popd >/dev/null || {
    log_error "Failed to switch back from Terraform directory."
    return 1
  }

  if [[ $exit_code -eq 0 && "$cluster_data" != "null" && -n "$cluster_data" ]]; then
    local vm_count
    vm_count=$(echo "$cluster_data" | jq '. | length')

    if [[ $vm_count -gt 0 ]]; then
      log_success "VMs deployed: ${vm_count}"
      echo
      echo -e "${GREEN}Cluster VMs:${ENDCOLOR}"
      echo "$cluster_data" | jq -r 'to_entries[] | "  ✓ \(.key) (\(.value.hostname)) - \(.value.IP)"'
    else
      log_warning "No VMs found in the current workspace."
    fi
  else
    log_error "Failed to retrieve VM information from Terraform."
    log_info "Is the cluster deployed? Try running 'cpc deploy apply'."
  fi
  echo

  # --- Start of Fix ---
  log_info "🔗 2. Testing SSH connectivity..."
  if [[ -z "$cluster_data" || "$cluster_data" == "null" ]]; then
    log_warning "Cannot test SSH connectivity because VM data is unavailable."
  else
    local all_hosts_reachable=true
    local host_ips
    host_ips=$(echo "$cluster_data" | jq -r '.[].IP')

    for ip in $host_ips; do
      if ssh_test_connection "$ip"; then
        log_success "SSH connection to ${ip} successful."
      else
        log_error "SSH connection to ${ip} failed."
        all_hosts_reachable=false
      fi
    done
    [[ "$all_hosts_reachable" == true ]] && log_success "All nodes are reachable via SSH."
  fi
  # --- End of Fix ---
  echo

  log_info "⚙️ 3. Checking Kubernetes cluster status..."
  if ! command -v kubectl &>/dev/null; then
    log_error "'kubectl' command not found. Please install it first."
  elif ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster."
    log_info "Try running 'cpc k8s-cluster get-kubeconfig' to retrieve cluster config."
  else
    log_success "Successfully connected to Kubernetes cluster."
    kubectl cluster-info
  fi
  echo

  log_info "📊 4. Cluster Summary:"
  if ! kubectl get nodes &>/dev/null; then
    log_error "Kubernetes cluster not accessible or no nodes found."
  else
    kubectl get nodes -o wide
    echo
    log_info "Pods status:"
    kubectl get pods -A
  fi
  echo
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
