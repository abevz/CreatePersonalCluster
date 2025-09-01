#!/bin/bash

# Enhanced get-kubeconfig script with error handling and recovery
# Part of CPC (Create Personal Cluster) - Enhanced Kubeconfig Management

# Color definitions
export GREEN='\033[32m'
export RED='\033[0;31m'
export YELLOW='\033[0;33m'
export BLUE='\033[1;34m'
export ENDCOLOR='\033[0m'

# Configuration
CONFIG_DIR="$HOME/.config/my-kthw-cpc"
REPO_PATH_FILE="$CONFIG_DIR/repo_path"
CPC_CONTEXT_FILE="$CONFIG_DIR/current_cluster_context"

# Error handling constants
readonly ERROR_CONFIG=1
readonly ERROR_EXECUTION=2
readonly ERROR_INPUT=3
readonly SEVERITY_LOW=1
readonly SEVERITY_MEDIUM=2
readonly SEVERITY_HIGH=3
readonly SEVERITY_CRITICAL=4

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${ENDCOLOR} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${ENDCOLOR} $1" >&2
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${ENDCOLOR} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${ENDCOLOR} $1"
}

# Error handling function
error_handle() {
  local error_code="$1"
  local error_message="$2"
  local severity="$3"
  local action="$4"

  log_error "$error_message (Error code: $error_code)"

  case "$action" in
    "abort")
      log_error "Aborting operation due to critical error"
      exit $error_code
      ;;
    "retry")
      log_warning "Will retry operation"
      ;;
    "continue")
      log_warning "Continuing despite error"
      ;;
    *)
      log_warning "Unknown error action: $action"
      ;;
  esac
}

# Recovery checkpoint function
recovery_checkpoint() {
  local checkpoint_name="$1"
  local description="$2"
  log_info "Recovery checkpoint: $checkpoint_name - $description"
}

# Validation functions
validate_dependencies() {
  local missing_deps=()

  if ! command -v tofu &> /dev/null; then
    missing_deps+=("tofu")
  fi

  if ! command -v kubectl &> /dev/null; then
    missing_deps+=("kubectl")
  fi

  if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
  fi

  if ! command -v ssh &> /dev/null; then
    missing_deps+=("ssh")
  fi

  if [ ${#missing_deps[@]} -gt 0 ]; then
    error_handle "$ERROR_CONFIG" "Missing required dependencies: ${missing_deps[*]}" "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  return 0
}

validate_directory() {
  local dir_path="$1"
  local dir_name="$2"

  if [[ ! -d "$dir_path" ]]; then
    error_handle "$ERROR_CONFIG" "Directory not found: $dir_name ($dir_path)" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  return 0
}

validate_file() {
  local file_path="$1"
  local file_name="$2"

  if [[ ! -f "$file_path" ]]; then
    error_handle "$ERROR_CONFIG" "File not found: $file_name ($file_path)" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  return 0
}

# Helper functions with error handling
get_repo_path() {
  if ! validate_file "$REPO_PATH_FILE" "Repository path configuration"; then
    return 1
  fi

  local repo_path
  repo_path=$(cat "$REPO_PATH_FILE" 2>/dev/null)
  if [[ -z "$repo_path" ]]; then
    error_handle "$ERROR_CONFIG" "Repository path is empty in configuration file" "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  echo "$repo_path"
}

get_current_cluster_context() {
  if ! validate_file "$CPC_CONTEXT_FILE" "Current cluster context configuration"; then
    return 1
  fi

  local context
  context=$(cat "$CPC_CONTEXT_FILE" 2>/dev/null)
  if [[ -z "$context" ]]; then
    error_handle "$ERROR_CONFIG" "Current cluster context is empty in configuration file" "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  echo "$context"
}

# Enhanced get-kubeconfig function that prefers DNS hostnames over IP addresses
# This function should replace the existing get-kubeconfig functionality in cpc

enhanced_get_kubeconfig() {
  # Initialize recovery for kubeconfig retrieval
  recovery_checkpoint "enhanced_get_kubeconfig_start" "Starting enhanced kubeconfig retrieval"

  # Validate dependencies
  if ! validate_dependencies; then
    return 1
  fi

  local force_overwrite=false
  local custom_context_name=""
  local use_hostname=true
  local use_ip=false

  # Parse options
  while [[ $# -gt 0 ]]; do
    case $1 in
      --force)
        force_overwrite=true
        shift
        ;;
      --context-name)
        custom_context_name="$2"
        shift 2
        ;;
      --use-ip)
        use_ip=true
        use_hostname=false
        shift
        ;;
      --use-hostname)
        use_hostname=true
        use_ip=false
        shift
        ;;
      -h|--help)
        echo "Usage: cpc get-kubeconfig [options]"
        echo ""
        echo "Get kubeconfig from the cluster and merge it with local ~/.kube/config"
        echo ""
        echo "Options:"
        echo "  --force                Force overwrite existing context"
        echo "  --context-name NAME    Use custom context name"
        echo "  --use-ip              Force use of IP address for server endpoint"
        echo "  --use-hostname        Use DNS hostname for server endpoint (default)"
        echo "  -h, --help            Show this help"
        echo ""
        echo "The command will:"
        echo "  1. Retrieve kubeconfig from control plane node"
        echo "  2. Update server endpoint to use hostname (if available) or IP"
        echo "  3. Rename context to avoid conflicts"
        echo "  4. Merge with existing ~/.kube/config"
        return 0
        ;;
      *)
        error_handle "$ERROR_INPUT" "Unknown option: $1" "$SEVERITY_LOW" "abort"
        return 1
        ;;
    esac
  done

  # Check if secrets are loaded
  if ! check_secrets_loaded; then
    error_handle "$ERROR_CONFIG" "Failed to load secrets. Aborting kubeconfig retrieval." "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  local current_ctx
  if ! current_ctx=$(get_current_cluster_context); then
    return 1
  fi

  local repo_root
  if ! repo_root=$(get_repo_path); then
    return 1
  fi

  # Validate terraform directory
  local terraform_dir="$repo_root/terraform"
  if ! validate_directory "$terraform_dir" "Terraform directory"; then
    return 1
  fi

  # Set context name
  if [ -z "$custom_context_name" ]; then
    context_name="cluster-${current_ctx}"
  else
    context_name="$custom_context_name"
  fi

  echo -e "${BLUE}Retrieving kubeconfig for cluster context: $current_ctx${ENDCOLOR}"
  echo -e "${BLUE}Kubernetes context will be named: $context_name${ENDCOLOR}"

  # Warn if context already exists
  if kubectl config get-contexts -o name 2>/dev/null | grep -q "^${context_name}$"; then
    if [ "$force_overwrite" = false ]; then
      echo -e "${YELLOW}Context '$context_name' already exists and will be overwritten.${ENDCOLOR}"
      echo -e "${YELLOW}Use --context-name to use a different name if desired.${ENDCOLOR}"
    else
      echo -e "${BLUE}Context '$context_name' exists and will be overwritten (--force specified).${ENDCOLOR}"
    fi
  fi

  # Get control plane information from Terraform/Tofu output
  if ! pushd "$terraform_dir" >/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to change to terraform directory: $terraform_dir" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Ensure we're in the correct workspace
  if ! tofu workspace select "$current_ctx" &>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to select Tofu workspace '$current_ctx'" "$SEVERITY_HIGH" "retry"
    # Retry once more
    if ! tofu workspace select "$current_ctx" &>/dev/null; then
      error_handle "$ERROR_EXECUTION" "Failed to select Tofu workspace '$current_ctx' after retry" "$SEVERITY_CRITICAL" "abort"
      popd >/dev/null || true
      return 1
    fi
  fi

  # Get control plane node IP and hostname with error handling
  local control_plane_ip
  local control_plane_hostname

  if ! control_plane_ip=$(tofu output -json k8s_node_ips 2>/dev/null | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value' 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to get control plane IP from Tofu output" "$SEVERITY_HIGH" "abort"
    popd >/dev/null || true
    return 1
  fi

  if ! control_plane_hostname=$(tofu output -json k8s_node_names 2>/dev/null | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value' 2>/dev/null); then
    log_warning "Failed to get control plane hostname from Tofu output, will use IP only"
    control_plane_hostname=""
  fi

  if ! popd >/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to return to original directory" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if [ -z "$control_plane_ip" ] || [ "$control_plane_ip" = "null" ]; then
    error_handle "$ERROR_EXECUTION" "Failed to get control plane IP from Tofu output" "$SEVERITY_HIGH" "abort"
    echo -e "${RED}Make sure the cluster is deployed and 'tofu output k8s_node_ips' returns valid data${ENDCOLOR}" >&2
    return 1
  fi

  echo -e "${BLUE}Control plane IP: $control_plane_ip${ENDCOLOR}"
  if [ -n "$control_plane_hostname" ] && [ "$control_plane_hostname" != "null" ]; then
    echo -e "${BLUE}Control plane hostname: $control_plane_hostname${ENDCOLOR}"
  fi

  # Determine server endpoint
  if [ "$use_hostname" = true ] && [ -n "$control_plane_hostname" ] && [ "$control_plane_hostname" != "null" ]; then
    server_endpoint="$control_plane_hostname"
    endpoint_type="hostname"
  else
    server_endpoint="$control_plane_ip"
    endpoint_type="IP address"
  fi

  echo -e "${BLUE}Using $endpoint_type for server endpoint: $server_endpoint${ENDCOLOR}"

  # Test connectivity to the chosen endpoint
  if [ "$endpoint_type" = "hostname" ]; then
    echo -e "${BLUE}Testing DNS resolution for $server_endpoint...${ENDCOLOR}"
    if ! nslookup "$server_endpoint" >/dev/null 2>&1; then
      error_handle "$ERROR_EXECUTION" "DNS resolution failed for $server_endpoint" "$SEVERITY_MEDIUM" "continue"
      echo -e "${YELLOW}Warning: DNS resolution failed for $server_endpoint${ENDCOLOR}"
      echo -e "${YELLOW}Falling back to IP address: $control_plane_ip${ENDCOLOR}"
      server_endpoint="$control_plane_ip"
      endpoint_type="IP address"
    fi
  fi

  # Create temporary directory for kubeconfig operations
  local temp_dir
  if ! temp_dir=$(mktemp -d 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to create temporary directory" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  local temp_kubeconfig="$temp_dir/admin.conf"

  # Cleanup function
  cleanup_temp() {
    if [[ -d "$temp_dir" ]]; then
      rm -rf "$temp_dir" 2>/dev/null || true
    fi
  }
  trap cleanup_temp EXIT

  # Get ansible config to determine remote user
  local ansible_dir="$repo_root/ansible"
  if ! validate_directory "$ansible_dir" "Ansible directory"; then
    return 1
  fi

  local ansible_cfg="$ansible_dir/ansible.cfg"
  if ! validate_file "$ansible_cfg" "Ansible configuration file"; then
    return 1
  fi

  local remote_user
  if ! remote_user=$(grep -Po '^remote_user\s*=\s*\K.*' "$ansible_cfg" 2>/dev/null); then
    log_warning "Could not determine remote user from ansible.cfg, using default 'root'"
    remote_user="root"
  fi

  echo -e "${BLUE}Retrieving kubeconfig from control plane node...${ENDCOLOR}"

  # Copy kubeconfig from control plane node using sudo with retry
  local max_retries=3
  local retry_count=0
  local ssh_success=false

  while [ $retry_count -le $max_retries ]; do
    if [ $retry_count -gt 0 ]; then
      log_info "Retrying SSH connection (attempt $((retry_count + 1))/$((max_retries + 1)))..."
      sleep 2
    fi

    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -o ConnectTimeout=10 \
         "${remote_user}@${control_plane_ip}" \
         "sudo cat /etc/kubernetes/admin.conf" > "$temp_kubeconfig" 2>/dev/null; then
      ssh_success=true
      break
    fi

    retry_count=$((retry_count + 1))

    if [ $retry_count -le $max_retries ]; then
      error_handle "$ERROR_EXECUTION" "SSH connection failed (attempt $retry_count), will retry" "$SEVERITY_MEDIUM" "retry"
    fi
  done

  if [ "$ssh_success" = false ]; then
    error_handle "$ERROR_EXECUTION" "Failed to retrieve kubeconfig from control plane node after $((retry_count)) attempts" "$SEVERITY_CRITICAL" "abort"
    echo -e "${RED}Make sure you can SSH to $control_plane_ip as user $remote_user and use sudo${ENDCOLOR}" >&2
    return 1
  fi

  # Validate kubeconfig file
  if [[ ! -s "$temp_kubeconfig" ]]; then
    error_handle "$ERROR_EXECUTION" "Retrieved kubeconfig file is empty" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Update server endpoint in the kubeconfig
  echo -e "${BLUE}Updating server endpoint to use $endpoint_type...${ENDCOLOR}"
  if ! sed -i "s|server: https://.*:6443|server: https://${server_endpoint}:6443|g" "$temp_kubeconfig" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to update server endpoint in kubeconfig" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Verify the endpoint is accessible
  echo -e "${BLUE}Testing connectivity to https://${server_endpoint}:6443...${ENDCOLOR}"
  if ! timeout 10 bash -c "echo > /dev/tcp/${server_endpoint}/6443" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Cannot connect to https://${server_endpoint}:6443" "$SEVERITY_MEDIUM" "continue"
    echo -e "${YELLOW}Warning: Cannot connect to https://${server_endpoint}:6443${ENDCOLOR}"
    if [ "$endpoint_type" = "hostname" ]; then
      echo -e "${YELLOW}Falling back to IP address: $control_plane_ip${ENDCOLOR}"
      server_endpoint="$control_plane_ip"
      if ! sed -i "s|server: https://.*:6443|server: https://${server_endpoint}:6443|g" "$temp_kubeconfig" 2>/dev/null; then
        error_handle "$ERROR_EXECUTION" "Failed to update server endpoint to IP fallback" "$SEVERITY_HIGH" "abort"
        return 1
      fi
    else
      echo -e "${YELLOW}Please ensure the API server is running and accessible${ENDCOLOR}"
    fi
  fi

  # Update context and user names to avoid conflicts
  if ! sed -i "s|kubernetes-admin@kubernetes|${context_name}|g" "$temp_kubeconfig" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to update context name in kubeconfig" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if ! sed -i "s|name: kubernetes-admin|name: ${context_name}-admin|g" "$temp_kubeconfig" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to update user name in kubeconfig" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if ! sed -i "s|name: kubernetes|name: ${context_name}-cluster|g" "$temp_kubeconfig" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to update cluster name in kubeconfig" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if ! sed -i "s|cluster: kubernetes|cluster: ${context_name}-cluster|g" "$temp_kubeconfig" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to update cluster reference in kubeconfig" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  if ! sed -i "s|user: kubernetes-admin|user: ${context_name}-admin|g" "$temp_kubeconfig" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to update user reference in kubeconfig" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Merge the kubeconfig
  echo -e "${BLUE}Merging kubeconfig into ~/.kube/config...${ENDCOLOR}"

  # Backup existing kubeconfig if it exists
  if [ -f ~/.kube/config ]; then
    local backup_file=~/.kube/config.backup.$(date +%Y%m%d_%H%M%S)
    if ! cp ~/.kube/config "$backup_file" 2>/dev/null; then
      error_handle "$ERROR_EXECUTION" "Failed to create backup of existing kubeconfig" "$SEVERITY_MEDIUM" "continue"
    else
      echo -e "${BLUE}Existing kubeconfig backed up to: $backup_file${ENDCOLOR}"
    fi
  fi

  # Ensure .kube directory exists
  if ! mkdir -p ~/.kube 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to create ~/.kube directory" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Merge kubeconfig
  if [ -f ~/.kube/config ] && [ -s ~/.kube/config ]; then
    # Existing config exists and is not empty

    # Remove existing context if it exists to avoid conflicts
    if kubectl config get-contexts -o name 2>/dev/null | grep -q "^${context_name}$"; then
      echo -e "${BLUE}Removing existing context '$context_name' to avoid conflicts...${ENDCOLOR}"
      kubectl config delete-context "$context_name" &>/dev/null || true
      kubectl config delete-cluster "${context_name}-cluster" &>/dev/null || true
      kubectl config delete-user "${context_name}-admin" &>/dev/null || true
    fi

    local temp_merged="$HOME/.kube/config.tmp"
    if ! KUBECONFIG=~/.kube/config:$temp_kubeconfig kubectl config view --flatten > "$temp_merged" 2>/dev/null; then
      error_handle "$ERROR_EXECUTION" "Failed to merge kubeconfig files" "$SEVERITY_HIGH" "abort"
      return 1
    fi

    if [ -s "$temp_merged" ]; then
      if ! mv "$temp_merged" ~/.kube/config 2>/dev/null; then
        error_handle "$ERROR_EXECUTION" "Failed to update kubeconfig file" "$SEVERITY_HIGH" "abort"
        return 1
      fi
    else
      error_handle "$ERROR_EXECUTION" "Merge resulted in empty config, using new config only" "$SEVERITY_MEDIUM" "continue"
      echo -e "${YELLOW}Warning: Merge resulted in empty config, using new config only${ENDCOLOR}"
      if ! cp "$temp_kubeconfig" ~/.kube/config 2>/dev/null; then
        error_handle "$ERROR_EXECUTION" "Failed to copy new kubeconfig" "$SEVERITY_HIGH" "abort"
        return 1
      fi
    fi
  else
    # No existing config or empty config
    if ! cp "$temp_kubeconfig" ~/.kube/config 2>/dev/null; then
      error_handle "$ERROR_EXECUTION" "Failed to copy kubeconfig to ~/.kube/config" "$SEVERITY_HIGH" "abort"
      return 1
    fi
  fi

  # Set permissions
  if ! chmod 600 ~/.kube/config 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to set permissions on kubeconfig file" "$SEVERITY_MEDIUM" "continue"
  fi

  # Test the connection
  echo -e "${BLUE}Testing cluster connection...${ENDCOLOR}"
  if kubectl --context="$context_name" cluster-info --request-timeout=10s >/dev/null 2>&1; then
    echo -e "${GREEN}Successfully configured kubeconfig for context '$context_name'${ENDCOLOR}"
    echo -e "${GREEN}Server: https://${server_endpoint}:6443${ENDCOLOR}"

    # Show cluster nodes
    echo -e "${BLUE}Cluster nodes:${ENDCOLOR}"
    if ! kubectl --context="$context_name" get nodes -o wide 2>/dev/null; then
      error_handle "$ERROR_EXECUTION" "Could not retrieve node information" "$SEVERITY_LOW" "continue"
      echo -e "${YELLOW}Could not retrieve node information${ENDCOLOR}"
    fi
  else
    error_handle "$ERROR_EXECUTION" "Kubeconfig configured but cluster connection test failed" "$SEVERITY_MEDIUM" "continue"
    echo -e "${YELLOW}Kubeconfig configured but cluster connection test failed${ENDCOLOR}"
    echo -e "${YELLOW}You may need to check network connectivity or certificate issues${ENDCOLOR}"
    echo -e "${BLUE}Try: kubectl --context='$context_name' get nodes${ENDCOLOR}"
  fi

  echo -e "${BLUE}Context '$context_name' is now available${ENDCOLOR}"
  echo -e "${BLUE}Switch to it with: kubectl config use-context $context_name${ENDCOLOR}"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Validate dependencies
  if ! validate_dependencies; then
    exit $ERROR_CONFIG
  fi

  # Validate configuration directory
  if ! validate_directory "$CONFIG_DIR" "Configuration directory"; then
    exit $ERROR_CONFIG
  fi

  # Validate repository path file
  if ! validate_file "$REPO_PATH_FILE" "Repository path file"; then
    exit $ERROR_CONFIG
  fi

  # Validate current cluster context file
  if ! validate_file "$CPC_CONTEXT_FILE" "Current cluster context file"; then
    exit $ERROR_CONFIG
  fi

  enhanced_get_kubeconfig "$@"
fi
