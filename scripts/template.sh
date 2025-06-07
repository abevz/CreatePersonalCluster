#!/bin/bash

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
set -e

# Create temporary SSH key files from SOPS secrets
TEMP_SSH_KEY=$(mktemp)
TEMP_SSH_PUB_KEY=$(mktemp)
echo "$VM_SSH_KEY" > "$TEMP_SSH_PUB_KEY"

# Extract private key from SSH public key is not possible, so we'll use existing SSH agent or key
# For now, we'll assume the SSH key is already set up for the current user
ssh-copy-id -f "$PROXMOX_USERNAME"@"$PROXMOX_HOST" 2>/dev/null || echo "SSH key copy failed, but may already be present"

# Copy the vm_template directory (containing create_template_helper.sh and other assets)
scp -q -r ./vm_template "$PROXMOX_USERNAME"@"$PROXMOX_HOST":
# Copy the main cpc.env file to the vm_template directory on the Proxmox host
scp -q "${REPO_PATH}/cpc.env" "$PROXMOX_USERNAME"@"$PROXMOX_HOST":vm_template/
# Copy the SSH public key from our temporary file
scp -q "$TEMP_SSH_PUB_KEY" "$PROXMOX_USERNAME"@"$PROXMOX_HOST":vm_template/vm_ssh_key.pub
# Copy the Debian cloud-init user-data file if it exists
if [ -f "./vm_template/debian-cloud-init-userdata.yaml" ]; then
    scp -q "./vm_template/debian-cloud-init-userdata.yaml" "$PROXMOX_USERNAME"@"$PROXMOX_HOST":vm_template/
fi

# Copy the Ubuntu cloud-init user-data file if it exists
if [ -f "./vm_template/ubuntu-cloud-init-userdata.yaml" ]; then
    scp -q "./vm_template/ubuntu-cloud-init-userdata.yaml" "$PROXMOX_USERNAME"@"$PROXMOX_HOST":vm_template/
fi

# Copy the machine-id script
if [ -f "./vm_template/ensure-unique-machine-id.sh" ]; then
    scp -q "./vm_template/ensure-unique-machine-id.sh" "$PROXMOX_USERNAME"@"$PROXMOX_HOST":vm_template/
fi

# Clean up temporary files
rm -f "$TEMP_SSH_KEY" "$TEMP_SSH_PUB_KEY"
set +e

echo -e "${GREEN}Executing helper script on Proxmox host to create a k8s template vm (id: $TEMPLATE_VM_ID)${ENDCOLOR}"

# Pass environment variables through SSH and execute the helper script
ssh "$PROXMOX_USERNAME"@"$PROXMOX_HOST" "
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
cd vm_template && chmod +x ./create_template_helper.sh && ./create_template_helper.sh
"
ssh "$PROXMOX_USERNAME"@"$PROXMOX_HOST" "rm -rf vm_template"
