#!/bin/bash

# Generate cloud-init snippets with correct hostname for each node
# This script is meant to be run before applying the Terraform configuration

# Check for necessary environment variables (SOPS secrets should be loaded by cpc)
if [ -z "$PROXMOX_HOST" ] || [ -z "$PROXMOX_USERNAME" ]; then
  echo "Error: Required environment variables not set. This script should be called via 'cpc' command."
  echo "Please run: cpc ctx <workspace> && cpc generate-hostnames"
  exit 1
fi

# Load additional configuration variables from cpc.env
if [ -f "$REPO_PATH/cpc.env" ]; then
  source "$REPO_PATH/cpc.env"
else
  echo "Warning: cpc.env not found. Using default storage paths."
  PROXMOX_STORAGE_BASE_PATH="/DataPool"
  PROXMOX_DISK_DATASTORE="MyStorage"
fi

echo "Successfully loaded secrets (PROXMOX_HOST: $PROXMOX_HOST, PROXMOX_USERNAME: $PROXMOX_USERNAME)"
echo "Using storage configuration: ${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"

# Get the current workspace to determine release letter
cd "$REPO_PATH/terraform"
CURRENT_WORKSPACE=$(tofu workspace show)
cd "$REPO_PATH/scripts"

# Check if RELEASE_LETTER is already set in environment
if [ -z "$RELEASE_LETTER" ]; then
  # Try to load from workspace's .env file if it exists
  ENV_FILE="$REPO_PATH/envs/$CURRENT_WORKSPACE.env"
  if [ -f "$ENV_FILE" ]; then
    # Try to extract RELEASE_LETTER from the workspace's .env file
    ENV_RELEASE_LETTER=$(grep -E "^RELEASE_LETTER=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$ENV_RELEASE_LETTER" ]; then
      RELEASE_LETTER="$ENV_RELEASE_LETTER"
      echo "Using RELEASE_LETTER='$RELEASE_LETTER' from workspace .env file"
    fi
  fi

  # If still not found, fall back to the old mapping
  if [ -z "$RELEASE_LETTER" ]; then
    echo "RELEASE_LETTER not found in environment or workspace .env, falling back to mapping"
    # Map workspace to release letter (same logic as in locals.tf)
    case "$CURRENT_WORKSPACE" in
    "debian") RELEASE_LETTER="d" ;;
    "ubuntu") RELEASE_LETTER="u" ;;
    "rocky") RELEASE_LETTER="r" ;;
    "suse") RELEASE_LETTER="s" ;;
    *) RELEASE_LETTER="${CURRENT_WORKSPACE:0:1}" ;; # fallback to first letter of workspace
    esac
    echo "Mapped workspace '$CURRENT_WORKSPACE' to RELEASE_LETTER='$RELEASE_LETTER'"
  fi
fi

# Get cluster domain from Terraform variables
VM_DOMAIN=$(grep -A 3 'variable "vm_domain"' "$REPO_PATH/terraform/variables.tf" | grep 'default' | cut -d'"' -f2)

# Get node information from the terraform output
echo "Getting node information from terraform output..."
cd "$REPO_PATH/terraform"
NODE_INFO=$(tofu output -json k8s_node_names 2>/dev/null)
cd "$REPO_PATH/scripts"

# Initialize arrays
HOSTNAMES=()
ROLES=()
INDICES=()

# If the tofu output command succeeds and is not empty, parse the JSON
if [ $? -eq 0 ] && [ -n "$NODE_INFO" ] && [ "$NODE_INFO" != "null" ]; then
  echo "Successfully got node information from tofu output."
  while read -r key hostname; do
    short_hostname=$(echo "$hostname" | cut -d'.' -f1)
    role="${short_hostname:0:1}"
    index="${short_hostname:2}"

    HOSTNAMES+=("$hostname")
    ROLES+=("$role")
    INDICES+=("$index")
  done < <(echo "$NODE_INFO" | jq -r 'to_entries[] | "\(.key) \(.value)"')
else
  echo "Warning: Could not get node information from terraform output. Falling back to default node definitions."
  # Fallback logic for new workspaces
  HOSTNAMES=() # Ensure it's empty
  ROLES=("c" "w" "w")
  INDICES=("1" "2" "3") # Note: Terraform logic uses original_index 1, 1, 2. Let's stick to simple logic here for fallback.
fi

# Create snippets directory if it doesn't exist
mkdir -p "$REPO_PATH/terraform/snippets"

echo "Generating cloud-init snippets for each node..."

# For each node, generate a cloud-init snippet with the correct hostname
for i in "${!ROLES[@]}"; do
  ROLE="${ROLES[$i]}"
  # Adjust index for workers in fallback mode
  if [ ${#HOSTNAMES[@]} -eq 0 ]; then
    if [ "$ROLE" == "w" ]; then
      INDEX=$((i))
    else
      INDEX=1
    fi
  else
    INDEX="${INDICES[$i]}"
  fi

  # If we have full hostnames from terraform output, use them
  if [ ${#HOSTNAMES[@]} -gt 0 ] && [ -n "${HOSTNAMES[$i]}" ]; then
    FQDN="${HOSTNAMES[$i]}"
  else
    # Fall back to generating the hostname from components
    CLEAN_DOMAIN=${VM_DOMAIN#.}
    HOSTNAME="${ROLE}${RELEASE_LETTER}${INDEX}"
    FQDN="${HOSTNAME}.${CLEAN_DOMAIN}"
  fi

  echo "Generated hostname: $FQDN"

  # Create a cloud-init snippet for this node
  NODE_KEY="node-${ROLE}${RELEASE_LETTER}${INDEX}-userdata.yaml"
  cat "$REPO_PATH/terraform/snippets/hostname-template.yaml" |
    sed "s|\${hostname}|$FQDN|g" >"$REPO_PATH/terraform/snippets/$NODE_KEY"

  echo "Created cloud-init snippet for $FQDN"
done

echo "Done. Created $(ls -la $REPO_PATH/terraform/snippets/node-*-userdata.yaml | wc -l) cloud-init snippets."

# Create a summary file for Terraform to use
echo "Creating summary file for Terraform..."
echo "# Auto-generated cloud-init snippets" >$REPO_PATH/terraform/snippets/summary.txt
echo "# Generated on $(date)" >>$REPO_PATH/terraform/snippets/summary.txt
echo "# Node count: ${#ROLES[@]}" >>$REPO_PATH/terraform/snippets/summary.txt

# Copy snippets to Proxmox host
echo "Debug: PROXMOX_HOST='$PROXMOX_HOST', PROXMOX_USERNAME='$PROXMOX_USERNAME'"
if [ -n "$PROXMOX_HOST" ] && [ -n "$PROXMOX_USERNAME" ]; then
  echo "Copying snippets to Proxmox host..."

  SNIPPETS_PATH="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"

  # Ensure the remote directory exists
  ssh "$PROXMOX_USERNAME@$PROXMOX_HOST" "sudo mkdir -p $SNIPPETS_PATH"

  # Use rsync for efficient copying
  rsync -avz --progress "$REPO_PATH/terraform/snippets/" "$PROXMOX_USERNAME@$PROXMOX_HOST:/tmp/cpc-snippets"
  ssh "$PROXMOX_USERNAME@$PROXMOX_HOST" "sudo cp /tmp/cpc-snippets/* $SNIPPETS_PATH/ && sudo chmod 644 $SNIPPETS_PATH/*"

  echo "Done copying snippets to Proxmox host at $SNIPPETS_PATH/"
fi
