#!/bin/bash

# Verify that VM hostnames are correctly set
# Enhanced with error handling and recovery mechanisms
# This script connects to each node via SSH and checks the hostname

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
  echo "[INFO] $1"
}

log_error() {
  echo "[ERROR] $1" >&2
}

log_warning() {
  echo "[WARNING] $1"
}

log_success() {
  echo "[SUCCESS] $1"
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

  if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
  fi

  if ! command -v ssh &> /dev/null; then
    missing_deps+=("ssh")
  fi

  if ! command -v sops &> /dev/null; then
    missing_deps+=("sops")
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

# Function to get hostname from VM with retry
get_vm_hostname() {
  local ip="$1"
  local user="$2"
  local max_retries=3
  local retry_count=0

  while [ $retry_count -le $max_retries ]; do
    if [ $retry_count -gt 0 ]; then
      log_info "Retrying hostname check for $ip (attempt $((retry_count + 1))/$((max_retries + 1)))..."
      sleep 2
    fi

    local hostname
    if hostname=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$user@$ip" hostname 2>/dev/null); then
      echo "$hostname"
      return 0
    fi

    retry_count=$((retry_count + 1))

    if [ $retry_count -le $max_retries ]; then
      log_warning "SSH connection failed for $user@$ip (attempt $retry_count), will retry"
    fi
  done

  return 1
}

# Initialize recovery for hostname verification
recovery_checkpoint "verify_hostname_start" "Starting hostname verification process"

# Validate dependencies
if ! validate_dependencies; then
  exit 1
fi

# Get script directory and validate paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if ! validate_directory "$REPO_ROOT" "Repository root"; then
  exit 1
fi

# Source environment variables
CPC_ENV_FILE="$REPO_ROOT/cpc.env"
if [ -f "$CPC_ENV_FILE" ]; then
  if ! source "$CPC_ENV_FILE"; then
    error_handle "$ERROR_CONFIG" "Failed to source cpc.env configuration file" "$SEVERITY_HIGH" "abort"
    exit 1
  fi
else
  log_warning "cpc.env not found, will try to get credentials from terraform secrets"
fi

# Get Proxmox credentials if not set
if [ -z "$PROXMOX_HOST" ] || [ -z "$PROXMOX_USERNAME" ]; then
  log_info "PROXMOX_HOST or PROXMOX_USERNAME not set. Getting from terraform secrets..."

  terraform_dir="$REPO_ROOT/terraform"
  if ! validate_directory "$terraform_dir" "Terraform directory"; then
    exit 1
  fi

  secrets_file="$terraform_dir/secrets.sops.yaml"
  if ! validate_file "$secrets_file" "Terraform secrets file"; then
    exit 1
  fi

  if ! pushd "$terraform_dir" >/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to change to terraform directory" "$SEVERITY_HIGH" "abort"
    exit 1
  fi

  # Extract credentials from sops
  if ! PROXMOX_HOST=$(sops --decrypt --extract '["virtual_environment_endpoint"]' secrets.sops.yaml 2>/dev/null | sed 's|https://||' | sed 's|:8006/api2/json||' 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to extract PROXMOX_HOST from secrets" "$SEVERITY_HIGH" "abort"
    popd >/dev/null || true
    exit 1
  fi

  if ! PROXMOX_USERNAME=$(sops --decrypt --extract '["proxmox_username"]' secrets.sops.yaml 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to extract PROXMOX_USERNAME from secrets" "$SEVERITY_HIGH" "abort"
    popd >/dev/null || true
    exit 1
  fi

  if ! popd >/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to return to original directory" "$SEVERITY_HIGH" "abort"
    exit 1
  fi
fi

# Get node information from terraform
if ! validate_directory "$REPO_ROOT/terraform" "Terraform directory"; then
  exit 1
fi

if ! pushd "$REPO_ROOT/terraform" >/dev/null; then
  error_handle "$ERROR_EXECUTION" "Failed to change to terraform directory for node info" "$SEVERITY_HIGH" "abort"
  exit 1
fi

node_ips
node_names

if ! node_ips=$(tofu output -json k8s_node_ips 2>/dev/null); then
  error_handle "$ERROR_EXECUTION" "Failed to get node IPs from tofu output" "$SEVERITY_HIGH" "abort"
  popd >/dev/null || true
  exit 1
fi

if ! node_names=$(tofu output -json k8s_node_names 2>/dev/null); then
  error_handle "$ERROR_EXECUTION" "Failed to get node names from tofu output" "$SEVERITY_HIGH" "abort"
  popd >/dev/null || true
  exit 1
fi

if ! popd >/dev/null; then
  error_handle "$ERROR_EXECUTION" "Failed to return to original directory after getting node info" "$SEVERITY_HIGH" "abort"
  exit 1
fi

# Check if we got the node information
if [ -z "$node_ips" ] || [ "$node_ips" = "null" ] || [ -z "$node_names" ] || [ "$node_names" = "null" ]; then
  error_handle "$ERROR_EXECUTION" "Could not retrieve node information from terraform. Make sure the cluster is deployed" "$SEVERITY_HIGH" "abort"
  exit 1
fi

# Initialize counters
success_count=0
total_count=0
error_count=0

# Check if we got the node information
echo "Checking VM hostnames..."
echo "------------------------"
echo "| Node Key | IP Address | Expected Hostname | Actual Hostname | Status |"
echo "------------------------"

while read -r node_key ip_address; do
  total_count=$((total_count + 1))

  # Get the expected hostname for this node
  expected_hostname
  if ! expected_hostname=$(echo "$node_names" | jq -r ".[\"$node_key\"]" 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to extract expected hostname for $node_key" "$SEVERITY_MEDIUM" "continue"
    expected_hostname="ERROR"
  fi

  # Check the actual hostname on the VM
  actual_hostname=""

  # Try with VM_USERNAME from environment first
  if [ -n "$VM_USERNAME" ]; then
    if actual_hostname=$(get_vm_hostname "$ip_address" "$VM_USERNAME"); then
      log_info "Successfully connected to $ip_address as $VM_USERNAME"
    fi
  fi

  # Try with root user if VM_USERNAME doesn't work or is not set
  if [ -z "$actual_hostname" ]; then
    if actual_hostname=$(get_vm_hostname "$ip_address" "root"); then
      log_info "Successfully connected to $ip_address as root"
    fi
  fi

  # Determine status
  status
  if [ -z "$actual_hostname" ]; then
    status="ERROR: Could not connect"
    error_count=$((error_count + 1))
  elif [ "$actual_hostname" == "$expected_hostname" ]; then
    status="✓ MATCH"
    success_count=$((success_count + 1))
  else
    status="✗ MISMATCH"
    error_count=$((error_count + 1))
  fi

  # Print the results
  printf "| %-8s | %-10s | %-17s | %-15s | %-7s |\n" \
    "$node_key" "$ip_address" "$expected_hostname" "${actual_hostname:-N/A}" "$status"

done < <(echo "$node_ips" | jq -r 'to_entries[] | "\(.key) \(.value)"' 2>/dev/null)

echo "------------------------"
echo ""

# Summary
echo "Summary: $success_count of $total_count hostnames verified successfully."

if [ $error_count -gt 0 ]; then
  echo "Errors: $error_count hostname verification(s) failed."
fi

# Provide instructions for fixing hostnames if needed
if [ $success_count -lt $total_count ]; then
  echo ""
  echo "Some hostname verifications failed. To fix a hostname on a specific VM, use:"
  echo "./fix_vm_hostname.sh <vm_id> <hostname>"
  echo ""
  echo "Example: ./fix_vm_hostname.sh 300 cu1.bevz.net"
fi

if [ $success_count -eq $total_count ]; then
  log_success "All hostname verifications passed!"
else
  log_warning "Some hostname verifications failed. Check the output above for details."
fi

exit 0
