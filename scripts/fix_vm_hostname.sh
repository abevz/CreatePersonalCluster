#!/bin/bash

# Color definitions
GREEN='\033[32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[1;34m'
ENDCOLOR='\033[0m'

# Check if VM_ID is provided
if [ -z "$1" ]; then
  echo -e "${RED}Error: VM ID is required as first argument${ENDCOLOR}"
  echo "Usage: $0 <vm_id> [new_hostname]"
  exit 1
fi

VM_ID=$1
NEW_HOSTNAME=$2

# If no hostname is provided, generate one based on VM info
if [ -z "$NEW_HOSTNAME" ]; then
  # Get VM name from Proxmox
  echo -e "${BLUE}No hostname specified, attempting to generate one from VM name...${ENDCOLOR}"
  
  # Check if we have environment variables
  if [ -z "$PROXMOX_HOST" ] || [ -z "$PROXMOX_USERNAME" ]; then
    echo -e "${YELLOW}PROXMOX_HOST or PROXMOX_USERNAME not set. Setting from terraform secrets...${ENDCOLOR}"
    cd ~/Projects/kubernetes/my-kthw/terraform
    PROXMOX_HOST=$(sops --decrypt --extract '["virtual_environment_endpoint"]' secrets.sops.yaml | sed 's|https://||' | sed 's|:8006/api2/json||')
    PROXMOX_USERNAME=$(sops --decrypt --extract '["proxmox_username"]' secrets.sops.yaml)
    cd - > /dev/null
  fi
  
  # Get VM name
  VM_NAME=$(ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm config $VM_ID" | grep "^name:" | awk '{print $2}')
  if [ -z "$VM_NAME" ]; then
    echo -e "${RED}Error: Could not retrieve VM name from Proxmox. Specify hostname manually.${ENDCOLOR}"
    exit 1
  fi
  
  NEW_HOSTNAME=$VM_NAME
  echo -e "${GREEN}Generated hostname: $NEW_HOSTNAME${ENDCOLOR}"
fi

# Check if we have environment variables
if [ -z "$PROXMOX_HOST" ] || [ -z "$PROXMOX_USERNAME" ]; then
  echo -e "${YELLOW}PROXMOX_HOST or PROXMOX_USERNAME not set. Setting from terraform secrets...${ENDCOLOR}"
  cd ~/Projects/kubernetes/my-kthw/terraform
  PROXMOX_HOST=$(sops --decrypt --extract '["virtual_environment_endpoint"]' secrets.sops.yaml | sed 's|https://||' | sed 's|:8006/api2/json||')
  PROXMOX_USERNAME=$(sops --decrypt --extract '["proxmox_username"]' secrets.sops.yaml)
  cd - > /dev/null
fi

echo -e "${BLUE}Checking current hostname...${ENDCOLOR}"
CURRENT_HOSTNAME=$(ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec $VM_ID -- hostname")
echo -e "${GREEN}Current hostname: $CURRENT_HOSTNAME${ENDCOLOR}"

echo -e "${BLUE}Setting hostname to $NEW_HOSTNAME...${ENDCOLOR}"

# Set hostname using hostnamectl
ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec $VM_ID -- bash -c 'hostnamectl set-hostname $NEW_HOSTNAME'"

# Update /etc/hosts to include the new hostname
ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec $VM_ID -- bash -c \"sed -i '/127.0.1.1/d' /etc/hosts && echo '127.0.1.1 $NEW_HOSTNAME' >> /etc/hosts\""

# Update cloud-init preferences to preserve hostname on next boot
ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec $VM_ID -- bash -c 'echo \"preserve_hostname: true\" > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg'"

# Verify changes
echo -e "${BLUE}Verifying hostname change...${ENDCOLOR}"
NEW_CURRENT_HOSTNAME=$(ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec $VM_ID -- hostname")
echo -e "${GREEN}New hostname: $NEW_CURRENT_HOSTNAME${ENDCOLOR}"

# Show hosts file
echo -e "${BLUE}Updated /etc/hosts:${ENDCOLOR}"
ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec $VM_ID -- cat /etc/hosts"

echo -e "${GREEN}Hostname update complete!${ENDCOLOR}"
