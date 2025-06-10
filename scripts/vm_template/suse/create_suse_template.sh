#!/bin/bash

# SUSE-specific VM template creation script
# This script handles all SUSE-specific logic for template creation

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

# SUSE-specific functions
suse_pre_setup() {
    echo -e "${GREEN}SUSE Pre-Setup: Skipping virt-customize due to libguestfs compatibility issues...${ENDCOLOR}"
    echo -e "${GREEN}SUSE configuration will be handled during VM boot via cloud-init...${ENDCOLOR}"
    # Create a marker file to indicate SUSE image was processed differently
    touch /tmp/suse_skip_virt_customize
}

suse_prepare_cloud_init() {
    echo -e "${GREEN}Preparing SUSE cloud-init user-data...${ENDCOLOR}"
    
    # Debug: Show SSH key information
    echo -e "${BLUE}Debug: SSH_KEY_FILE=$SSH_KEY_FILE${ENDCOLOR}"
    echo -e "${BLUE}Debug: VM_SSH_KEY (first 50 chars): ${VM_SSH_KEY:0:50}...${ENDCOLOR}"
    if [[ -f "$SSH_KEY_FILE" ]]; then
        echo -e "${GREEN}SSH key file exists and is readable${ENDCOLOR}"
    else
        echo -e "${RED}ERROR: SSH key file $SSH_KEY_FILE does not exist!${ENDCOLOR}"
        return 1
    fi
    
    local suse_userdata="$SCRIPT_BASE_PATH/suse/suse-cloud-init-userdata.yaml"
    if [ ! -f "$suse_userdata" ]; then
        echo -e "${RED}Error: suse-cloud-init-userdata.yaml not found at $suse_userdata!${ENDCOLOR}"
        return 1
    fi
    
    # Template values for hostname replacement
    local temp_userdata="/tmp/suse-userdata-${TEMPLATE_VM_ID}.yaml"
    local vm_hostname="${VM_NAME_PREFIX}template"
    
    # Process template file with variable substitution
    cat "$suse_userdata" | \
        sed "s|\${VM_USERNAME}|$VM_USERNAME|g" | \
        sed "s|\${VM_SSH_KEY}|$VM_SSH_KEY|g" | \
        sed "s|\${VM_HOSTNAME}|$vm_hostname|g" > "$temp_userdata"
    
    # Copy to Proxmox snippets directory (using configurable storage variables)
    local snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo mkdir -p "$snippets_path"
    sudo cp "$temp_userdata" "${snippets_path}/suse-userdata-${TEMPLATE_VM_ID}.yaml"
    sudo chmod 644 "${snippets_path}/suse-userdata-${TEMPLATE_VM_ID}.yaml"
    
    # Also create a generic suse-userdata.yaml for future VM deployments
    sudo cp "$temp_userdata" "${snippets_path}/suse-userdata.yaml"
    sudo chmod 644 "${snippets_path}/suse-userdata.yaml"
    echo -e "${GREEN}Created generic suse-userdata.yaml for VM deployments${ENDCOLOR}"
    
    # Clean up temporary file
    rm -f "$temp_userdata"
    
    echo -e "${GREEN}SUSE cloud-init preparation completed.${ENDCOLOR}"
    return 0
}

suse_configure_vm() {
    echo -e "${GREEN}Configuring SUSE VM with cloud-init settings...${ENDCOLOR}"
    
    # Prepare cloud-init configuration first
    if ! suse_prepare_cloud_init; then
        echo -e "${RED}Failed to prepare SUSE cloud-init configuration${ENDCOLOR}"
        return 1
    fi
    
    # Configure VM with SUSE-specific settings
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
      --cicustom "user=${PROXMOX_DISK_DATASTORE}:snippets/suse-userdata-${TEMPLATE_VM_ID}.yaml" \
      --agent "enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1" \
      --hotplug cpu,disk,network,usb \
      --tags "$EXTRA_TEMPLATE_TAGS ${KUBERNETES_MEDIUM_VERSION}"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to configure SUSE VM${ENDCOLOR}"
        return 1
    fi
    
    # Debug: Show VM configuration
    echo -e "${BLUE}Debug: VM $TEMPLATE_VM_ID configuration:${ENDCOLOR}"
    sudo qm config "$TEMPLATE_VM_ID" | grep -E "(sshkeys|cicustom|ciuser)"
    
    echo -e "${GREEN}SUSE VM configuration completed.${ENDCOLOR}"
    return 0
}

suse_wait_for_completion() {
    echo -e "${GREEN}Waiting for SUSE cloud-init to complete...${ENDCOLOR}"
    
    local max_timeout=1800  # 30 minutes
    local timeout_counter=0
    
    echo -e -n "${GREEN}Waiting for cloud-init configuration to complete${ENDCOLOR}"
    while [[ $timeout_counter -lt $max_timeout ]]; do
        # Check for the completion marker file created by cloud-init
        output=$(sudo qm guest exec "$TEMPLATE_VM_ID" -- test -f /var/log/suse-cloud-init-complete.log 2>/dev/null)
        success=$?
        if [[ $success -eq 0 ]]; then
            echo -e "\n${GREEN}SUSE cloud-init configuration complete.${ENDCOLOR}"
            break
        fi
        
        # Check for timeout
        timeout_counter=$((timeout_counter + 2))
        if [[ $timeout_counter -gt $max_timeout ]]; then
            echo -e "\n${RED}Timeout waiting for SUSE cloud-init to complete after $max_timeout seconds. Continuing anyway...${ENDCOLOR}"
            break
        fi
        
        echo -n "."
        sleep 2
    done
    
    local end_time_packages=$(date +%s)
    local elapsed_time_packages=$((end_time_packages - start_time_total))
    echo -e "${GREEN}Elapsed time for SUSE package installation: $((elapsed_time_packages / 60)) minutes and $((elapsed_time_packages % 60)) seconds.${ENDCOLOR}"
    
    return 0
}

suse_handle_shutdown() {
    echo -e "${GREEN}Handling SUSE VM shutdown...${ENDCOLOR}"
    
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
    
    # Log cleanup for SUSE
    echo -e "${GREEN}Performing SUSE log cleanup...${ENDCOLOR}"
    # Additional SUSE-specific cleanup can be added here if needed
}

suse_final_cleanup() {
    echo -e "${GREEN}SUSE-specific cleanup tasks...${ENDCOLOR}"
    
    # Copy ensure-unique-machine-id.sh script to the VM
    local script_path="$SCRIPT_BASE_PATH/ensure-unique-machine-id.sh"
    if [[ -f "$script_path" ]]; then
        echo -e "${GREEN}Copying ensure-unique-machine-id.sh to VM...${ENDCOLOR}"
        sudo qm guest exec "$TEMPLATE_VM_ID" -- mkdir -p /root
        sudo qm guest exec "$TEMPLATE_VM_ID" -- rm -f /root/ensure-unique-machine-id.sh
        
        # Copy script content to VM
        script_content=$(cat "$script_path")
        sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c "cat > /root/ensure-unique-machine-id.sh << 'SCRIPT_EOF'
$script_content
SCRIPT_EOF"
        
        # Make script executable
        sudo qm guest exec "$TEMPLATE_VM_ID" -- chmod +x /root/ensure-unique-machine-id.sh
        echo -e "${GREEN}ensure-unique-machine-id.sh copied successfully.${ENDCOLOR}"
    else
        echo -e "${YELLOW}Warning: ensure-unique-machine-id.sh not found at $script_path${ENDCOLOR}"
    fi
    
    # Check firstboot logs for space issues (with enhanced error handling)
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

    echo -e "${GREEN}Clean out cloudconfig configuration...${ENDCOLOR}"
    sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c "rm -f /etc/cloud/clean.d/README && cloud-init clean --logs" >/dev/null || true
    
    echo -e "${GREEN}SUSE cleanup completed.${ENDCOLOR}"
}

suse_copy_generic_userdata() {
    echo -e "${GREEN}Copying generic SUSE userdata for future VM deployments...${ENDCOLOR}"
    
    local suse_userdata="$SCRIPT_BASE_PATH/suse/suse-cloud-init-userdata.yaml"
    if [ -f "$suse_userdata" ]; then
        local snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
        sudo mkdir -p "$snippets_path"
        sudo cp "$suse_userdata" "${snippets_path}/suse-userdata.yaml"
        sudo chmod 644 "${snippets_path}/suse-userdata.yaml"
        echo -e "${GREEN}Generic suse-userdata.yaml copied to ${PROXMOX_DISK_DATASTORE} snippets directory.${ENDCOLOR}"
    else
        echo -e "${YELLOW}Warning: suse-cloud-init-userdata.yaml not found for copying.${ENDCOLOR}"
    fi
}

# Main SUSE template creation function
create_suse_template() {
    echo -e "${BLUE}Starting SUSE template creation...${ENDCOLOR}"
    
    # Step 1: Download image
    if ! download_image; then
        return 1
    fi
    
    # Step 2: SUSE pre-setup (skip virt-customize)
    suse_pre_setup
    
    # Step 3: Clean up old template
    cleanup_old_template
    
    # Step 4: Create base VM
    if ! create_base_vm; then
        return 1
    fi
    
    # Step 5: Configure SUSE-specific VM settings
    if ! suse_configure_vm; then
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
    
    # Step 8: Wait for SUSE configuration to complete
    suse_wait_for_completion
    
    # Step 9: Handle SUSE shutdown
    suse_handle_shutdown
    
    # Step 10: SUSE-specific cleanup
    suse_final_cleanup
     # Step 11: Convert to template
    if ! convert_to_template; then
        return 1
    fi

    # Step 12: Copy generic SUSE userdata for future VM deployments
    suse_copy_generic_userdata

    # Step 13: Final cleanup
    if ! final_cleanup; then
        return 1
    fi
    
    echo -e "${BLUE}SUSE template creation completed successfully!${ENDCOLOR}"
    return 0
}

# Export the main function for use by the dispatcher
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly, execute the main function
    create_suse_template
else
    # Script is being sourced, just make the function available
    echo -e "${GREEN}SUSE template creation functions loaded.${ENDCOLOR}"
fi