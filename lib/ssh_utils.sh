#!/bin/bash
# =============================================================================
# CPC SSH Utilities Library
# =============================================================================
# Provides SSH-related utility functions

# --- SSH Management Functions ---

# Clear SSH known hosts for a specific host or pattern
ssh_clear_known_hosts() {
    local host_pattern="$1"
    
    if [ -z "$host_pattern" ]; then
        log_error "Usage: ssh_clear_known_hosts <host_pattern>"
        return 1
    fi
    
    if [ ! -f "$SSH_KNOWN_HOSTS_FILE" ]; then
        log_warning "SSH known_hosts file not found: $SSH_KNOWN_HOSTS_FILE"
        return 0
    fi
    
    log_step "Clearing SSH known hosts for pattern: $host_pattern"
    
    # Create backup
    cp "$SSH_KNOWN_HOSTS_FILE" "${SSH_KNOWN_HOSTS_FILE}.backup.$(date +%s)"
    
    # Remove matching entries
    ssh-keygen -R "$host_pattern" 2>/dev/null || true
    
    log_success "Cleared SSH known hosts for: $host_pattern"
}

# Clear SSH control sockets/connections
ssh_clear_control_sockets() {
    local host_pattern="$1"
    
    log_step "Clearing SSH control sockets..."
    
    # Default SSH control socket locations
    local control_dirs=(
        "$HOME/.ssh/sockets"
        "$HOME/.ssh/master"
        "/tmp/ssh-*"
    )
    
    for dir in "${control_dirs[@]}"; do
        if [ -d "$dir" ]; then
            if [ -n "$host_pattern" ]; then
                find "$dir" -name "*${host_pattern}*" -type s -delete 2>/dev/null || true
            else
                find "$dir" -type s -delete 2>/dev/null || true
            fi
        fi
    done
    
    log_success "Cleared SSH control sockets"
}

# Validate SSH connectivity to a host
ssh_test_connection() {
    local host="$1"
    local user="$2"
    local timeout="${3:-5}"
    
    if [ -z "$host" ]; then
        log_error "Usage: ssh_test_connection <host> [user] [timeout]"
        return 1
    fi
    
    local ssh_target="${user:+$user@}$host"
    
    log_debug "Testing SSH connection to: $ssh_target"
    
    if ssh -o ConnectTimeout="$timeout" \
           -o BatchMode=yes \
           -o StrictHostKeyChecking=no \
           "$ssh_target" "exit 0" 2>/dev/null; then
        log_success "SSH connection successful: $ssh_target"
        return 0
    else
        log_warning "SSH connection failed: $ssh_target"
        return 1
    fi
}

# Generate SSH config entry for a host
ssh_generate_config_entry() {
    local hostname="$1"
    local ip="$2"
    local user="$3"
    local key_file="$4"
    
    if [ -z "$hostname" ] || [ -z "$ip" ]; then
        log_error "Usage: ssh_generate_config_entry <hostname> <ip> [user] [key_file]"
        return 1
    fi
    
    echo "Host $hostname"
    echo "    HostName $ip"
    [ -n "$user" ] && echo "    User $user"
    [ -n "$key_file" ] && echo "    IdentityFile $key_file"
    echo "    StrictHostKeyChecking no"
    echo "    UserKnownHostsFile /dev/null"
    echo "    LogLevel ERROR"
    echo ""
}

# Add SSH config entry for a host
ssh_add_config_entry() {
    local hostname="$1"
    local ip="$2"
    local user="$3"
    local key_file="$4"
    
    if [ -z "$hostname" ] || [ -z "$ip" ]; then
        log_error "Usage: ssh_add_config_entry <hostname> <ip> [user] [key_file]"
        return 1
    fi
    
    log_step "Adding SSH config entry for: $hostname ($ip)"
    
    # Remove existing entry if it exists
    ssh_remove_config_entry "$hostname"
    
    # Add new entry
    {
        echo "# Added by CPC on $(date)"
        ssh_generate_config_entry "$hostname" "$ip" "$user" "$key_file"
    } >> "$SSH_CONFIG_FILE"
    
    log_success "Added SSH config entry for: $hostname"
}

# Remove SSH config entry for a host
ssh_remove_config_entry() {
    local hostname="$1"
    
    if [ -z "$hostname" ]; then
        log_error "Usage: ssh_remove_config_entry <hostname>"
        return 1
    fi
    
    if [ ! -f "$SSH_CONFIG_FILE" ]; then
        log_debug "SSH config file not found: $SSH_CONFIG_FILE"
        return 0
    fi
    
    log_debug "Removing SSH config entry for: $hostname"
    
    # Create backup
    cp "$SSH_CONFIG_FILE" "${SSH_CONFIG_FILE}.backup.$(date +%s)"
    
    # Remove entry (host block and following lines until next Host or end of file)
    awk -v host="$hostname" '
    /^Host / {
        if ($2 == host) {
            skip = 1
            next
        } else {
            skip = 0
        }
    }
    /^Host / && skip {
        skip = 0
    }
    !skip { print }
    ' "$SSH_CONFIG_FILE" > "${SSH_CONFIG_FILE}.tmp" && mv "${SSH_CONFIG_FILE}.tmp" "$SSH_CONFIG_FILE"
    
    log_debug "Removed SSH config entry for: $hostname"
}

# Comprehensive SSH cleanup for cluster nodes
ssh_cleanup_cluster() {
    local workspace="$1"
    local release_letter="$2"
    
    if [ -z "$workspace" ]; then
        log_error "Usage: ssh_cleanup_cluster <workspace> [release_letter]"
        return 1
    fi
    
    log_header "Cleaning up SSH entries for workspace: $workspace"
    
    # Patterns for cluster nodes
    local patterns=(
        "${release_letter:-}[cw][0-9]*"
        "*${workspace}*"
        "*.bevz.net"
    )
    
    for pattern in "${patterns[@]}"; do
        ssh_clear_known_hosts "$pattern"
        ssh_clear_control_sockets "$pattern"
    done
    
    log_success "SSH cleanup completed for workspace: $workspace"
}

# Main CPC SSH utilities dispatcher
cpc_ssh_utils() {
    local action="$1"
    shift
    
    case "$action" in
        "clear-hosts")
            ssh_clear_known_hosts "$@"
            ;;
        "clear-sockets")
            ssh_clear_control_sockets "$@"
            ;;
        "test")
            ssh_test_connection "$@"
            ;;
        "add-config")
            ssh_add_config_entry "$@"
            ;;
        "remove-config")
            ssh_remove_config_entry "$@"
            ;;
        "cleanup-cluster")
            ssh_cleanup_cluster "$@"
            ;;
        *)
            log_error "Unknown SSH utility action: $action"
            log_info "Available actions: clear-hosts, clear-sockets, test, add-config, remove-config, cleanup-cluster"
            return 1
            ;;
    esac
}

# Export SSH utility functions
export -f ssh_clear_known_hosts ssh_clear_control_sockets ssh_test_connection
export -f ssh_generate_config_entry ssh_add_config_entry ssh_remove_config_entry
export -f ssh_cleanup_cluster cpc_ssh_utils
