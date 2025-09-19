#!/bin/bash

# Generate cloud-init snippets with correct hostname for each node
# This script is meant to be run before applying the Terraform configuration

# Check for necessary environment variables (SOPS secrets should be loaded by cpc)
if [ -z "$PROXMOX_HOST" ] || [ -z "$PROXMOX_USERNAME" ] || [ -z "$VM_USERNAME" ]; then
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

  # If still not found, require explicit definition in workspace environment
  if [ -z "$RELEASE_LETTER" ]; then
    echo "ERROR: RELEASE_LETTER not found in environment or workspace .env file"
    echo "This variable must be explicitly defined in envs/${CURRENT_WORKSPACE}.env to prevent hostname conflicts"
    echo ""
    echo "Add this line to envs/${CURRENT_WORKSPACE}.env:"
    echo "RELEASE_LETTER=\"[single letter for this workspace]\""
    echo ""
    echo "Suggested values:"
    echo "  debian -> RELEASE_LETTER=\"d\""
    echo "  ubuntu -> RELEASE_LETTER=\"u\""
    echo "  rocky  -> RELEASE_LETTER=\"r\""
    echo "  suse   -> RELEASE_LETTER=\"s\""
    echo ""
    echo "Choose a unique letter to avoid hostname conflicts between workspaces."
    exit 1
  fi
fi

# Get cluster domain from Terraform variables
VM_DOMAIN=$(grep -A 3 'variable "vm_domain"' "$REPO_PATH/terraform/variables.tf" | grep 'default' | cut -d'"' -f2)

# Get node information from the terraform output
echo "Getting node information from terraform output..."
cd "$REPO_PATH/terraform"
CLUSTER_SUMMARY=$(tofu output -json cluster_summary 2>/dev/null)
cd "$REPO_PATH/scripts"

# Initialize arrays
HOSTNAMES=()
ROLES=()
INDICES=()

# If the tofu output command succeeds and is not empty, parse the JSON
if [ $? -eq 0 ] && [ -n "$CLUSTER_SUMMARY" ] && [ "$CLUSTER_SUMMARY" != "null" ]; then
  echo "Successfully got node information from tofu output."
  while read -r key hostname; do
    short_hostname=$(echo "$hostname" | cut -d'.' -f1)
    role="${short_hostname:0:1}"
    
    # Extract index using regex - handle both formats: c1, cb1, w1, wb1, etc.
    if [[ "$short_hostname" =~ ^[cw]([0-9]+)$ ]]; then
      # Format: c1, w1, w2 (no release letter)
      index="${BASH_REMATCH[1]}"
    elif [[ "$short_hostname" =~ ^[cw][a-z]([0-9]+)$ ]]; then
      # Format: cb1, wb1, wb2 (with release letter)
      index="${BASH_REMATCH[1]}"
    else
      # Fallback for unexpected format
      index="${short_hostname:2}"
    fi

    HOSTNAMES+=("$hostname")
    ROLES+=("$role")
    INDICES+=("$index")
  done < <(echo "$CLUSTER_SUMMARY" | jq -r 'to_entries[] | "\(.key) \(.value.hostname)"')
else
  echo "Warning: Could not get node information from terraform output. Falling back to default node definitions."
  # Fallback logic for new workspaces - read from environment file
  HOSTNAMES=() # Ensure it's empty
  
  # Read additional nodes from environment file
  ENV_FILE="$REPO_PATH/envs/$CURRENT_WORKSPACE.env"
  ADDITIONAL_WORKERS=""
  ADDITIONAL_CONTROLPLANES=""
  
  if [ -f "$ENV_FILE" ]; then
    # Extract additional workers and control planes
    ADDITIONAL_WORKERS=$(grep -E "^ADDITIONAL_WORKERS=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' || echo "")
    ADDITIONAL_CONTROLPLANES=$(grep -E "^ADDITIONAL_CONTROLPLANES=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' || echo "")
  fi
  
  # Start with base nodes
  ROLES=("c" "w" "w")
  INDICES=("1" "1" "2")  # controlplane1, worker1, worker2
  
  # Add additional workers
  if [ -n "$ADDITIONAL_WORKERS" ]; then
    IFS=',' read -ra WORKER_ARRAY <<< "$ADDITIONAL_WORKERS"
    for worker in "${WORKER_ARRAY[@]}"; do
      if [ -n "$worker" ]; then
        # Extract number from worker name (e.g., worker-3 -> 3)
        if [[ "$worker" =~ worker-([0-9]+) ]]; then
          WORKER_NUM="${BASH_REMATCH[1]}"
        elif [[ "$worker" =~ worker([0-9]+) ]]; then
          WORKER_NUM="${BASH_REMATCH[1]}"
        else
          WORKER_NUM="3"  # fallback
        fi
        ROLES+=("w")
        INDICES+=("$WORKER_NUM")
      fi
    done
  fi
  
  # Add additional control planes
  if [ -n "$ADDITIONAL_CONTROLPLANES" ]; then
    IFS=',' read -ra CP_ARRAY <<< "$ADDITIONAL_CONTROLPLANES"
    for cp in "${CP_ARRAY[@]}"; do
      if [ -n "$cp" ]; then
        # Extract number from controlplane name (e.g., controlplane-2 -> 2)
        if [[ "$cp" =~ controlplane-([0-9]+) ]]; then
          CP_NUM="${BASH_REMATCH[1]}"
        elif [[ "$cp" =~ controlplane([0-9]+) ]]; then
          CP_NUM="${BASH_REMATCH[1]}"
        else
          CP_NUM="2"  # fallback
        fi
        ROLES+=("c")
        INDICES+=("$CP_NUM")
      fi
    done
  fi
fi

# Create snippets directory if it doesn't exist
mkdir -p "$REPO_PATH/terraform/snippets"

echo "Generating cloud-init snippets for each node..."

# For each node, generate a cloud-init snippet with the correct hostname
for i in "${!ROLES[@]}"; do
  ROLE="${ROLES[$i]}"
  
  # Use the INDEX from our arrays - we've already calculated them correctly
  INDEX="${INDICES[$i]}"
  
  echo "Generating for node $i: ROLE=$ROLE, INDEX=$INDEX"

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
# echo "Debug: PROXMOX_HOST='$PROXMOX_HOST', PROXMOX_USERNAME='$PROXMOX_USERNAME', PROXMOX_SSH_USERNAME='$PROXMOX_SSH_USERNAME'"
log_debug "Proxmox connection details: HOST='$PROXMOX_HOST', USERNAME='$PROXMOX_USERNAME', SSH_USERNAME='$PROXMOX_SSH_USERNAME'"
if [ -n "$PROXMOX_HOST" ] && [ -n "$PROXMOX_SSH_USERNAME" ]; then
  echo "Copying snippets to Proxmox host..."

  # Extract hostname from PROXMOX_HOST URL (remove protocol and port)
  PROXMOX_HOSTNAME=$(echo "$PROXMOX_HOST" | sed 's|https://||' | sed 's|/.*||' | sed 's|:.*||')
  echo "Using Proxmox hostname: $PROXMOX_HOSTNAME"

  SNIPPETS_PATH="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"

  # Ensure the remote directory exists
  ssh "$PROXMOX_SSH_USERNAME@$PROXMOX_HOSTNAME" "sudo mkdir -p $SNIPPETS_PATH"

  # Use rsync for efficient copying
  rsync -avz --progress "$REPO_PATH/terraform/snippets/" "$PROXMOX_SSH_USERNAME@$PROXMOX_HOSTNAME:/tmp/cpc-snippets"
  ssh "$PROXMOX_SSH_USERNAME@$PROXMOX_HOSTNAME" "sudo cp /tmp/cpc-snippets/* $SNIPPETS_PATH/ && sudo chmod 644 $SNIPPETS_PATH/*"

  echo "Done copying snippets to Proxmox host at $SNIPPETS_PATH/"
fi
