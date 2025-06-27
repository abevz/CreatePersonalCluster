#!/bin/bash

# Script to extract DNS servers from Terraform configuration
# This script is used by the configure-coredns command to automatically
# get the Pi-hole DNS server IP from Terraform variables

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

# Function to extract DNS servers from terraform.tfvars
get_dns_from_tfvars() {
    local tfvars_file="$TERRAFORM_DIR/terraform.tfvars"
    if [[ -f "$tfvars_file" ]]; then
        grep -E '^dns_servers\s*=' "$tfvars_file" | \
        sed -E 's/.*\[\"([^"]+)\".*/\1/' | \
        head -n 1
    fi
}

# Function to extract DNS servers from variables.tf default
get_dns_from_variables() {
    local variables_file="$TERRAFORM_DIR/variables.tf"
    if [[ -f "$variables_file" ]]; then
        awk '/variable "dns_servers"/,/}/' "$variables_file" | \
        grep -E 'default\s*=' | \
        sed -E 's/.*\[\"([^"]+)\".*/\1/' | \
        head -n 1
    fi
}

# Function to get DNS servers from Terraform output (if available)
get_dns_from_output() {
    local current_dir=$(pwd)
    cd "$TERRAFORM_DIR" 2>/dev/null || return 1
    
    # Try to get from terraform output
    terraform output -json dns_servers 2>/dev/null | \
    jq -r '.[0]' 2>/dev/null || \
    tofu output -json dns_servers 2>/dev/null | \
    jq -r '.[0]' 2>/dev/null
    
    cd "$current_dir"
}

# Main logic
main() {
    local dns_server=""
    
    # Try multiple sources in order of preference
    # 1. Terraform output (most current)
    dns_server=$(get_dns_from_output)
    
    # 2. terraform.tfvars (user overrides)
    if [[ -z "$dns_server" || "$dns_server" == "null" ]]; then
        dns_server=$(get_dns_from_tfvars)
    fi
    
    # 3. variables.tf default
    if [[ -z "$dns_server" ]]; then
        dns_server=$(get_dns_from_variables)
    fi
    
    # 4. Fallback
    if [[ -z "$dns_server" ]]; then
        dns_server="10.10.10.36"
    fi
    
    echo "$dns_server"
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
