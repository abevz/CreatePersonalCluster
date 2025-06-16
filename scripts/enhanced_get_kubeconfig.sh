#!/bin/bash

# Color definitions
export GREEN='\033[32m'
export RED='\033[0;31m'
export YELLOW='\033[0;33m'
export BLUE='\033[1;34m'
export ENDCOLOR='\033[0m'

# Configuration
CONFIG_DIR="$HOME/.config/my-kthw-cpc"
REPO_PATH_FILE="$CONFIG_DIR/repo_path"
CLUSTER_CONTEXT_FILE="$CONFIG_DIR/current_cluster_context"

# Helper functions
get_repo_path() {
  if [ -f "$REPO_PATH_FILE" ]; then
    cat "$REPO_PATH_FILE"
  else
    echo -e "${RED}Repository path not set. Run 'cpc setup-cpc' to set this value.${ENDCOLOR}" >&2
    exit 1
  fi
}

get_current_cluster_context() {
  if [ -f "$CLUSTER_CONTEXT_FILE" ]; then
    cat "$CLUSTER_CONTEXT_FILE"
  else
    echo -e "${RED}Error: No cpc context set.${ENDCOLOR}" >&2
    exit 1
  fi
}

# Enhanced get-kubeconfig function that prefers DNS hostnames over IP addresses
# This function should replace the existing get-kubeconfig functionality in cpc

enhanced_get_kubeconfig() {
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
        echo -e "${RED}Unknown option: $1${ENDCOLOR}" >&2
        return 1
        ;;
    esac
  done

  # Check if secrets are loaded
  check_secrets_loaded

  current_ctx=$(get_current_cluster_context)
  repo_root=$(get_repo_path)
  
  # Set context name
  if [ -z "$custom_context_name" ]; then
    context_name="cluster-${current_ctx}"
  else
    context_name="$custom_context_name"
  fi

  echo -e "${BLUE}Retrieving kubeconfig for cluster context: $current_ctx${ENDCOLOR}"
  echo -e "${BLUE}Kubernetes context will be named: $context_name${ENDCOLOR}"

  # Warn if context already exists
  if kubectl config get-contexts -o name | grep -q "^${context_name}$"; then
    if [ "$force_overwrite" = false ]; then
      echo -e "${YELLOW}Context '$context_name' already exists and will be overwritten.${ENDCOLOR}"
      echo -e "${YELLOW}Use --context-name to use a different name if desired.${ENDCOLOR}"
    else
      echo -e "${BLUE}Context '$context_name' exists and will be overwritten (--force specified).${ENDCOLOR}"
    fi
  fi

  # Get control plane information from Terraform/Tofu output
  pushd "$repo_root/terraform" > /dev/null || { echo -e "${RED}Failed to change to terraform directory${ENDCOLOR}"; return 1; }
  
  # Ensure we're in the correct workspace
  if ! tofu workspace select "$current_ctx" &>/dev/null; then
    echo -e "${RED}Failed to select Tofu workspace '$current_ctx'${ENDCOLOR}" >&2
    popd > /dev/null
    return 1
  fi

  # Get control plane node IP and hostname
  control_plane_ip=$(tofu output -json k8s_node_ips 2>/dev/null | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value')
  control_plane_hostname=$(tofu output -json k8s_node_names 2>/dev/null | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value')
  
  if [ -z "$control_plane_ip" ] || [ "$control_plane_ip" = "null" ]; then
    echo -e "${RED}Failed to get control plane IP from Tofu output${ENDCOLOR}" >&2
    echo -e "${RED}Make sure the cluster is deployed and 'tofu output k8s_node_ips' returns valid data${ENDCOLOR}" >&2
    popd > /dev/null
    return 1
  fi

  popd > /dev/null

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
      echo -e "${YELLOW}Warning: DNS resolution failed for $server_endpoint${ENDCOLOR}"
      echo -e "${YELLOW}Falling back to IP address: $control_plane_ip${ENDCOLOR}"
      server_endpoint="$control_plane_ip"
      endpoint_type="IP address"
    fi
  fi

  # Create temporary directory for kubeconfig operations
  temp_dir=$(mktemp -d)
  temp_kubeconfig="$temp_dir/admin.conf"
  
  # Cleanup function
  cleanup_temp() {
    rm -rf "$temp_dir"
  }
  trap cleanup_temp EXIT

  # Get ansible config to determine remote user
  ansible_dir="$repo_root/ansible"
  remote_user=$(grep -Po '^remote_user\s*=\s*\K.*' "$ansible_dir/ansible.cfg" 2>/dev/null || echo 'root')

  echo -e "${BLUE}Retrieving kubeconfig from control plane node...${ENDCOLOR}"
  
  # Copy kubeconfig from control plane node using sudo
  if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       "${remote_user}@${control_plane_ip}" \
       "sudo cat /etc/kubernetes/admin.conf" > "$temp_kubeconfig" 2>/dev/null; then
    echo -e "${RED}Failed to retrieve kubeconfig from control plane node${ENDCOLOR}" >&2
    echo -e "${RED}Make sure you can SSH to $control_plane_ip as user $remote_user and use sudo${ENDCOLOR}" >&2
    return 1
  fi

  # Update server endpoint in the kubeconfig
  echo -e "${BLUE}Updating server endpoint to use $endpoint_type...${ENDCOLOR}"
  if ! sed -i "s|server: https://.*:6443|server: https://${server_endpoint}:6443|g" "$temp_kubeconfig"; then
    echo -e "${RED}Failed to update server endpoint in kubeconfig${ENDCOLOR}" >&2
    return 1
  fi

  # Verify the endpoint is accessible
  echo -e "${BLUE}Testing connectivity to https://${server_endpoint}:6443...${ENDCOLOR}"
  if ! timeout 10 bash -c "echo > /dev/tcp/${server_endpoint}/6443" 2>/dev/null; then
    echo -e "${YELLOW}Warning: Cannot connect to https://${server_endpoint}:6443${ENDCOLOR}"
    if [ "$endpoint_type" = "hostname" ]; then
      echo -e "${YELLOW}Falling back to IP address: $control_plane_ip${ENDCOLOR}"
      server_endpoint="$control_plane_ip"
      sed -i "s|server: https://.*:6443|server: https://${server_endpoint}:6443|g" "$temp_kubeconfig"
    else
      echo -e "${YELLOW}Please ensure the API server is running and accessible${ENDCOLOR}"
    fi
  fi

  # Update context and user names to avoid conflicts
  if ! sed -i "s|kubernetes-admin@kubernetes|${context_name}|g" "$temp_kubeconfig"; then
    echo -e "${RED}Failed to update context name in kubeconfig${ENDCOLOR}" >&2
    return 1
  fi

  if ! sed -i "s|name: kubernetes-admin|name: ${context_name}-admin|g" "$temp_kubeconfig"; then
    echo -e "${RED}Failed to update user name in kubeconfig${ENDCOLOR}" >&2
    return 1
  fi

  if ! sed -i "s|name: kubernetes|name: ${context_name}-cluster|g" "$temp_kubeconfig"; then
    echo -e "${RED}Failed to update cluster name in kubeconfig${ENDCOLOR}" >&2
    return 1
  fi

  if ! sed -i "s|cluster: kubernetes|cluster: ${context_name}-cluster|g" "$temp_kubeconfig"; then
    echo -e "${RED}Failed to update cluster reference in kubeconfig${ENDCOLOR}" >&2
    return 1
  fi

  if ! sed -i "s|user: kubernetes-admin|user: ${context_name}-admin|g" "$temp_kubeconfig"; then
    echo -e "${RED}Failed to update user reference in kubeconfig${ENDCOLOR}" >&2
    return 1
  fi

  # Merge the kubeconfig
  echo -e "${BLUE}Merging kubeconfig into ~/.kube/config...${ENDCOLOR}"
  
  # Backup existing kubeconfig if it exists
  if [ -f ~/.kube/config ]; then
    cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d_%H%M%S)
    echo -e "${BLUE}Existing kubeconfig backed up${ENDCOLOR}"
  fi

  # Ensure .kube directory exists
  mkdir -p ~/.kube

  # Merge kubeconfig
  if [ -f ~/.kube/config ] && [ -s ~/.kube/config ]; then
    # Existing config exists and is not empty
    
    # Remove existing context if it exists to avoid conflicts
    if kubectl config get-contexts -o name | grep -q "^${context_name}$"; then
      echo -e "${BLUE}Removing existing context '$context_name' to avoid conflicts...${ENDCOLOR}"
      kubectl config delete-context "$context_name" &>/dev/null || true
      kubectl config delete-cluster "${context_name}-cluster" &>/dev/null || true
      kubectl config delete-user "${context_name}-admin" &>/dev/null || true
    fi
    
    KUBECONFIG=~/.kube/config:$temp_kubeconfig kubectl config view --flatten > ~/.kube/config.tmp
    if [ -s ~/.kube/config.tmp ]; then
      mv ~/.kube/config.tmp ~/.kube/config
    else
      echo -e "${YELLOW}Warning: Merge resulted in empty config, using new config only${ENDCOLOR}"
      cp "$temp_kubeconfig" ~/.kube/config
    fi
  else
    # No existing config or empty config
    cp "$temp_kubeconfig" ~/.kube/config
  fi

  # Set permissions
  chmod 600 ~/.kube/config

  # Test the connection
  echo -e "${BLUE}Testing cluster connection...${ENDCOLOR}"
  if kubectl --context="$context_name" cluster-info --request-timeout=10s >/dev/null 2>&1; then
    echo -e "${GREEN}Successfully configured kubeconfig for context '$context_name'${ENDCOLOR}"
    echo -e "${GREEN}Server: https://${server_endpoint}:6443${ENDCOLOR}"
    
    # Show cluster nodes
    echo -e "${BLUE}Cluster nodes:${ENDCOLOR}"
    kubectl --context="$context_name" get nodes -o wide 2>/dev/null || echo -e "${YELLOW}Could not retrieve node information${ENDCOLOR}"
  else
    echo -e "${YELLOW}Kubeconfig configured but cluster connection test failed${ENDCOLOR}"
    echo -e "${YELLOW}You may need to check network connectivity or certificate issues${ENDCOLOR}"
    echo -e "${BLUE}Try: kubectl --context='$context_name' get nodes${ENDCOLOR}"
  fi

  echo -e "${BLUE}Context '$context_name' is now available${ENDCOLOR}"
  echo -e "${BLUE}Switch to it with: kubectl config use-context $context_name${ENDCOLOR}"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  enhanced_get_kubeconfig "$@"
fi
