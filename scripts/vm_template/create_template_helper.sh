#!/bin/bash

# Record the start time
start_time_total=$(date +%s)

GREEN='\\033[32m'
RED='\\033[31m'
ENDCOLOR='\\033[0m'

echo -e "${GREEN}Ensuring libguestfs-tools and jq are installed...${ENDCOLOR}"

# Check if required tools are already available
if command -v jq >/dev/null 2>&1 && command -v guestfish >/dev/null 2>&1; then
    echo -e "${GREEN}jq and libguestfs-tools are already installed.${ENDCOLOR}"
else
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
        exit 1
    fi
    
    # Verify installation
    if command -v jq >/dev/null 2>&1 && command -v guestfish >/dev/null 2>&1; then
        echo -e "${GREEN}jq and libguestfs-tools are installed.${ENDCOLOR}"
    else
        echo -e "${RED}Failed to install jq or libguestfs-tools. Exiting.${ENDCOLOR}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Loading the environment variables from cpc.env...${ENDCOLOR}"
if [[ -f ./cpc.env ]]; then
    set -a # automatically export all variables
    source ./cpc.env
    set +a # stop automatically exporting
    echo -e "${GREEN}cpc.env loaded.${ENDCOLOR}"
else
    echo -e "${RED}cpc.env not found in the current directory. Exiting.${ENDCOLOR}"
    exit 1
fi

echo ""
echo -e "${GREEN}Loading secrets from environment variables...${ENDCOLOR}"

# Verify that all required secrets were provided via environment variables
if [[ -z "$PROXMOX_HOST" || -z "$PROXMOX_USERNAME" || -z "$PROXMOX_PASSWORD" || -z "$VM_USERNAME" || -z "$VM_PASSWORD" || -z "$VM_SSH_KEY" ]]; then
    echo -e "${RED}Error: One or more required secrets are missing from environment variables${ENDCOLOR}"
    echo -e "${RED}Required secrets: PROXMOX_HOST, PROXMOX_USERNAME, PROXMOX_PASSWORD, VM_USERNAME, VM_PASSWORD, VM_SSH_KEY${ENDCOLOR}"
    echo -e "${RED}These should be provided by the cpc script that calls this template creation.${ENDCOLOR}"
    exit 1
fi

# Use the SSH key file that was copied by template.sh
TEMP_SSH_KEY_FILE="./vm_ssh_key.pub"
export SSH_KEY_FILE="$TEMP_SSH_KEY_FILE"

echo -e "${GREEN}Successfully loaded secrets (PROXMOX_HOST: $PROXMOX_HOST, VM_USERNAME: $VM_USERNAME)${ENDCOLOR}"

# Essential variable checks (variables from cpc.env - SOPS secrets already loaded above)
: "${PROXMOX_ISO_PATH:?PROXMOX_ISO_PATH is not set in cpc.env}"
: "${PROXMOX_STORAGE_BASE_PATH:?PROXMOX_STORAGE_BASE_PATH is not set in cpc.env}"
: "${IMAGE_NAME:?IMAGE_NAME is not set in cpc.env}"
: "${IMAGE_LINK:?IMAGE_LINK is not set in cpc.env}"
: "${TIMEZONE:?TIMEZONE is not set in cpc.env}"
: "${TEMPLATE_VM_ID:?TEMPLATE_VM_ID is not set in cpc.env}"
: "${TEMPLATE_VM_NAME:?TEMPLATE_VM_NAME is not set in cpc.env}"
: "${TEMPLATE_VM_CPU:?TEMPLATE_VM_CPU is not set in cpc.env}"
: "${TEMPLATE_VM_MEM:?TEMPLATE_VM_MEM is not set in cpc.env}"
: "${TEMPLATE_VM_BRIDGE:?TEMPLATE_VM_BRIDGE is not set in cpc.env}"
: "${TEMPLATE_VM_CPU_TYPE:?TEMPLATE_VM_CPU_TYPE is not set in cpc.env}"
: "${PROXMOX_DISK_DATASTORE:?PROXMOX_DISK_DATASTORE is not set in cpc.env}"
: "${TEMPLATE_VM_GATEWAY:?TEMPLATE_VM_GATEWAY is not set in cpc.env}"
: "${TEMPLATE_VM_IP:?TEMPLATE_VM_IP is not set in cpc.env}"
: "${TWO_DNS_SERVERS:?TWO_DNS_SERVERS is not set in cpc.env}"
: "${TEMPLATE_VM_SEARCH_DOMAIN:?TEMPLATE_VM_SEARCH_DOMAIN is not set in cpc.env}"
: "${TEMPLATE_DISK_SIZE:?TEMPLATE_DISK_SIZE is not set in cpc.env}"
: "${KUBERNETES_MEDIUM_VERSION:?KUBERNETES_MEDIUM_VERSION is not set in cpc.env}"

# Note: VM_USERNAME, VM_PASSWORD, PROXMOX_HOST, SSH_KEY loaded from secrets.sops.yaml via SOPS

# Add gpu tag(s) based on NVIDIA_DRIVER_VERSION from cpc.env
if [[ -n "$NVIDIA_DRIVER_VERSION" && "$NVIDIA_DRIVER_VERSION" != "none" ]]; then
  EXTRA_TEMPLATE_TAGS="${EXTRA_TEMPLATE_TAGS:+$EXTRA_TEMPLATE_TAGS }nvidia"
fi

set -e

# Smart image download with caching
download_image_legacy() {
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
            local remote_size=$(grep "Content-Length" "$temp_headers" | tail -1 | awk '{print $2}' | tr -d '\r')
            local remote_date=$(grep "Last-Modified" "$temp_headers" | tail -1 | cut -d' ' -f2- | tr -d '\r')
            
            # Get local file info
            local local_size=$(stat -c%s "$image_path" 2>/dev/null || echo "0")
            local local_date=$(date -r "$image_path" -u "+%a, %d %b %Y %H:%M:%S GMT" 2>/dev/null || echo "")
            
            echo -e "${BLUE}Remote: ${remote_size} bytes, ${remote_date}${ENDCOLOR}"
            echo -e "${BLUE}Local:  ${local_size} bytes, ${local_date}${ENDCOLOR}"
            
            # Compare sizes and dates
            if [[ "$remote_size" != "$local_size" ]] || [[ "$remote_date" != "$local_date" ]]; then
                echo -e "${YELLOW}Image has changed. Download needed.${ENDCOLOR}"
                force_download=true
            else
                echo -e "${GREEN}Image is up to date. Skipping download.${ENDCOLOR}"
                rm -f "$temp_headers"
                return 0
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

# Call the smart download function
download_image_legacy
echo ""

echo -e "${GREEN}Update, add packages, enable services, edit multipath config, set timezone, set firstboot scripts...${ENDCOLOR}"

# For Rocky Linux, Debian, and Ubuntu, we need to skip virt-customize due to libguestfs compatibility issues
if [[ "$IMAGE_NAME" == *"Rocky"* || "$IMAGE_NAME" == *"rocky"* ]]; then
    echo -e "${GREEN}Detected Rocky Linux image. Skipping virt-customize due to libguestfs compatibility issues...${ENDCOLOR}"
    echo -e "${GREEN}Rocky Linux configuration will be handled during VM boot via cloud-init...${ENDCOLOR}"
    # Create a marker file to indicate Rocky Linux image was processed differently
    touch /tmp/rocky_skip_virt_customize
elif [[ "$IMAGE_NAME" == *"debian"* || "$IMAGE_NAME" == *"Debian"* ]]; then
    echo -e "${GREEN}Detected Debian image. Skipping virt-customize completely due to compatibility issues...${ENDCOLOR}"
    echo -e "${GREEN}All configuration including QEMU Guest Agent installation will be handled during VM boot via cloud-init user-data...${ENDCOLOR}"
    # Create a marker file to indicate Debian image was processed without virt-customize
    touch /tmp/debian_skip_virt_customize
elif [[ "$IMAGE_NAME" == *"ubuntu"* || "$IMAGE_NAME" == *"Ubuntu"* ]]; then
    echo -e "${GREEN}Detected Ubuntu image. Skipping virt-customize completely due to compatibility issues...${ENDCOLOR}"
    echo -e "${GREEN}All configuration including QEMU Guest Agent installation will be handled during VM boot via cloud-init user-data...${ENDCOLOR}"
    # Create a marker file to indicate Ubuntu image was processed without virt-customize
    touch /tmp/ubuntu_skip_virt_customize
else
    sudo virt-customize -a "$PROXMOX_ISO_PATH"/"$IMAGE_NAME" \
         --mkdir /etc/systemd/system/containerd.service.d/ \
         --copy-in ./FilesToPlace/override.conf:/etc/systemd/system/containerd.service.d/ \
         --copy-in ./FilesToPlace/multipath.conf:/etc/ \
         --copy-in ./FilesToPlace/k8s_mods.conf:/etc/modules-load.d/ \
         --copy-in ./FilesToPlace/storage_mods.conf:/etc/modules-load.d/ \
         --copy-in ./FilesToPlace/k8s_sysctl.conf:/etc/sysctl.d/ \
         --copy-in ./FilesToPlace/99-inotify-limits.conf:/etc/sysctl.d/ \
         --copy-in ./FilesToPlace/setup-udev-rules.sh:/root/ \
         --copy-in ./FilesToPlace/apt-packages.sh:/root/ \
         --copy-in ./FilesToPlace/rpm-packages.sh:/root/ \
         --copy-in ./FilesToPlace/suse-packages.sh:/root/ \
         --copy-in ./FilesToPlace/universal-packages.sh:/root/ \
         --copy-in ./FilesToPlace/source-packages.sh:/root/ \
         --copy-in ./FilesToPlace/watch-disk-space.sh:/root/ \
         --copy-in ./FilesToPlace/extra-kernel-modules.sh:/root/ \
         --copy-in ./cpc.env:/etc/ \
         --timezone "$TIMEZONE" \
         --firstboot ./FilesToRun/install_packages.sh
fi

# Note: qemu-guest-agent and cloud-init will be installed during firstboot to avoid space issues
# Note: cpc.env is now the source of truth for environment variables
# firstboot script creates /tmp/.firstboot when finished

echo -e "${GREEN}Deleting the old template vm if it exists...${ENDCOLOR}"
sudo qm stop "$TEMPLATE_VM_ID" --skiplock 1 || true
sudo qm destroy "$TEMPLATE_VM_ID" --purge 1 --skiplock 1 --destroy-unreferenced-disks 1 || true

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

echo -e "${GREEN}Setting the VM options...${ENDCOLOR}"

# Check if this is a Debian or Ubuntu image and use custom cloud-init user-data
if [[ "$IMAGE_NAME" == *"debian"* || "$IMAGE_NAME" == *"Debian"* ]]; then
    echo -e "${GREEN}Configuring Debian VM with custom cloud-init user-data...${ENDCOLOR}"
    
    # Check if the cloud-init user-data file exists
    if [ ! -f "./debian-cloud-init-userdata.yaml" ]; then
        echo -e "${RED}Error: debian-cloud-init-userdata.yaml not found!${ENDCOLOR}"
        exit 1
    fi
    
    # Create temporary cloud-init user-data file for this specific VM
    TEMP_USERDATA="/tmp/debian-userdata-${TEMPLATE_VM_ID}.yaml"
    
    # Replace variables in the cloud-init file
    echo -e "${GREEN}Processing cloud-init template variables...${ENDCOLOR}"
    # Set VM_HOSTNAME to template name + ID for better identification
    VM_HOSTNAME="debian-template-${TEMPLATE_VM_ID}"
    cat "./debian-cloud-init-userdata.yaml" | \
        sed "s|\${VM_USERNAME}|$VM_USERNAME|g" | \
        sed "s|\${VM_SSH_KEY}|$VM_SSH_KEY|g" | \
        sed "s|\${VM_HOSTNAME}|$VM_HOSTNAME|g" > "$TEMP_USERDATA"
    
    # Copy the user-data file to Proxmox snippets directory first
    echo -e "${GREEN}Copying cloud-init user-data to Proxmox snippets directory...${ENDCOLOR}"
    snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo mkdir -p "$snippets_path"
    sudo cp "$TEMP_USERDATA" "${snippets_path}/debian-userdata-${TEMPLATE_VM_ID}.yaml"
    sudo chmod 644 "${snippets_path}/debian-userdata-${TEMPLATE_VM_ID}.yaml"
    
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
      --cicustom "user=${PROXMOX_DISK_DATASTORE}:snippets/debian-userdata-${TEMPLATE_VM_ID}.yaml" \
      --agent "enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1" \
      --hotplug cpu,disk,network,usb \
      --tags "$EXTRA_TEMPLATE_TAGS ${KUBERNETES_MEDIUM_VERSION}"
elif [[ "$IMAGE_NAME" == *"ubuntu"* || "$IMAGE_NAME" == *"Ubuntu"* ]]; then
    echo -e "${GREEN}Configuring Ubuntu VM with custom cloud-init user-data...${ENDCOLOR}"
    
    # Check if the cloud-init user-data file exists
    if [ ! -f "./ubuntu-cloud-init-userdata.yaml" ]; then
        echo -e "${RED}Error: ubuntu-cloud-init-userdata.yaml not found!${ENDCOLOR}"
        exit 1
    fi
    
    # Create temporary cloud-init user-data file for this specific VM
    TEMP_USERDATA="/tmp/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml"
    
    # Replace variables in the cloud-init file
    echo -e "${GREEN}Processing cloud-init template variables...${ENDCOLOR}"
    # Set VM_HOSTNAME to template name + ID for better identification
    VM_HOSTNAME="ubuntu-template-${TEMPLATE_VM_ID}"
    cat "./ubuntu-cloud-init-userdata.yaml" | \
        sed "s|\${VM_USERNAME}|$VM_USERNAME|g" | \
        sed "s|\${VM_SSH_KEY}|$VM_SSH_KEY|g" | \
        sed "s|\${VM_HOSTNAME}|$VM_HOSTNAME|g" > "$TEMP_USERDATA"
    
    # Copy the user-data file to Proxmox snippets directory first
    echo -e "${GREEN}Copying cloud-init user-data to Proxmox snippets directory...${ENDCOLOR}"
    snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo mkdir -p "$snippets_path"
    sudo cp "$TEMP_USERDATA" "${snippets_path}/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml"
    sudo chmod 644 "${snippets_path}/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml"
    
    # Also create a generic ubuntu-userdata.yaml for future VM deployments
    sudo cp "$TEMP_USERDATA" "${snippets_path}/ubuntu-userdata.yaml"
    sudo chmod 644 "${snippets_path}/ubuntu-userdata.yaml"
    echo -e "${GREEN}Created generic ubuntu-userdata.yaml for VM deployments${ENDCOLOR}"
    
    # Copy machine-id script into VM
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
else
    # Standard configuration for non-Debian images
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
      --agent "enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1" \
      --hotplug cpu,disk,network,usb \
      --tags "$EXTRA_TEMPLATE_TAGS ${KUBERNETES_MEDIUM_VERSION}"
fi

echo -e "${GREEN}Expanding disk to $TEMPLATE_DISK_SIZE...${ENDCOLOR}"
sudo qm resize "$TEMPLATE_VM_ID" virtio0 "$TEMPLATE_DISK_SIZE"

echo -e "${GREEN}Starting the VM, allowing firstboot script to install packages...${ENDCOLOR}"
sudo qm start "$TEMPLATE_VM_ID"

start_time_packages=$(date +%s)

echo -e "${GREEN}Sleeping 180s to allow VM and the QEMU Guest Agent to start...${ENDCOLOR}"
sleep 180s

echo -e -n "${GREEN}Waiting for all packages to be installed${ENDCOLOR}"
timeout_counter=0
max_timeout=3600 # 1 hour maximum wait time
qemu_agent_check_counter=0
while true; do
  # First check if QEMU Guest Agent is responsive
  if ! sudo qm guest exec "$TEMPLATE_VM_ID" echo "ping" >/dev/null 2>&1; then
    qemu_agent_check_counter=$((qemu_agent_check_counter + 2))
    if [[ $qemu_agent_check_counter -ge 300 ]]; then # 5 minutes without agent
      echo -e "\n${RED}QEMU Guest Agent not responding after 5 minutes. Checking VM status...${ENDCOLOR}"
      vm_status=$(sudo qm status "$TEMPLATE_VM_ID" | grep "status:" | awk '{print $2}')
      echo -e "${RED}VM Status: $vm_status${ENDCOLOR}"
      if [[ "$vm_status" != "running" ]]; then
        echo -e "${RED}VM is not running. Template creation failed.${ENDCOLOR}"
        exit 1
      fi
      qemu_agent_check_counter=0 # Reset counter
    fi
    echo -n "."
    sleep 2
    timeout_counter=$((timeout_counter + 2))
    if [[ $timeout_counter -gt $max_timeout ]]; then
      echo -e "\n${RED}Timeout waiting for QEMU Guest Agent after $max_timeout seconds.${ENDCOLOR}"
      exit 1
    fi
    continue
  fi
  
  # QEMU Guest Agent is responsive, now check for completion
  if [[ "$IMAGE_NAME" == *"debian"* || "$IMAGE_NAME" == *"Debian"* ]]; then
    # For Debian, check cloud-init completion
    output=$(sudo qm guest exec "$TEMPLATE_VM_ID" cat /var/log/debian-cloud-init-complete.log 2>/dev/null)
    success=$?
    if [[ $success -eq 0 ]]; then
      echo -e "\n${GREEN}Debian cloud-init configuration complete. VM will shutdown automatically...${ENDCOLOR}"
      break
    fi
    
    # Also check if cloud-init finished (alternative check)
    cloud_init_status=$(sudo qm guest exec "$TEMPLATE_VM_ID" cloud-init status 2>/dev/null | jq -r '.stdout' 2>/dev/null)
    if [[ "$cloud_init_status" == *"done"* ]]; then
      echo -e "\n${GREEN}Cloud-init reported as done. Proceeding...${ENDCOLOR}"
      break
    fi
  elif [[ "$IMAGE_NAME" == *"ubuntu"* || "$IMAGE_NAME" == *"Ubuntu"* ]]; then
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
  else
    # For non-Debian/Ubuntu images, check firstboot completion
    output=$(sudo qm guest exec "$TEMPLATE_VM_ID" cat /tmp/.firstboot 2>/dev/null)
    success=$?
    if [[ $success -eq 0 ]]; then
      exit_code=$(echo "$output" | jq '.exitcode')
      if [[ $? -eq 0 && $exit_code -eq 0 ]]; then
        echo -e "\n${GREEN}Firstboot complete. Proceeding with cloud-init reset and shutdown...${ENDCOLOR}"
        break
      fi
    fi
  fi
  
  # Check for timeout
  timeout_counter=$((timeout_counter + 2))
  if [[ $timeout_counter -gt $max_timeout ]]; then
    echo -e "\n${RED}Timeout waiting for firstboot to complete after $max_timeout seconds. Continuing anyway...${ENDCOLOR}"
    break
  fi
  
  echo -n "."
  sleep 2
done

end_time_packages=$(date +%s)
elapsed_time_packages=$(( end_time_packages - start_time_packages ))
echo -e "${GREEN}Elapsed time installing packages: $((elapsed_time_packages / 60)) minutes and $((elapsed_time_packages % 60)) seconds.${ENDCOLOR}"

echo -e "${GREEN}Handling VM shutdown and cleanup...${ENDCOLOR}"

if [[ "$IMAGE_NAME" == *"debian"* || "$IMAGE_NAME" == *"Debian"* || "$IMAGE_NAME" == *"ubuntu"* || "$IMAGE_NAME" == *"Ubuntu"* ]]; then
    echo -e "${GREEN}Debian/Ubuntu VM should shutdown automatically. Waiting for shutdown...${ENDCOLOR}"
    
    # Wait for VM to shutdown automatically (up to 5 minutes)
    shutdown_timeout=300
    shutdown_counter=0
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
else
    echo -e "${GREEN}Print out disk space stats...${ENDCOLOR}"
    log_output=$(sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c "cat /var/log/watch-disk-space.txt" | jq -r '.["out-data"]' 2>/dev/null || echo "Failed to retrieve disk space log")
    if echo "$log_output" | grep -q "critically low"; then
        echo -e "${RED}Disk space reached a critically low value during package installation. Please increase TEMPLATE_DISK_SIZE and try again.${ENDCOLOR}"
        # Adding an attempt to shutdown before exiting to prevent a zombie VM
        sudo qm stop "$TEMPLATE_VM_ID" --skiplock 1 || true
        exit 1
    elif echo "$log_output" | grep -q "Failed to retrieve"; then
        echo -e "${GREEN}Could not retrieve disk space log from VM (VM may have already shut down). Continuing with template creation...${ENDCOLOR}"
    else
        echo -e "${GREEN}Disk space log:${ENDCOLOR}"
        echo "$log_output"
    fi

    echo -e "${GREEN}Checking for 'No space left' logs...${ENDCOLOR}"
    # Corrected the grep command to search within the output of qm guest exec
    firstboot_log_output=$(sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c "cat /var/log/template-firstboot-*" | jq -r '.["out-data"]' 2>/dev/null || echo "Failed to retrieve firstboot log")

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
    sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c  "rm -f /etc/cloud/clean.d/README && cloud-init clean --logs" >/dev/null

    echo -e "${GREEN}Shutting down the VM gracefully...${ENDCOLOR}"
    sudo qm shutdown "$TEMPLATE_VM_ID"
fi

# For Ubuntu, ensure machine-id is cleaned before templating to avoid duplicate IPs
if [[ "$IMAGE_NAME" == *"ubuntu"* || "$IMAGE_NAME" == *"Ubuntu"* ]]; then
    echo -e "${GREEN}Cleaning machine-id for Ubuntu template...${ENDCOLOR}"
    # Try to clean up machine-id in the template itself if possible
    if sudo qm guest exec "$TEMPLATE_VM_ID" -- /bin/sh -c "truncate -s 0 /etc/machine-id && rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1; then
        echo -e "${GREEN}Successfully cleared machine-id files in the template${ENDCOLOR}"
    else
        echo -e "${YELLOW}Could not clear machine-id directly, VM may already be stopped${ENDCOLOR}"
    fi
    sudo qm set "$TEMPLATE_VM_ID" -description "Machine-ID will be regenerated on clone to ensure unique DHCP IPs"
fi

echo -e "${GREEN}Converting the shut-down VM into a template...${ENDCOLOR}"
sudo qm template "$TEMPLATE_VM_ID"

echo -e "${GREEN}Deleting the downloaded image...${ENDCOLOR}"
sudo rm -f "${PROXMOX_ISO_PATH:?PROXMOX_ISO_PATH is not set}/${IMAGE_NAME:?IMAGE_NAME is not set}"*

# Clean up temporary cloud-init files
if [[ "$IMAGE_NAME" == *"debian"* || "$IMAGE_NAME" == *"Debian"* ]]; then
    echo -e "${GREEN}Cleaning up temporary Debian cloud-init files...${ENDCOLOR}"
    snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo rm -f "${snippets_path}/debian-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
    rm -f "/tmp/debian-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
elif [[ "$IMAGE_NAME" == *"ubuntu"* || "$IMAGE_NAME" == *"Ubuntu"* ]]; then
    echo -e "${GREEN}Preserving Ubuntu cloud-init files for VM deployments...${ENDCOLOR}"
    # Create a generic cloud-init file for all Ubuntu VMs
    snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo cp "./ubuntu-cloud-init-userdata.yaml" "${snippets_path}/ubuntu-userdata.yaml"
    sudo chmod 644 "${snippets_path}/ubuntu-userdata.yaml"
    
    # Important: ALSO KEEP the template-specific file (this is what Terraform/OpenTofu references)
    snippets_path="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    sudo cp "./ubuntu-cloud-init-userdata.yaml" "${snippets_path}/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
    sudo chmod 644 "${snippets_path}/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
    echo -e "${GREEN}Created permanent ubuntu cloud-init files in snippets for VM deployments${ENDCOLOR}"
    
    # Clean up only the temp file
    rm -f "/tmp/ubuntu-userdata-${TEMPLATE_VM_ID}.yaml" 2>/dev/null || true
fi

echo -e "${GREEN}Template created successfully${ENDCOLOR}"

end_time_total=$(date +%s)
elapsed_time_total=$(( end_time_total - start_time_total ))
echo -e "${GREEN}Total elapsed time: $((elapsed_time_total / 60)) minutes and $((elapsed_time_total % 60)) seconds.${ENDCOLOR}"
