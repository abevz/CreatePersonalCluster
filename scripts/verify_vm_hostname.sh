#!/bin/bash

# Verify that VM hostnames are correctly set
# This script connects to each node via SSH and checks the hostname

# Source environment variables
source ../cpc.env

# Get Proxmox credentials if not set
if [ -z "$PROXMOX_HOST" ] || [ -z "$PROXMOX_USERNAME" ]; then
  echo "PROXMOX_HOST or PROXMOX_USERNAME not set. Setting from terraform secrets..."
  cd ../terraform
  PROXMOX_HOST=$(sops --decrypt --extract '["virtual_environment_endpoint"]' secrets.sops.yaml | sed 's|https://||' | sed 's|:8006/api2/json||')
  PROXMOX_USERNAME=$(sops --decrypt --extract '["proxmox_username"]' secrets.sops.yaml)
  cd - > /dev/null
fi

# Get node information from terraform
cd ../terraform
NODE_IPS=$(tofu output -json k8s_node_ips)
NODE_NAMES=$(tofu output -json k8s_node_names)
cd - > /dev/null

# Check if we got the node information
if [ -z "$NODE_IPS" ] || [ -z "$NODE_NAMES" ]; then
  echo "Error: Could not retrieve node information from terraform. Make sure the cluster is deployed."
  exit 1
fi

# Parse the JSON to get the node IPs and expected hostnames
echo "Checking VM hostnames..."
echo "------------------------"
echo "| Node Key | IP Address | Expected Hostname | Actual Hostname | Status |"
echo "------------------------"

while read -r node_key ip_address; do
  # Get the expected hostname for this node
  expected_hostname=$(echo "$NODE_NAMES" | jq -r ".[\"$node_key\"]")
  
  # Check the actual hostname on the VM
  # Try with both user from cpc.env and root as backup
  actual_hostname=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $VM_USERNAME@$ip_address hostname 2>/dev/null)
  
  if [ -z "$actual_hostname" ]; then
    # Try with root user if VM_USERNAME doesn't work
    actual_hostname=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$ip_address hostname 2>/dev/null)
  fi
  
  # Check if hostname matches expected
  if [ -z "$actual_hostname" ]; then
    status="ERROR: Could not connect"
  elif [ "$actual_hostname" == "$expected_hostname" ]; then
    status="✓ MATCH"
  else
    status="✗ MISMATCH"
  fi
  
  # Print the results
  printf "| %-8s | %-10s | %-17s | %-15s | %-7s |\n" \
    "$node_key" "$ip_address" "$expected_hostname" "${actual_hostname:-N/A}" "$status"
  
done < <(echo "$NODE_IPS" | jq -r 'to_entries[] | "\(.key) \(.value)"')

echo "------------------------"
echo ""

# Count successes and failures
success_count=$(echo "$NODE_IPS" | jq -r 'to_entries[] | "\(.key) \(.value)"' | wc -l)
total_count=$(echo "$NODE_IPS" | jq -r 'to_entries[] | "\(.key) \(.value)"' | wc -l)

echo "Summary: $success_count of $total_count hostnames verified."

# Provide instructions for fixing hostnames if needed
if [ $success_count -lt $total_count ]; then
  echo ""
  echo "Some hostname verifications failed. To fix a hostname on a specific VM, use:"
  echo "./fix_vm_hostname.sh <vm_id> <hostname>"
  echo ""
  echo "Example: ./fix_vm_hostname.sh 300 cu1.bevz.net"
fi

exit 0
