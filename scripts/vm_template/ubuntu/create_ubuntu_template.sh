#!/bin/bash

# Ubuntu-specific VM template creation script
# This script handles all Ubuntu-specific logic for template creation

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
    # echo "Debug: Current directory: $(pwd)"
    # echo "Debug: Script directory: $SCRIPT_DIR"
    # echo "Debug: Looking for common_functions.sh at: $SCRIPT_DIR/../shared/common_functions.sh"
    
    # Check if common_functions.sh exists in expected location
    if [[ -f "$SCRIPT_DIR/../shared/common_functions.sh" ]]; then
        source "$SCRIPT_DIR/../shared/common_functions.sh"
        SCRIPT_BASE_PATH="$SCRIPT_DIR/.."
    else
        # Try alternative paths
        # echo "Debug: Trying alternative paths..."
        
        # Look for common_functions.sh in current directory tree
        for possible_path in "shared/common_functions.sh" "../shared/common_functions.sh" "../../shared/common_functions.sh"; do
            # echo "Debug: Checking $possible_path"
            if [[ -f "$possible_path" ]]; then
                source "$possible_path"
                SCRIPT_BASE_PATH="$(dirname "$possible_path")"
                break
            fi
        done
    fi
fi

# Ubuntu-specific functions
ubuntu_pre_setup() {
    echo -e "${GREEN}Ubuntu Pre-Setup: Skipping virt-customize due to compatibility issues...${ENDCOLOR}"
    echo -e "${GREEN}All configuration including QEMU Guest Agent installation will be handled during VM boot via cloud-init user-data...${ENDCOLOR}"
    # Create a marker file to indicate Ubuntu image was processed without virt-customize
    touch /tmp/ubuntu_skip_virt_customize
}

ubuntu_configure_vm() {
    echo -e "${GREEN}Configuring Ubuntu VM with custom cloud-init user-data...${ENDCOLOR}"
    
    # Check if the cloud-init user-data file exists
    local ubuntu_userdata="$SCRIPT_BASE_PATH/ubuntu/ubuntu-cloud-init-userdata.yaml"
    if [ ! -f "$ubuntu_userdata" ]; then
        echo -e "${RED}Error: ubuntu-cloud-init-userdata.yaml not found at $ubuntu_userdata!${ENDCOLOR}"
        return 1
    fi
    
    # Create temporary cloud-init user-data file for this specific VM
    local temp_userdata="/tmp/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml"
    
    # Replace variables in the cloud-init file
    echo -e "${GREEN}Processing cloud-init template variables...${ENDCOLOR}"
    # Set VM_HOSTNAME to template name + ID for better identification
    local vm_hostname="ubuntu-template-${TEMPLATE_VM_ID}"
    cat "$ubuntu_userdata" | \
        sed "s|\${VM_USERNAME}|$VM_USERNAME|g" | \
        sed "s|\${VM_SSH_KEY}|$VM_SSH_KEY|g" | \
        sed "s|\${VM_HOSTNAME}|$vm_hostname|g" > "$temp_userdata"
    
    # Copy the user-data file to Proxmox snippets directory first
    echo -e "${GREEN}Copying cloud-init user-data to Proxmox snippets directory...${ENDCOLOR}"
    local snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo mkdir -p "$snippets_path"
    sudo cp "$temp_userdata" "${snippets_path}/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml"
    sudo chmod 644 "${snippets_path}/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml"
    
    # Also create a generic ubuntu-userdata.yaml for future VM deployments
    sudo cp "$temp_userdata" "${snippets_path}/ubuntu-userdata.yaml"
    sudo chmod 644 "${snippets_path}/ubuntu-userdata.yaml"
    echo -e "${GREEN}Created generic ubuntu-userdata.yaml for VM deployments${ENDCOLOR}"
    
    # Copy machine-id script into VM
    copy_machine_id_script
    
    # Configure VM with Ubuntu-specific settings
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
      --cicustom "user=${PROXMOX_DISK_DATASTORE}:snippets/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml" \
      --agent "enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1" \
      --hotplug cpu,disk,network,usb \
      --tags "$EXTRA_TEMPLATE_TAGS ${KUBERNETES_MEDIUM_VERSION}"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to configure Ubuntu VM${ENDCOLOR}"
        return 1
    fi
    
    echo -e "${GREEN}Ubuntu VM configuration completed.${ENDCOLOR}"
    return 0
}

ubuntu_wait_for_completion() {
    echo -e "${GREEN}Waiting for Ubuntu cloud-init configuration to complete...${ENDCOLOR}"
    
    local max_timeout=300  # 30 minutes
    local timeout_counter=0
    local start_time_total=$(date +%s)  # Add missing variable

    echo -e -n "${GREEN}Waiting for Ubuntu configuration to complete${ENDCOLOR}"
    while [[ $timeout_counter -lt $max_timeout ]]; do
        # For Ubuntu, check cloud-init completion
        output=$(sudo qm guest exec "$TEMPLATE_VM_ID" cat /var/log/ubuntu-cloud-init-complete.log 2>/dev/null)
        success=$?
        if [[ $success -eq 0 ]]; then
            echo -e "\n${GREEN}Ubuntu cloud-init configuration complete. VM will shutdown automatically...${ENDCOLOR}"
            break
        fi
        
        # Also check if cloud-init finished (alternative check)
        cloud_init_status=$(sudo qm guest exec "$TEMPLATE_VM_ID" cloud-init status 2>/dev/null | jq -r '.stdout' 2>/dev/null)
        if [[ "$cloud_init_status" == *"done"* ]]; then
            echo -e "\n${GREEN}Cloud-init reported as done. Proceeding...${ENDCOLOR}"
            break
        fi
        
        # Check for timeout
        timeout_counter=$((timeout_counter + 2))
        if [[ $timeout_counter -gt $max_timeout ]]; then
            echo -e "\n${RED}Timeout waiting for Ubuntu configuration to complete after $max_timeout seconds. Continuing anyway...${ENDCOLOR}"
            break
        fi
        
        echo -n "."
        sleep 2
    done
    
    local end_time_packages=$(date +%s)
    local elapsed_time_packages=$((end_time_packages - start_time_total))
    echo -e "${GREEN}Elapsed time for Ubuntu configuration: $((elapsed_time_packages / 60)) minutes and $((elapsed_time_packages % 60)) seconds.${ENDCOLOR}"
    
    return 0
}

ubuntu_handle_shutdown() {
    echo -e "${GREEN}Ubuntu VM should shutdown automatically. Waiting for shutdown...${ENDCOLOR}"
    
    # Wait for VM to shutdown automatically (up to 5 minutes)
    local shutdown_timeout=300
    local shutdown_counter=0
    while [[ $shutdown_counter -lt $shutdown_timeout ]]; do
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
    
    # Skip log cleanup since cloud-init handles this
    echo -e "${GREEN}Skipping log cleanup (handled by cloud-init)...${ENDCOLOR}"
}

ubuntu_final_cleanup() {
    echo -e "${GREEN}Ubuntu-specific cleanup tasks...${ENDCOLOR}"
    
    # Clean up machine-id for Ubuntu template
    cleanup_machine_id "ubuntu"
    
    # Clean up cloud-init reset
    sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c "rm -f /etc/cloud/clean.d/README && cloud-init clean --logs" >/dev/null || true
    
    # Preserve Ubuntu cloud-init files for VM deployments
    echo -e "${GREEN}Preserving Ubuntu cloud-init files for VM deployments...${ENDCOLOR}"
    
    # Create a generic cloud-init file for all Ubuntu VMs
    local ubuntu_userdata="$SCRIPT_BASE_PATH/ubuntu/ubuntu-cloud-init-userdata.yaml"
    local snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo cp "$ubuntu_userdata" "${snippets_path}/ubuntu-userdata.yaml"
    sudo chmod 644 "${snippets_path}/ubuntu-userdata.yaml"
    
    # Important: ALSO KEEP the template-specific file (this is what Terraform/OpenTofu references)
    sudo cp "$ubuntu_userdata" "${snippets_path}/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
    sudo chmod 644 "${snippets_path}/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
    
    echo -e "${GREEN}Created permanent ubuntu cloud-init files in snippets for VM deployments${ENDCOLOR}"
    
    # Clean up only the temp file
    rm -f "/tmp/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
}

# Main Ubuntu template creation function
create_ubuntu_template() {
    echo -e "${BLUE}Starting Ubuntu template creation...${ENDCOLOR}"
    
    # Step 1: Download image
    if ! download_image; then
        return 1
    fi
    
    # Step 2: Ubuntu pre-setup (skip virt-customize)
    ubuntu_pre_setup
    
    # Step 3: Clean up old template
    cleanup_old_template
    
    # Step 4: Create base VM
    if ! create_base_vm; then
        return 1
    fi
    
    # Step 5: Configure Ubuntu-specific VM settings
    if ! ubuntu_configure_vm; then
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
    
    # Step 8: Wait for Ubuntu configuration to complete
    ubuntu_wait_for_completion
    
    # Step 9: Handle Ubuntu shutdown
    ubuntu_handle_shutdown
    
    # Step 10: Ubuntu-specific cleanup
    ubuntu_final_cleanup
    
    # Step 11: Convert to template
    if ! convert_to_template; then
        return 1
    fi
    
    # Step 12: Final cleanup
    final_cleanup
    
    echo -e "${GREEN}Ubuntu template creation completed successfully!${ENDCOLOR}"
    return 0
}

# Execute the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    create_ubuntu_template
fi