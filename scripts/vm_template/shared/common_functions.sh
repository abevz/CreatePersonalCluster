#!/bin/bash

# Shared functions for VM template creation across all operating systems
# These functions are used by all OS-specific template creation scripts

# Color definitions
export GREEN='\033[32m'
export RED='\033[31m'
export YELLOW='\033[33m'
export BLUE='\033[34m'
export ENDCOLOR='\033[0m'

# Ensure required tools are installed
install_required_tools() {
    echo -e "${GREEN}Ensuring libguestfs-tools and jq are installed...${ENDCOLOR}"
    
    if command -v jq >/dev/null 2>&1 && command -v guestfish >/dev/null 2>&1; then
        echo -e "${GREEN}jq and libguestfs-tools are already installed.${ENDCOLOR}"
        return 0
    fi
    
    # Try to install using available package manager
    if command -v apt >/dev/null 2>&1; then
        sudo apt update -qq && sudo apt install -qq jq libguestfs-tools -y
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y jq libguestfs-tools
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq libguestfs-tools
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y jq libguestfs
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm jq libguestfs
    else
        echo -e "${RED}No supported package manager found. Please install jq and libguestfs-tools manually.${ENDCOLOR}"
        return 1
    fi
    
    # Verify installation
    if command -v jq >/dev/null 2>&1 && command -v guestfish >/dev/null 2>&1; then
        echo -e "${GREEN}jq and libguestfs-tools are installed.${ENDCOLOR}"
        return 0
    else
        echo -e "${RED}Failed to install jq or libguestfs-tools. Exiting.${ENDCOLOR}"
        return 1
    fi
}

# Load environment and secrets
load_environment() {
    echo -e "${GREEN}Loading the environment variables from cpc.env...${ENDCOLOR}"
    
    # Preserve REPO_PATH if it was set via SSH export (for Proxmox host execution)
    local saved_repo_path="$REPO_PATH"
    
    if [[ -f ./cpc.env ]]; then
        set -a # automatically export all variables
        source ./cpc.env
        set +a # stop automatically exporting
        echo -e "${GREEN}cpc.env loaded.${ENDCOLOR}"
        
        # Restore REPO_PATH if it was previously set (prioritize SSH export over cpc.env)
        if [[ -n "$saved_repo_path" ]]; then
            export REPO_PATH="$saved_repo_path"
            echo -e "${GREEN}REPO_PATH restored to SSH exported value: $REPO_PATH${ENDCOLOR}"
        fi
    else
        echo -e "${RED}cpc.env not found in the current directory. Exiting.${ENDCOLOR}"
        return 1
    fi

    echo -e "${GREEN}Loading secrets from environment variables...${ENDCOLOR}"
    
    # Verify that all required secrets were provided via environment variables
    if [[ -z "$PROXMOX_HOST" || -z "$PROXMOX_USERNAME" || -z "$PROXMOX_PASSWORD" || -z "$VM_USERNAME" || -z "$VM_PASSWORD" || -z "$VM_SSH_KEY" ]]; then
        echo -e "${RED}Error: One or more required secrets are missing from environment variables${ENDCOLOR}"
        echo -e "${RED}Required secrets: PROXMOX_HOST, PROXMOX_USERNAME, PROXMOX_PASSWORD, VM_USERNAME, VM_PASSWORD, VM_SSH_KEY${ENDCOLOR}"
        echo -e "${RED}These should be provided by the cpc script that calls this template creation.${ENDCOLOR}"
        return 1
    fi

    # Use the SSH key file that was copied by template.sh
    TEMP_SSH_KEY_FILE="./vm_ssh_key.pub"
    export SSH_KEY_FILE="$TEMP_SSH_KEY_FILE"

    echo -e "${GREEN}Successfully loaded secrets (PROXMOX_HOST: $PROXMOX_HOST, VM_USERNAME: $VM_USERNAME)${ENDCOLOR}"
    return 0
}

# Validate required variables
validate_environment() {
    local required_vars=(
        "PROXMOX_ISO_PATH" "IMAGE_NAME" "IMAGE_LINK" "TIMEZONE"
        "TEMPLATE_VM_ID" "TEMPLATE_VM_NAME" "TEMPLATE_VM_CPU" "TEMPLATE_VM_MEM"
        "TEMPLATE_VM_BRIDGE" "TEMPLATE_VM_CPU_TYPE" "PROXMOX_DISK_DATASTORE"
        "TEMPLATE_VM_GATEWAY" "TEMPLATE_VM_IP" "TWO_DNS_SERVERS"
        "TEMPLATE_VM_SEARCH_DOMAIN" "TEMPLATE_DISK_SIZE" "KUBERNETES_MEDIUM_VERSION"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo -e "${RED}Error: $var is not set in cpc.env${ENDCOLOR}"
            return 1
        fi
    done
    
    echo -e "${GREEN}All required environment variables are set.${ENDCOLOR}"
    return 0
}

# Add GPU tags if NVIDIA drivers are configured
setup_gpu_tags() {
    if [[ -n "$NVIDIA_DRIVER_VERSION" && "$NVIDIA_DRIVER_VERSION" != "none" ]]; then
        EXTRA_TEMPLATE_TAGS="${EXTRA_TEMPLATE_TAGS:+$EXTRA_TEMPLATE_TAGS }nvidia"
        echo -e "${GREEN}Added NVIDIA GPU tag to template.${ENDCOLOR}"
    fi
}

# Download VM image with smart caching
download_image() {
    local image_path="$PROXMOX_ISO_PATH/$IMAGE_NAME"
    local temp_headers="/tmp/image_headers_${TEMPLATE_VM_ID}.txt"
    local force_download="${FORCE_IMAGE_DOWNLOAD:-false}"
    
    echo -e "${GREEN}Checking if image download is needed...${ENDCOLOR}"
    
    # If forced download is enabled, skip all checks
    if [[ "$force_download" == "true" ]]; then
        echo -e "${YELLOW}Force download enabled. Skipping cache checks.${ENDCOLOR}"
    elif [[ -f "$image_path" ]]; then
        echo -e "${YELLOW}Image already exists: $image_path${ENDCOLOR}"
        
        # Get remote file info (Last-Modified and Content-Length)
        if sudo wget --no-check-certificate --spider --server-response "$IMAGE_LINK" 2>&1 | grep -E "(Last-Modified|Content-Length)" > "$temp_headers"; then
            local remote_size=$(grep "Content-Length" "$temp_headers" | tail -1 | awk '{print $2}' | tr -d '\r\n ')
            local remote_date=$(grep "Last-Modified" "$temp_headers" | tail -1 | cut -d' ' -f2- | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # Get local file info
            local local_size=$(stat -c%s "$image_path" 2>/dev/null || echo "0")
            local local_date=$(date -r "$image_path" -u "+%a, %d %b %Y %H:%M:%S GMT" 2>/dev/null || echo "")
            
            echo -e "${BLUE}Remote: ${remote_size} bytes, Last-Modified: ${remote_date}${ENDCOLOR}"
            echo -e "${BLUE}Local:  ${local_size} bytes, ${local_date}${ENDCOLOR}"
            
            # Compare sizes first (more reliable)
            if [[ "$remote_size" != "$local_size" ]]; then
                echo -e "${YELLOW}File size changed (remote: ${remote_size}, local: ${local_size}). Download needed.${ENDCOLOR}"
                force_download=true
            elif [[ -z "$remote_size" || -z "$local_size" || "$remote_size" == "0" || "$local_size" == "0" ]]; then
                echo -e "${YELLOW}Could not determine file sizes. Will re-download to be safe.${ENDCOLOR}"
                force_download=true
            else
                # Convert dates to timestamps for reliable comparison
                local remote_timestamp=$(date -d "$remote_date" +%s 2>/dev/null || echo "0")
                local local_timestamp=$(stat -c%Y "$image_path" 2>/dev/null || echo "0")
                
                # Commenting out debug message showing timestamps
                # echo -e "${BLUE}Debug: Remote timestamp: ${remote_timestamp}, Local timestamp: ${local_timestamp}${ENDCOLOR}"
                
                if [[ "$remote_timestamp" != "0" && "$local_timestamp" != "0" ]]; then
                    local time_diff=$((remote_timestamp - local_timestamp))
                    # Allow 1 second difference for rounding errors
                    if [[ $time_diff -gt 1 || $time_diff -lt -1 ]]; then
                        echo -e "${YELLOW}File modification time changed. Download needed.${ENDCOLOR}"
                        force_download=true
                    else
                        echo -e "${GREEN}Image is up to date (size and timestamp match). Skipping download.${ENDCOLOR}"
                        rm -f "$temp_headers"
                        return 0
                    fi
                else
                    echo -e "${YELLOW}Could not parse timestamps. Using size comparison only.${ENDCOLOR}"
                    echo -e "${GREEN}Image size matches. Assuming up to date. Skipping download.${ENDCOLOR}"
                    rm -f "$temp_headers"
                    return 0
                fi
            fi
        else
            echo -e "${YELLOW}Could not check remote image info. Will re-download to be safe.${ENDCOLOR}"
            force_download=true
        fi
    else
        echo -e "${YELLOW}Image not found locally. Download needed.${ENDCOLOR}"
        force_download=true
    fi
    
    # Clean up temp headers file
    rm -f "$temp_headers"
    
    # Download image if needed
    if [[ "$force_download" == "true" ]]; then
        echo -e "${GREEN}Removing old image if it exists...${ENDCOLOR}"
        sudo rm -f "${image_path}"* 2>/dev/null || true

        echo -e "${GREEN}Downloading the image...${ENDCOLOR}"
        if ! sudo wget --no-check-certificate -qO "$image_path" "$IMAGE_LINK"; then
            echo -e "${RED}Failed to download image from $IMAGE_LINK${ENDCOLOR}"
            return 1
        fi
        echo -e "${GREEN}Image downloaded successfully.${ENDCOLOR}"
    fi
    
    return 0
}

# Clean up old VM template
cleanup_old_template() {
    echo -e "${GREEN}Deleting the old template vm if it exists...${ENDCOLOR}"
    sudo qm stop "$TEMPLATE_VM_ID" --skiplock 1 || true
    sudo qm destroy "$TEMPLATE_VM_ID" --purge 1 --skiplock 1 --destroy-unreferenced-disks 1 || true
}

# Create base VM
create_base_vm() {
    # Check if TEMPLATE_VLAN_TAG is valid
    if [[ -z "$TEMPLATE_VLAN_TAG" || "$TEMPLATE_VLAN_TAG" == "0" || "$TEMPLATE_VLAN_TAG" =~ ^(none|null|None)$ ]]; then
        TAG_ARG=""  # No VLAN tag applied
    else
        TAG_ARG="tag=$TEMPLATE_VLAN_TAG"  # Apply VLAN tag
    fi

    echo -e "${GREEN}Creating the VM...${ENDCOLOR}"
    sudo qm create "$TEMPLATE_VM_ID" \
      --name "$TEMPLATE_VM_NAME" \
      --machine "type=q35" \
      --cores "$TEMPLATE_VM_CPU" \
      --sockets 1 \
      --memory "$TEMPLATE_VM_MEM" \
      --net0 "virtio,bridge=$TEMPLATE_VM_BRIDGE,$TAG_ARG" \
      --agent "enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1" \
      --onboot 1 \
      --balloon 0 \
      --autostart 1 \
      --cpu cputype="$TEMPLATE_VM_CPU_TYPE" \
      --numa 1

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to create base VM${ENDCOLOR}"
        return 1
    fi
    
    echo -e "${GREEN}Base VM created successfully.${ENDCOLOR}"
    return 0
}

# Expand disk size
expand_disk() {
    echo -e "${GREEN}Expanding disk to $TEMPLATE_DISK_SIZE...${ENDCOLOR}"
    if ! sudo qm resize "$TEMPLATE_VM_ID" virtio0 "$TEMPLATE_DISK_SIZE"; then
        echo -e "${RED}Failed to resize disk to $TEMPLATE_DISK_SIZE${ENDCOLOR}"
        return 1
    fi
    echo -e "${GREEN}Disk expanded successfully.${ENDCOLOR}"
    return 0
}

# Start VM and wait for QEMU Guest Agent
start_vm_and_wait() {
    echo -e "${GREEN}Starting the VM, allowing firstboot script to install packages...${ENDCOLOR}"
    sudo qm start "$TEMPLATE_VM_ID"

    echo -e "${GREEN}Sleeping 60s to allow VM and the QEMU Guest Agent to start...${ENDCOLOR}"
    sleep 60s

    # Wait for QEMU Guest Agent to become responsive
    local max_timeout=300  # 5 minutes - reduced from 6 to be more practical
    local timeout_counter=0
    local check_interval=10  # Check every 10 seconds instead of 5

    echo -e "${GREEN}Waiting for QEMU Guest Agent to become responsive...${ENDCOLOR}"
    while [[ $timeout_counter -lt $max_timeout ]]; do
        # Try multiple methods to detect the agent
        local agent_detected=false
        local detection_method=""
        
        # Method 1: Try guest exec with simple command (most reliable)
        if sudo qm guest exec "$TEMPLATE_VM_ID" -- echo "agent-test" >/dev/null 2>&1; then
            agent_detected=true
            detection_method="exec"
        # Method 2: Try guest cmd ping (alternative format)
        elif sudo qm guest cmd "$TEMPLATE_VM_ID" ping >/dev/null 2>&1; then
            agent_detected=true
            detection_method="cmd-ping"
        fi
        
        if [[ "$agent_detected" == "true" ]]; then
            echo -e "\n${GREEN}QEMU Guest Agent is responsive (detected via $detection_method after $timeout_counter seconds).${ENDCOLOR}"
            return 0
        fi
        
        # Progress indication and status check
        if [[ $((timeout_counter % 30)) -eq 0 ]]; then
            vm_status=$(sudo qm status "$TEMPLATE_VM_ID" 2>/dev/null | grep "status:" | awk '{print $2}')
            echo -e "\n${BLUE}Still waiting... VM Status: $vm_status (${timeout_counter}s elapsed)${ENDCOLOR}"
            
            # After 3 minutes, if VM is stable and running, proceed anyway
            if [[ $timeout_counter -ge 180 && "$vm_status" == "running" ]]; then
                echo -e "${YELLOW}VM has been stable and running for 3+ minutes. QEMU Guest Agent might be working but not responding to our checks.${ENDCOLOR}"
                echo -e "${YELLOW}Proceeding with template creation...${ENDCOLOR}"
                return 0
            fi
        else
            echo -n "."
        fi
        
        sleep $check_interval
        timeout_counter=$((timeout_counter + check_interval))
    done
    
    # Final check - if VM is running, let's proceed anyway
    vm_status=$(sudo qm status "$TEMPLATE_VM_ID" 2>/dev/null | grep "status:" | awk '{print $2}')
    if [[ "$vm_status" == "running" ]]; then
        echo -e "\n${YELLOW}QEMU Guest Agent detection timed out but VM is running. Proceeding with template creation...${ENDCOLOR}"
        echo -e "${YELLOW}You can manually verify the agent is working via SSH if needed.${ENDCOLOR}"
        return 0
    fi
    
    echo -e "\n${RED}Timeout waiting for QEMU Guest Agent after $max_timeout seconds and VM is not running properly.${ENDCOLOR}"
    return 1
}

# Copy machine-id script to VM
copy_machine_id_script() {
    if [ -f "./ensure-unique-machine-id.sh" ]; then
        echo -e "${GREEN}Copying machine-id script to VM...${ENDCOLOR}"
        
        # First try qm guest file-upload (Proxmox 7.0+)
        if sudo qm guest file-upload "$TEMPLATE_VM_ID" ./ensure-unique-machine-id.sh /root/ensure-unique-machine-id.sh 2>/dev/null; then
            echo -e "${GREEN}Used guest file-upload feature${ENDCOLOR}"
        else
            # Fallback to exec method
            echo -e "${YELLOW}Falling back to exec method for file upload${ENDCOLOR}"
            
            # Create directory
            sudo qm guest exec "$TEMPLATE_VM_ID" -- mkdir -p /root/ || true
            
            # Create base64 encoded content and write to file inside VM
            base64_content=$(base64 -w0 ./ensure-unique-machine-id.sh)
            sudo qm guest exec "$TEMPLATE_VM_ID" -- bash -c "echo '$base64_content' | base64 -d > /root/ensure-unique-machine-id.sh" || true
        fi
        
        # Make the script executable
        sudo qm guest exec "$TEMPLATE_VM_ID" -- chmod +x /root/ensure-unique-machine-id.sh || true
        echo -e "${GREEN}Machine-id script copied successfully${ENDCOLOR}"
    fi
}

# Clean up machine-id for template
cleanup_machine_id() {
    local os_type="$1"
    
    if [[ "$os_type" == "ubuntu" ]]; then
        echo -e "${GREEN}Cleaning machine-id for Ubuntu template...${ENDCOLOR}"
        if sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c "truncate -s 0 /etc/machine-id && rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1; then
            echo -e "${GREEN}Successfully cleared machine-id files in the template${ENDCOLOR}"
        else
            echo -e "${YELLOW}Could not clear machine-id directly, VM may already be stopped${ENDCOLOR}"
        fi
        sudo qm set "$TEMPLATE_VM_ID" -description "Machine-ID will be regenerated on clone to ensure unique DHCP IPs"
    fi
}

# Convert VM to template
convert_to_template() {
    echo -e "${GREEN}Converting the shut-down VM into a template...${ENDCOLOR}"
    sudo qm template "$TEMPLATE_VM_ID"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Template conversion successful.${ENDCOLOR}"
        return 0
    else
        echo -e "${RED}Failed to convert VM to template.${ENDCOLOR}"
        return 1
    fi
}

# Final cleanup
final_cleanup() {
    echo -e "${GREEN}Deleting the downloaded image...${ENDCOLOR}"
    sudo rm -f "${PROXMOX_ISO_PATH:?PROXMOX_ISO_PATH is not set}/${IMAGE_NAME:?IMAGE_NAME is not set}"*
}

# Print elapsed time
print_elapsed_time() {
    local start_time="$1"
    local end_time=$(date +%s)
    local elapsed_time=$((end_time - start_time))
    echo -e "${GREEN}Total elapsed time: $((elapsed_time / 60)) minutes and $((elapsed_time % 60)) seconds.${ENDCOLOR}"
}
