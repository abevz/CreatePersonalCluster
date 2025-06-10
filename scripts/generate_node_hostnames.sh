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

# Map workspace to release letter (same logic as in locals.tf)
case "$CURRENT_WORKSPACE" in
  "debian") RELEASE_LETTER="d" ;;
  "ubuntu") RELEASE_LETTER="u" ;;
  "rocky")  RELEASE_LETTER="r" ;;
  "suse")   RELEASE_LETTER="s" ;;
  *)        RELEASE_LETTER="x" ;;  # fallback
esac

# Get cluster domain from Terraform variables
VM_DOMAIN=$(grep -A 3 'variable "vm_domain"' "$REPO_PATH/terraform/variables.tf" | grep 'default' | cut -d'"' -f2)

# Get node information from the terraform output instead of parsing the configuration files
# This is more reliable as it uses the actual data structure that Terraform/OpenTofu has built
echo "Getting node information from terraform output..."
cd "$REPO_PATH/terraform"
NODE_INFO=$(tofu output -json k8s_node_names)
cd "$REPO_PATH/scripts"

# Parse the JSON output to extract roles and hostnames
HOSTNAMES=()
ROLES=()
INDICES=()

# If the tofu output command succeeds, parse the JSON
if [ $? -eq 0 ] && [ -n "$NODE_INFO" ]; then
  # Extract roles and indices from the hostname patterns (e.g., "cu1.bevz.net" -> role="c", index="1")
  while read -r key hostname; do
    # Extract just the hostname part before the domain (e.g., "cu1" from "cu1.bevz.net")
    short_hostname=$(echo "$hostname" | cut -d'.' -f1)
    
    # Extract role (first letter) and index (everything after second character)
    # For example: "cu1" -> role="c", release="u", index="1"
    role="${short_hostname:0:1}"       # First character (c or w)
    release="${short_hostname:1:1}"    # Second character (d, u, r, s)
    index="${short_hostname:2}"        # Everything after second character (1, 2, etc.)
    
    HOSTNAMES+=("$hostname")
    ROLES+=("$role")
    INDICES+=("$index")
    
  done < <(echo "$NODE_INFO" | jq -r 'to_entries[] | "\(.key) \(.value)"')
  
  echo "Found ${#HOSTNAMES[@]} nodes with roles ${ROLES[*]} and indices ${INDICES[*]}"
else
  echo "Warning: Could not get node information from terraform output. Falling back to parsing configuration files."
  
  # Fallback to grep-based parsing if the tofu command fails
  # Parse the node_definitions section to get the structure
  NODE_DEFS=$(grep -A 10 "node_definitions = {" "$REPO_PATH/terraform/locals.tf" | grep -E "(controlplane|worker[0-9]*)" | awk '{print $1}')
  
  # Create arrays for roles and indices
  ROLES=()
  INDICES=()
  
  # Process each node definition
  while IFS= read -r node_def; do
    if [[ "$node_def" == *"controlplane"* ]]; then
      ROLES+=("c")
      INDICES+=("1")
    elif [[ "$node_def" == *"worker0"* ]]; then
      ROLES+=("w")
      INDICES+=("1")
    elif [[ "$node_def" == *"worker1"* ]]; then
      ROLES+=("w")
      INDICES+=("2")
    fi
  done <<< "$NODE_DEFS"
fi

# Create snippets directory if it doesn't exist
mkdir -p "$REPO_PATH/terraform/snippets"

echo "Generating cloud-init snippets for each node..."

# For each node, generate a cloud-init snippet with the correct hostname
for i in "${!ROLES[@]}"; do
  ROLE="${ROLES[$i]}"
  INDEX="${INDICES[$i]}"
  
  # If we have full hostnames from terraform output, use them
  if [ ${#HOSTNAMES[@]} -gt 0 ]; then
    FQDN="${HOSTNAMES[$i]}"
    HOSTNAME=$(echo "$FQDN" | cut -d'.' -f1)
    echo "Using hostname from terraform output: $FQDN"
  else
    # Fall back to generating the hostname from components
    CLEAN_DOMAIN=${VM_DOMAIN#.}
    HOSTNAME="${ROLE}${RELEASE_LETTER}${INDEX}"
    FQDN="${HOSTNAME}.${CLEAN_DOMAIN}"
    echo "Generated hostname: $FQDN"
  fi
  
  # Create a cloud-init snippet for this node - naming format must match what's expected in nodes.tf
  NODE_KEY="node-${ROLE}${RELEASE_LETTER}${INDEX}-userdata.yaml"
  cat "$REPO_PATH/terraform/snippets/hostname-template.yaml" | 
    sed "s|\${hostname}|$FQDN|g" > "$REPO_PATH/terraform/snippets/$NODE_KEY"
  
  echo "Created cloud-init snippet for $FQDN"
done

echo "Done. Created $(ls -la $REPO_PATH/terraform/snippets/node-*-userdata.yaml | wc -l) cloud-init snippets."

# Create a summary file for Terraform to use
echo "Creating summary file for Terraform..."
echo "# Auto-generated cloud-init snippets" > $REPO_PATH/terraform/snippets/summary.txt
echo "# Generated on $(date)" >> $REPO_PATH/terraform/snippets/summary.txt
echo "# Node count: ${#ROLES[@]}" >> $REPO_PATH/terraform/snippets/summary.txt

# Copy snippets to Proxmox host
echo "Debug: PROXMOX_HOST='$PROXMOX_HOST', PROXMOX_USERNAME='$PROXMOX_USERNAME'"
if [ -n "$PROXMOX_HOST" ] && [ -n "$PROXMOX_USERNAME" ]; then
  echo "Copying snippets to Proxmox host..."
  
  for i in "${!ROLES[@]}"; do
    ROLE="${ROLES[$i]}"
    INDEX="${INDICES[$i]}"
    
    # Get the node key for the snippet filename
    NODE_KEY="node-${ROLE}${RELEASE_LETTER}${INDEX}-userdata.yaml"
    
    # Copy the snippet to Proxmox
    scp "$REPO_PATH/terraform/snippets/$NODE_KEY" "$PROXMOX_USERNAME@$PROXMOX_HOST:/tmp/"
    
    # Use configurable storage path instead of hardcoded /var/lib/vz/snippets
    SNIPPETS_PATH="${PROXMOX_STORAGE_BASE_PATH}/${PROXMOX_DISK_DATASTORE}/snippets"
    ssh "$PROXMOX_USERNAME@$PROXMOX_HOST" "sudo mkdir -p $SNIPPETS_PATH && sudo cp /tmp/$NODE_KEY $SNIPPETS_PATH/"
    
    # Ensure the file has correct permissions
    ssh "$PROXMOX_USERNAME@$PROXMOX_HOST" "sudo chmod 644 $SNIPPETS_PATH/$NODE_KEY"
    
    echo "Copied $NODE_KEY to Proxmox host at $SNIPPETS_PATH/"
  done
  
  echo "Done copying snippets to Proxmox host at $SNIPPETS_PATH/"
fi
