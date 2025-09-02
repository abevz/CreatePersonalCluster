#!/bin/bash
# =============================================================================
# CPC Pi-hole API Library  
# =============================================================================
# Provides functions for managing Pi-hole DNS records

# --- Pi-hole DNS Management Functions ---

# Execute Pi-hole DNS script with proper error handling
pihole_dns_exec() {
    local action="$1"
    shift
    
    local script_path="$REPO_PATH/scripts/add_pihole_dns.py"
    
    if [ ! -f "$script_path" ]; then
        log_fatal "Pi-hole DNS script not found at: $script_path"
    fi
    
    log_debug "Executing Pi-hole action: $action with args: $*"
    
    # Configure Python environment if needed
    if command -v python3 >/dev/null 2>&1; then
        python3 "$script_path" "$action" "$@"
    elif command -v python >/dev/null 2>&1; then
        python "$script_path" "$action" "$@"
    else
        log_fatal "Python not found. Please install Python to use Pi-hole DNS features."
    fi
}

# List all DNS records
pihole_dns_list() {
    log_step "Listing Pi-hole DNS records..."
    pihole_dns_exec "list" "$@"
}

# Add a new DNS record
pihole_dns_add() {
    local hostname="$1"
    local ip="$2"
    
    if [ -z "$hostname" ] || [ -z "$ip" ]; then
        log_error "Usage: pihole_dns_add <hostname> <ip_address>"
        return 1
    fi
    
    log_step "Adding DNS record: $hostname -> $ip"
    pihole_dns_exec "add" "$hostname" "$ip"
}

# Remove a DNS record  
pihole_dns_remove() {
    local hostname="$1"
    
    if [ -z "$hostname" ]; then
        log_error "Usage: pihole_dns_remove <hostname>"
        return 1
    fi
    
    log_step "Removing DNS record: $hostname"
    pihole_dns_exec "unregister-dns" "$hostname"
}

# Interactive add with menu selection
pihole_dns_interactive_add() {
    log_step "Starting interactive DNS record addition..."
    pihole_dns_exec "interactive-add" "$@"
}

# Interactive remove with menu selection
pihole_dns_interactive_remove() {
    log_step "Starting interactive DNS record removal..."
    pihole_dns_exec "interactive-unregister" "$@"
}

# Validate Pi-hole connectivity
pihole_validate_connection() {
    local pihole_server="$1"
    
    if [ -z "$pihole_server" ]; then
        log_error "Pi-hole server address not provided"
        return 1
    fi
    
    log_debug "Validating Pi-hole connection to: $pihole_server"
    
    # Try to reach Pi-hole API
    for endpoint in "${PIHOLE_API_ENDPOINTS[@]}"; do
        if curl -s --connect-timeout 5 "http://$pihole_server$endpoint" >/dev/null 2>&1; then
            log_success "Pi-hole API accessible at: $pihole_server$endpoint"
            return 0
        fi
    done
    
    log_warning "Could not connect to Pi-hole API at: $pihole_server"
    return 1
}

# Main Pi-hole DNS dispatcher function
cpc_dns_pihole() {
    if [[ "$1" == "-h" || "$1" == "--help" ]] || [[ -z "$1" ]]; then
        echo "Usage: cpc dns-pihole <action>"
        echo "Manages Pi-hole DNS records with VM FQDNs and IPs from the current Tofu workspace outputs."
        echo "Actions:"
        echo "  list             - Display current DNS records in Pi-hole"
        echo "  add              - Add all missing DNS records to Pi-hole"
        echo "  unregister-dns   - Remove all cluster DNS records from Pi-hole"
        echo "  interactive-add  - Interactively select which DNS records to add"
        echo "  interactive-unregister - Interactively select which DNS records to remove"
        echo "Requires 'sops' and 'curl' to be installed, and secrets.sops.yaml to be configured."
        return 0
    fi
    
    local action="$1"
    
    # Validate actions
    local valid_actions=("list" "add" "unregister-dns" "interactive-add" "interactive-unregister")
    local action_valid=false
    for valid_action in "${valid_actions[@]}"; do
        if [[ "$action" == "$valid_action" ]]; then
            action_valid=true
            break
        fi
    done
    
    if [[ "$action_valid" != "true" ]]; then
        log_error "Invalid action '$action' for dns-pihole."
        log_info "Valid actions: list, add, unregister-dns, interactive-add, interactive-unregister"
        return 1
    fi

    log_step "Managing Pi-hole DNS records (action: $action)..."
    
    # Get the domain suffix from environment or use default
    local domain_suffix="${CLUSTER_DOMAIN:-bevz.net}"
    
    # Check if debug flag is provided
    local debug_flag=""
    if [[ "$2" == "--debug" ]]; then
        debug_flag="--debug"
        log_debug "Running in debug mode"
    fi
    
    # Run the Python script with the appropriate action
    local repo_path
    repo_path=$(get_repo_path) || return 1
    
    "$repo_path/scripts/add_pihole_dns.py" --action "$action" --secrets-file "$repo_path/terraform/secrets.sops.yaml" --tf-dir "$repo_path/terraform" --domain-suffix "$domain_suffix" $debug_flag
    
    if [ $? -ne 0 ]; then
        log_error "Failed to execute dns-pihole action: $action"
        return 1
    fi
    
    log_success "Pi-hole DNS action '$action' completed successfully"
}

# Export Pi-hole functions
export -f pihole_dns_exec pihole_dns_list pihole_dns_add pihole_dns_remove
export -f pihole_dns_interactive_add pihole_dns_interactive_remove
export -f pihole_validate_connection cpc_dns_pihole
