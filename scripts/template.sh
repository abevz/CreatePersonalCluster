#!/bin/bash

# =============================================================================
# CPC Template Creation Script with Error Handling
# =============================================================================

# Load error handling libraries if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Try to load error handling libraries
if [[ -f "$REPO_ROOT/lib/error_handling.sh" ]]; then
    source "$REPO_ROOT/lib/error_handling.sh"
    source "$REPO_ROOT/lib/retry.sh"
    source "$REPO_ROOT/lib/timeout.sh"
    source "$REPO_ROOT/lib/recovery.sh"

    # Initialize error handling
    error_init
    retry_init
    timeout_init
    recovery_init
fi

# Variables like REPO_PATH, NON_PASSWORD_PROTECTED_SSH_KEY, PROXMOX_USERNAME, 
# PROXMOX_HOST, TEMPLATE_VM_ID are expected to be set in the environment, 
# typically by the calling 'cpc' script sourcing 'cpc.env'.
# GREEN and ENDCOLOR are kept for script output styling.
GREEN="\033[0;32m"
ENDCOLOR="\033[0m"

usage() {
    echo "Usage: cpc template"
    echo ""
    echo "Copies vm template creation files over to your proxmox node and runs them. This downloads a vm image, edits it, allows it to turn on, then installs various packages into it before turning it off and templating it."
    echo "All required variables are loaded automatically from cpc.env and secrets.sops.yaml via the cpc script."
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
        case $1 in
                -h|--help) usage; exit 0 ;;
                *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
        esac
        shift
done

# Check for necessary environment variables (SOPS secrets loaded by cpc)
: "${REPO_PATH:?REPO_PATH is not set. Please set it in your environment or cpc.env.}"
: "${TEMPLATE_VM_ID:?TEMPLATE_VM_ID is not set. Please ensure workspace is set correctly.}"

# Note: PROXMOX_HOST, PROXMOX_USERNAME, VM_SSH_KEY loaded from secrets.sops.yaml via SOPS

cd "$REPO_PATH/scripts"

echo -e "${GREEN}Copying relevant files to Proxmox host...${ENDCOLOR}"

# Create temporary SSH key files from SOPS secrets with error handling
TEMP_SSH_KEY=$(mktemp) || {
    error_handle "$ERROR_EXECUTION" "Failed to create temporary SSH key file" "$SEVERITY_HIGH" "abort"
    exit 1
}
TEMP_SSH_PUB_KEY=$(mktemp) || {
    error_handle "$ERROR_EXECUTION" "Failed to create temporary SSH public key file" "$SEVERITY_HIGH" "abort"
    exit 1
}

echo "$VM_SSH_KEY" > "$TEMP_SSH_PUB_KEY" || {
    error_handle "$ERROR_EXECUTION" "Failed to write SSH public key to temporary file" "$SEVERITY_HIGH" "abort"
    exit 1
}

# Setup SSH connection with retry
log_info "Setting up SSH connection to Proxmox host..."
if ! retry_network_operation \
     "ssh-copy-id -f '$PROXMOX_USERNAME@$PROXMOX_HOST' 2>/dev/null" \
     "SSH key copy to Proxmox host" \
     3 \
     5; then
    log_warning "SSH key copy failed, but may already be present"
fi

# Copy files to Proxmox host with error handling and retry
log_info "Copying template files to Proxmox host..."

# Create scripts directory with error handling
if ! retry_network_operation \
     "ssh '$PROXMOX_USERNAME@$PROXMOX_HOST' 'mkdir -p scripts'" \
     "Create scripts directory on Proxmox" \
     3 \
     2; then
    error_handle "$ERROR_NETWORK" "Failed to create scripts directory on Proxmox host" "$SEVERITY_HIGH" "abort"
    exit 1
fi

# Copy vm_template directory with error handling
if ! retry_network_operation \
     "scp -q -r ./vm_template '$PROXMOX_USERNAME@$PROXMOX_HOST:scripts/'" \
     "Copy vm_template directory" \
     3 \
     10; then
    error_handle "$ERROR_NETWORK" "Failed to copy vm_template directory to Proxmox host" "$SEVERITY_HIGH" "abort"
    exit 1
fi

# Copy cpc.env file with error handling
if ! retry_network_operation \
     "scp -q '$REPO_PATH/cpc.env' '$PROXMOX_USERNAME@$PROXMOX_HOST:scripts/vm_template/'" \
     "Copy cpc.env file" \
     3 \
     5; then
    error_handle "$ERROR_NETWORK" "Failed to copy cpc.env to Proxmox host" "$SEVERITY_HIGH" "abort"
    exit 1
fi

# Copy SSH public key with error handling
if ! retry_network_operation \
     "scp -q '$TEMP_SSH_PUB_KEY' '$PROXMOX_USERNAME@$PROXMOX_HOST:scripts/vm_template/vm_ssh_key.pub'" \
     "Copy SSH public key" \
     3 \
     5; then
    error_handle "$ERROR_NETWORK" "Failed to copy SSH public key to Proxmox host" "$SEVERITY_HIGH" "abort"
    exit 1
fi

# Copy cloud-init files if they exist
for cloud_init_file in "debian-cloud-init-userdata.yaml" "ubuntu-cloud-init-userdata.yaml"; do
    if [ -f "./vm_template/$cloud_init_file" ]; then
        if ! retry_network_operation \
             "scp -q './vm_template/$cloud_init_file' '$PROXMOX_USERNAME@$PROXMOX_HOST:scripts/vm_template/'" \
             "Copy $cloud_init_file" \
             3 \
             5; then
            log_warning "Failed to copy $cloud_init_file to Proxmox host"
        fi
    fi
done

# Copy machine-id script if it exists
if [ -f "./vm_template/ensure-unique-machine-id.sh" ]; then
    if ! retry_network_operation \
         "scp -q './vm_template/ensure-unique-machine-id.sh' '$PROXMOX_USERNAME@$PROXMOX_HOST:scripts/vm_template/'" \
         "Copy machine-id script" \
         3 \
         5; then
        log_warning "Failed to copy machine-id script to Proxmox host"
    fi
fi

# Clean up temporary files
rm -f "$TEMP_SSH_KEY" "$TEMP_SSH_PUB_KEY"

echo -e "${GREEN}Executing helper script on Proxmox host to create a k8s template vm (id: $TEMPLATE_VM_ID)${ENDCOLOR}"

# Execute template creation script on Proxmox host with timeout and error handling
TEMPLATE_COMMAND="
export PROXMOX_HOST='$PROXMOX_HOST'
export PROXMOX_USERNAME='$PROXMOX_USERNAME'
export PROXMOX_PASSWORD='$PROXMOX_PASSWORD'
export VM_USERNAME='$VM_USERNAME'
export VM_PASSWORD='$VM_PASSWORD'
export VM_SSH_KEY='$VM_SSH_KEY'
export TEMPLATE_VM_ID='$TEMPLATE_VM_ID'
export TEMPLATE_VM_NAME='$TEMPLATE_VM_NAME'
export IMAGE_NAME='$IMAGE_NAME'
export IMAGE_LINK='$IMAGE_LINK'
export KUBERNETES_VERSION='$KUBERNETES_VERSION'
export KUBERNETES_MEDIUM_VERSION='$KUBERNETES_MEDIUM_VERSION'
export KUBERNETES_LONG_VERSION='$KUBERNETES_LONG_VERSION'
export CNI_PLUGINS_VERSION='$CNI_PLUGINS_VERSION'
export CALICO_VERSION='$CALICO_VERSION'
export METALLB_VERSION='$METALLB_VERSION'
export COREDNS_VERSION='$COREDNS_VERSION'
export METRICS_SERVER_VERSION='$METRICS_SERVER_VERSION'
export ETCD_VERSION='$ETCD_VERSION'
export KUBELET_SERVING_CERT_APPROVER_VERSION='$KUBELET_SERVING_CERT_APPROVER_VERSION'
export LOCAL_PATH_PROVISIONER_VERSION='$LOCAL_PATH_PROVISIONER_VERSION'
export PROXMOX_STORAGE_BASE_PATH='$PROXMOX_STORAGE_BASE_PATH'
export PROXMOX_DISK_DATASTORE='$PROXMOX_DISK_DATASTORE'
export PROXMOX_ISO_PATH='$PROXMOX_ISO_PATH'
cd scripts/vm_template && chmod +x ./create_template_dispatcher.sh && ./create_template_dispatcher.sh
"

if ! timeout_execute \
     "ssh '$PROXMOX_USERNAME@$PROXMOX_HOST' '$TEMPLATE_COMMAND'" \
     3600 \
     "Template creation on Proxmox host" \
     "cleanup_template_remote"; then
    error_handle "$ERROR_EXECUTION" "Template creation failed on Proxmox host" "$SEVERITY_HIGH"
    exit 1
fi

# Clean up remote files
if ! retry_network_operation \
     "ssh '$PROXMOX_USERNAME@$PROXMOX_HOST' 'rm -rf scripts'" \
     "Clean up remote scripts directory" \
     3 \
     5; then
    log_warning "Failed to clean up remote scripts directory"
fi

log_success "Template creation completed successfully"

# Cleanup function for remote template creation failures
cleanup_template_remote() {
    log_warning "Cleaning up after template creation failure on remote host..."

    # Try to clean up remote files
    ssh "$PROXMOX_USERNAME@$PROXMOX_HOST" "rm -rf scripts" 2>/dev/null || true

    # Try to destroy any partially created VM
    if [[ -n "$TEMPLATE_VM_ID" ]]; then
        ssh "$PROXMOX_USERNAME@$PROXMOX_HOST" "qm stop $TEMPLATE_VM_ID 2>/dev/null; qm destroy $TEMPLATE_VM_ID 2>/dev/null" || true
    fi

    log_info "Remote cleanup completed"
}
