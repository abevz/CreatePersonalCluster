#!/bin/bash

# Rocky Linux-specific VM template creation script
# This script handles all Rocky Linux-specific logic for template creation

# Import shared functions
# Auto-detect if running locally (with REPO_PATH) or remotely (relative paths)
if [[ -n "$REPO_PATH" && -f "$REPO_PATH/scripts/vm_template/shared/common_functions.sh" ]]; then
    # Running locally via cpc - use REPO_PATH
    source "$REPO_PATH/scripts/vm_template/shared/common_functions.sh"
    SCRIPT_BASE_PATH="$REPO_PATH/scripts/vm_template"
else
    # Running remotely on Proxmox host - use relative paths
    # First, try to find the script directory
    SCRIPT_DIR="$(dirname "$0")"
    
    # Debug: Show current directory and script location
    echo "Debug: Current directory: $(pwd)"
    echo "Debug: Script directory: $SCRIPT_DIR"
    echo "Debug: Looking for common_functions.sh at: $SCRIPT_DIR/../shared/common_functions.sh"
    
    # Check if common_functions.sh exists in expected location
    if [[ -f "$SCRIPT_DIR/../shared/common_functions.sh" ]]; then
        source "$SCRIPT_DIR/../shared/common_functions.sh"
        SCRIPT_BASE_PATH="$SCRIPT_DIR/.."
    else
        # Try alternative paths
        echo "Debug: Trying alternative paths..."
        
        # Look for common_functions.sh in current directory tree
        for possible_path in "shared/common_functions.sh" "../shared/common_functions.sh" "../../shared/common_functions.sh"; do
            echo "Debug: Checking $possible_path" 
            if [[ -f "$possible_path" ]]; then
                source "$possible_path"
                SCRIPT_BASE_PATH="$(dirname "$possible_path")"
                break
            fi
        done
    fi
fi

# Rocky Linux-specific functions
rocky_pre_setup() {
    echo -e "${GREEN}Rocky Linux Pre-Setup: Skipping virt-customize due to libguestfs compatibility issues...${ENDCOLOR}"
    echo -e "${GREEN}Rocky Linux configuration will be handled during VM boot via cloud-init...${ENDCOLOR}"
    # Create a marker file to indicate Rocky Linux image was processed differently
    touch /tmp/rocky_skip_virt_customize
}

rocky_prepare_cloud_init() {
    echo -e "${GREEN}Preparing Rocky Linux cloud-init user-data...${ENDCOLOR}"
    
    # Debug: Show SSH key information
    echo -e "${BLUE}Debug: SSH_KEY_FILE=$SSH_KEY_FILE${ENDCOLOR}"
    echo -e "${BLUE}Debug: VM_SSH_KEY (first 50 chars): ${VM_SSH_KEY:0:50}...${ENDCOLOR}"
    if [[ -f "$SSH_KEY_FILE" ]]; then
        echo -e "${GREEN}SSH key file exists and is readable${ENDCOLOR}"
    else
        echo -e "${RED}ERROR: SSH key file $SSH_KEY_FILE does not exist!${ENDCOLOR}"
        return 1
    fi
    
    local rocky_userdata="$SCRIPT_BASE_PATH/rocky/rocky-cloud-init-userdata.yaml"
    if [ ! -f "$rocky_userdata" ]; then
        echo -e "${RED}Error: rocky-cloud-init-userdata.yaml not found at $rocky_userdata!${ENDCOLOR}"
        return 1
    fi
    
    # Create temporary cloud-init user-data file for this specific VM
    local temp_userdata="/tmp/rocky-userdata-${TEMPLATE_VM_ID}.yaml"
    
    # Replace variables in the cloud-init file
    echo -e "${GREEN}Processing cloud-init template variables...${ENDCOLOR}"
    # Set VM_HOSTNAME to template name + ID for better identification
    local vm_hostname="rocky-template-${TEMPLATE_VM_ID}"
    cat "$rocky_userdata" | \
        sed "s|\${VM_USERNAME}|$VM_USERNAME|g" | \
        sed "s|\${VM_SSH_KEY}|$VM_SSH_KEY|g" | \
        sed "s|\${VM_HOSTNAME}|$vm_hostname|g" > "$temp_userdata"
    
    # Copy the user-data file to Proxmox snippets directory first
    echo -e "${GREEN}Copying cloud-init user-data to Proxmox snippets directory...${ENDCOLOR}"
    local snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo mkdir -p "$snippets_path"
    sudo cp "$temp_userdata" "${snippets_path}/rocky-userdata-${TEMPLATE_VM_ID}.yaml"
    sudo chmod 644 "${snippets_path}/rocky-userdata-${TEMPLATE_VM_ID}.yaml"
    
    # Also create a generic rocky-userdata.yaml for future VM deployments
    sudo cp "$temp_userdata" "${snippets_path}/rocky-userdata.yaml"
    sudo chmod 644 "${snippets_path}/rocky-userdata.yaml"
    echo -e "${GREEN}Created generic rocky-userdata.yaml for VM deployments${ENDCOLOR}"
    
    # Clean up temporary file
    rm -f "$temp_userdata"
    
    echo -e "${GREEN}Rocky Linux cloud-init preparation completed.${ENDCOLOR}"
    return 0
}

rocky_configure_vm() {
    echo -e "${GREEN}Configuring Rocky Linux VM with cloud-init settings...${ENDCOLOR}"
    
    # Prepare cloud-init configuration first
    if ! rocky_prepare_cloud_init; then
        echo -e "${RED}Failed to prepare Rocky Linux cloud-init configuration${ENDCOLOR}"
        return 1
    fi
    
    # Configure VM with Rocky-specific settings
    sudo qm set "$TEMPLATE_VM_ID" \
      --scsihw virtio-scsi-pci \
      --virtio0 "${PROXMOX_DISK_DATASTORE}:0,iothread=1,import-from=$PROXMOX_ISO_PATH/$IMAGE_NAME" \
      --ide2 "${PROXMOX_DISK_DATASTORE}:cloudinit" \
      --boot c \
      --bootdisk virtio0 \
      --serial0 socket \
      --vga serial0 \
      --ciuser "$VM_USERNAME" \
      --cipassword "$VM_PASSWORD" \
      --ipconfig0 "gw=$TEMPLATE_VM_GATEWAY,ip=$TEMPLATE_VM_IP" \
      --nameserver "$TWO_DNS_SERVERS $TEMPLATE_VM_GATEWAY" \
      --searchdomain "$TEMPLATE_VM_SEARCH_DOMAIN" \
      --sshkeys "$SSH_KEY_FILE" \
      --cicustom "user=${PROXMOX_DISK_DATASTORE}:snippets/rocky-userdata-${TEMPLATE_VM_ID}.yaml" \
      --agent "enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1" \
      --hotplug cpu,disk,network,usb \
      --tags "$EXTRA_TEMPLATE_TAGS ${KUBERNETES_MEDIUM_VERSION}"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to configure Rocky Linux VM${ENDCOLOR}"
        return 1
    fi
    
    echo -e "${GREEN}Rocky Linux VM configuration completed.${ENDCOLOR}"
    return 0
}

rocky_wait_for_completion() {
    echo -e "${GREEN}Waiting for Rocky Linux package installation to complete...${ENDCOLOR}"
    
    local max_timeout=300  # 30 minutes
    local timeout_counter=0
    local start_time_total=$(date +%s)  # Add missing variable
    
    echo -e -n "${GREEN}Waiting for all packages to be installed${ENDCOLOR}"
    while [[ $timeout_counter -lt $max_timeout ]]; do
        # Check for the completion marker file
        output=$(sudo qm guest exec "$TEMPLATE_VM_ID" cat /tmp/.firstboot 2>/dev/null)
        success=$?
        if [[ $success -eq 0 ]]; then
            echo -e "\n${GREEN}Rocky Linux package installation complete.${ENDCOLOR}"
            break
        fi
        
        # Check for timeout
        timeout_counter=$((timeout_counter + 2))
        if [[ $timeout_counter -gt $max_timeout ]]; then
            echo -e "\n${RED}Timeout waiting for Rocky Linux packages to install after $max_timeout seconds. Continuing anyway...${ENDCOLOR}"
            break
        fi
        
        echo -n "."
        sleep 2
    done
    
    local end_time_packages=$(date +%s)
    local elapsed_time_packages=$((end_time_packages - start_time_total))
    echo -e "${GREEN}Elapsed time for Rocky Linux package installation: $((elapsed_time_packages / 60)) minutes and $((elapsed_time_packages % 60)) seconds.${ENDCOLOR}"
    
    return 0
}

rocky_handle_shutdown() {
    echo -e "${GREEN}Handling Rocky Linux VM shutdown...${ENDCOLOR}"
    
    # Wait for automatic shutdown or shutdown manually
    local shutdown_counter=0
    local max_shutdown_wait=300  # 5 minutes
    
    echo -e -n "${GREEN}Waiting for VM to shutdown automatically${ENDCOLOR}"
    while [[ $shutdown_counter -lt $max_shutdown_wait ]]; do
        vm_status=$(sudo qm status "$TEMPLATE_VM_ID" | grep "status:" | awk '{print $2}')
        if [[ "$vm_status" == "stopped" ]]; then
            echo -e "${GREEN}VM has shutdown automatically.${ENDCOLOR}"
            break
        fi
        echo -n "."
        sleep 5
        shutdown_counter=$((shutdown_counter + 5))
    done
    
    # If VM is still running after timeout, force shutdown
    vm_status=$(sudo qm status "$TEMPLATE_VM_ID" | grep "status:" | awk '{print $2}')
    if [[ "$vm_status" != "stopped" ]]; then
        echo -e "${YELLOW}VM did not shutdown automatically. Forcing shutdown...${ENDCOLOR}"
        sudo qm shutdown "$TEMPLATE_VM_ID" --timeout 60 || sudo qm stop "$TEMPLATE_VM_ID" --skiplock 1
    fi
    
    # Log cleanup for Rocky Linux
    echo -e "${GREEN}Performing Rocky Linux log cleanup...${ENDCOLOR}"
    # Additional Rocky-specific cleanup can be added here if needed
}

rocky_copy_generic_userdata() {
    echo -e "${GREEN}Copying generic Rocky userdata for future VM deployments...${ENDCOLOR}"
    
    local rocky_userdata="$SCRIPT_BASE_PATH/rocky/rocky-cloud-init-userdata.yaml"
    if [ -f "$rocky_userdata" ]; then
        local snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
        sudo mkdir -p "$snippets_path"
        sudo cp "$rocky_userdata" "${snippets_path}/rocky-userdata.yaml"
        sudo chmod 644 "${snippets_path}/rocky-userdata.yaml"
        echo -e "${GREEN}Generic rocky-userdata.yaml copied to ${PROXMOX_DISK_DATASTORE} snippets directory.${ENDCOLOR}"
    else
        echo -e "${YELLOW}Warning: rocky-cloud-init-userdata.yaml not found for copying.${ENDCOLOR}"
    fi
}

rocky_final_cleanup() {
    echo -e "${GREEN}Rocky Linux-specific cleanup tasks...${ENDCOLOR}"
    
    # Check firstboot logs for space issues
    firstboot_log_output=$(sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c "cat /var/log/template-firstboot-*" 2>/dev/null | jq -r '.["out-data"]' 2>/dev/null || echo "Failed to retrieve firstboot log")

    if echo "$firstboot_log_output" | grep -q "No space left"; then
        echo -e "${RED}'No space left' logs found in firstboot logs. Please increase TEMPLATE_DISK_SIZE and try again.${ENDCOLOR}"
        sudo qm stop "$TEMPLATE_VM_ID" --skiplock 1 || true
        exit 1
    elif echo "$firstboot_log_output" | grep -q "Failed to retrieve"; then
        echo -e "${GREEN}Could not retrieve firstboot log from VM (VM may have already shut down). Continuing with template creation...${ENDCOLOR}"
    else
        echo -e "${GREEN}No 'No space left' logs found in firstboot logs.${ENDCOLOR}"
    fi

    # Preserve Rocky cloud-init files for VM deployments
    echo -e "${GREEN}Preserving Rocky cloud-init files for VM deployments...${ENDCOLOR}"
    
    # Create a generic cloud-init file for all Rocky VMs
    local rocky_userdata="$SCRIPT_BASE_PATH/rocky/rocky-cloud-init-userdata.yaml"
    local snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo cp "$rocky_userdata" "${snippets_path}/rocky-userdata.yaml"
    sudo chmod 644 "${snippets_path}/rocky-userdata.yaml"
    
    # Important: ALSO KEEP the template-specific file (this is what Terraform/OpenTofu references)
    sudo cp "$rocky_userdata" "${snippets_path}/rocky-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
    sudo chmod 644 "${snippets_path}/rocky-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
    
    echo -e "${GREEN}Created permanent rocky cloud-init files in snippets for VM deployments${ENDCOLOR}"

    echo -e "${GREEN}Clean out cloudconfig configuration...${ENDCOLOR}"
    sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c "rm -f /etc/cloud/clean.d/README && cloud-init clean --logs" >/dev/null || true
    
    echo -e "${GREEN}Rocky Linux cleanup completed.${ENDCOLOR}"
}

# Main Rocky Linux template creation function
create_rocky_template() {
    echo -e "${BLUE}Starting Rocky Linux template creation...${ENDCOLOR}"
    
    # Step 1: Download image
    if ! download_image; then
        return 1
    fi
    
    # Step 2: Rocky pre-setup (skip virt-customize)
    rocky_pre_setup
    
    # Step 3: Clean up old template
    cleanup_old_template
    
    # Step 4: Create base VM
    if ! create_base_vm; then
        return 1
    fi
    
    # Step 5: Configure Rocky-specific VM settings
    if ! rocky_configure_vm; then
        return 1
    fi
    
    # Step 6: Expand disk
    if ! expand_disk; then
        return 1
    fi
    
    # Step 7: Start VM and wait for QEMU Guest Agent
    if ! start_vm_and_wait; then
        return 1
    fi
    
    # Step 8: Wait for Rocky configuration to complete
    rocky_wait_for_completion
    
    # Step 9: Handle Rocky shutdown
    rocky_handle_shutdown
    
    # Step 10: Rocky-specific cleanup
    rocky_final_cleanup
    
    # Step 11: Convert to template
    if ! convert_to_template; then
        return 1
    fi
    
    # Step 12: Final cleanup
    if ! final_cleanup; then
        return 1
    fi
    
    echo -e "${BLUE}Rocky Linux template creation completed successfully!${ENDCOLOR}"
    return 0
}

# Export the main function for use by the dispatcher
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly, execute the main function
    create_rocky_template
else
    # Script is being sourced, just make the function available
    echo -e "${GREEN}Rocky Linux template creation functions loaded.${ENDCOLOR}"
fi