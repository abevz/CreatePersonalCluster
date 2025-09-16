#!/bin/bash

# modules/80_ssh.sh - SSH Management Module
# Part of CPC (Create Personal Cluster) - Modular Architecture

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

#----------------------------------------------------------------------
# Main Dispatcher
#----------------------------------------------------------------------
cpc_ssh() {
  recovery_checkpoint "ssh_start" "Starting SSH operation: ${1:-}"

  case "${1:-}" in
  clear-ssh-hosts)
    shift
    ssh_clear_hosts "$@"
    ;;
  clear-ssh-maps)
    shift
    ssh_clear_maps "$@"
    ;;
  *)
    error_handle "$ERROR_INPUT" "Unknown SSH command: ${1:-}" "$SEVERITY_LOW" "abort"
    log_info "Available commands: clear-ssh-hosts, clear-ssh-maps"
    return 1
    ;;
  esac
}

#----------------------------------------------------------------------
# Main Functions
#----------------------------------------------------------------------

ssh_clear_hosts() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then ssh_show_hosts_help; return 0; fi
    recovery_checkpoint "ssh_clear_hosts_start" "Starting SSH known_hosts cleanup"

    local clear_all=false
    local dry_run=false
    for arg in "$@"; do
        case $arg in
            --all) clear_all=true; ;;
            --dry-run) dry_run=true; ;;
            *) error_handle "$ERROR_INPUT" "Unknown option: $arg" "$SEVERITY_LOW" "abort"; return 1; ;;
        esac
    done

    if [ ! -f ~/.ssh/known_hosts ]; then
        log_warning "No ~/.ssh/known_hosts file found. Nothing to clear."
        return 0
    fi

    local inventory_json
    inventory_json=$(_get_ansible_inventory_json)
    if [[ $? -ne 0 || -z "$inventory_json" ]]; then
        log_warning "Could not retrieve inventory information."
        return 1
    fi

    local -a all_ips
    mapfile -t all_ips < <(echo "$inventory_json" | jq -r '._meta.hostvars | .[].ansible_host')
    local -a all_hostnames
    mapfile -t all_hostnames < <(echo "$inventory_json" | jq -r '._meta.hostvars | keys_unsorted[]')

    local -a entries_to_clear
    entries_to_clear+=("${all_ips[@]}")
    entries_to_clear+=("${all_hostnames[@]}")

    local short_hostnames=()
    for hostname in "${all_hostnames[@]}"; do
        local short_name
        short_name=$(echo "$hostname" | cut -d. -f1 2>/dev/null || echo "")
        if [[ "$short_name" != "$hostname" && -n "$short_name" ]]; then
            short_hostnames+=("$short_name")
        fi
    done
    if [ ${#short_hostnames[@]} -gt 0 ]; then
        entries_to_clear+=("${short_hostnames[@]}")
    fi

    local -a unique_entries
    readarray -t unique_entries < <(printf '%s\n' "${entries_to_clear[@]}" | sort -u)

    if [ ${#unique_entries[@]} -eq 0 ]; then
        log_warning "No VM IPs or hostnames found to clear."
        return 1
    fi
    
    _ssh_remove_known_hosts_entries "$dry_run" "${unique_entries[@]}"
}

ssh_clear_maps() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then ssh_show_maps_help; return 0; fi
    recovery_checkpoint "ssh_clear_maps_start" "Starting SSH connections cleanup"

    local clear_all=false
    local dry_run=false
    for arg in "$@"; do
        case $arg in
            --all) clear_all=true; ;;
            --dry-run) dry_run=true; ;;
            *) error_handle "$ERROR_INPUT" "Unknown option: $arg" "$SEVERITY_LOW" "abort"; return 1; ;;
        esac
    done

    local inventory_json
    inventory_json=$(_get_ansible_inventory_json)
    if [[ $? -ne 0 || -z "$inventory_json" ]]; then
        log_warning "Could not retrieve inventory information."
        return 1
    fi

    local -a ips
    mapfile -t ips < <(echo "$inventory_json" | jq -r '._meta.hostvars | .[].ansible_host')

    if [ ${#ips[@]} -eq 0 ]; then
        log_warning "No VM IP addresses found to clear connections for."
        return 1
    fi

    _ssh_kill_vm_connections "$dry_run" "${ips[@]}"
    
    if [ "$dry_run" != true ]; then
        ssh_clear_control_sockets_all
    fi
    log_success "SSH connection cleanup completed."
}

#----------------------------------------------------------------------
# Helper Functions
#----------------------------------------------------------------------

_get_ansible_inventory_json() {
    local repo_root
    repo_root=$(get_repo_path)
    local inventory_script="$repo_root/ansible/inventory/tofu_inventory.py"
    if [ ! -x "$inventory_script" ]; then
        error_handle "$ERROR_CONFIG" "Inventory script not found or not executable: $inventory_script" "$SEVERITY_HIGH" "abort"
        return 1
    fi
    ANSIBLE_CACHE_PLUGIN_CONNECTION="$repo_root/ansible/.cache" "$inventory_script" --list
}

_ssh_remove_known_hosts_entries() {
    local dry_run=$1
    shift
    local -a entries_to_clear=("$@")

    log_info "VM entries to clear from ~/.ssh/known_hosts:"
    for item in "${entries_to_clear[@]}"; do log_info "  - $item"; done

    if [ "$dry_run" = true ]; then
        log_warning "Dry run mode. Will not remove entries."
        for item in "${entries_to_clear[@]}"; do
            grep -n "^$item[ ,]" ~/.ssh/known_hosts 2>/dev/null | sed 's/^/    /' || true
        done
        return 0
    fi

    local backup_file=~/.ssh/known_hosts.backup.$(date +%Y%m%d_%H%M%S)
    cp ~/.ssh/known_hosts "$backup_file"
    log_info "Created backup: $backup_file"

    local removed_count=0
    for item in "${entries_to_clear[@]}"; do
        if ssh-keygen -R "$item" &>/dev/null; then
            log_success "  Removed entries for $item"
            removed_count=$((removed_count + 1))
        fi
    done

    if [ $removed_count -gt 0 ]; then
        log_success "Successfully removed SSH known_hosts entries."
    else
        log_warning "No matching SSH known_hosts entries were found to remove."
        rm -f "$backup_file" 2>/dev/null || true
    fi
}

_ssh_kill_vm_connections() {
    local dry_run=$1
    shift
    local -a ips_to_clear=("$@")

    log_info "VM IPs to clear SSH connections for:"
    for ip in "${ips_to_clear[@]}"; do log_info "  - $ip"; done

    if [ "$dry_run" = true ]; then
        log_warning "Dry run mode - showing what would be cleared:"
        for ip in "${ips_to_clear[@]}"; do ssh_check_connections_for_ip "$ip" true; done
        return 0
    fi

    local cleared_count=0
    for ip in "${ips_to_clear[@]}"; do
        if ssh_kill_connections "$ip"; then cleared_count=$((cleared_count + 1)); fi
    done

    if [ $cleared_count -gt 0 ]; then
        log_success "Successfully cleared SSH connections for $cleared_count VMs."
    else
        log_warning "No active SSH connections found to clear."
    fi
}

ssh_check_connections_for_ip() {
  local ip="$1"
  local dry_run="${2:-false}"
  local active_connections
  active_connections=$(ps aux | grep -E "ssh.*$ip" | grep -v grep | grep -v "clear-ssh-maps" || true)

  if [ -n "$active_connections" ]; then
    if [ "$dry_run" = true ]; then
      log_warning "  Would kill SSH connections for $ip:"
      echo "$active_connections" | sed 's/^/    /'
    else
      log_info "  Found active SSH connections for $ip"
    fi
    return 0
  else
    log_info "  No active SSH connections found for $ip"
    return 1
  fi
}

ssh_kill_connections() {
  local ip="$1"
  if [[ -z "$ip" ]]; then return 1; fi
  log_info "Clearing SSH connections for $ip..."
  local ssh_pids
  ssh_pids=$(ps aux 2>/dev/null | grep -E "ssh.*$ip" | grep -v grep | grep -v "clear-ssh-maps" | awk '{print $2}' || true)

  if [ -n "$ssh_pids" ]; then
    for pid in $ssh_pids; do
      if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
        kill "$pid" 2>/dev/null && log_success "    Killed SSH process $pid for $ip"
      fi
    done
    return 0
  fi
  return 1
}

ssh_clear_control_sockets_all() {
  log_info "Clearing SSH control sockets..."
  local control_dirs=($HOME/.ssh/sockets $HOME/.ssh/master /tmp)
  local cleared_count=0
  for dir in "${control_dirs[@]}"; do
    if [ -d "$dir" ]; then
      local sockets
      sockets=$(find "$dir" -name "ssh-*" -type s 2>/dev/null || true)
      if [ -n "$sockets" ]; then
        while IFS= read -r socket; do
          if [ -S "$socket" ] && rm -f "$socket" 2>/dev/null;
            then
            log_success "  Removed control socket: $socket"
            cleared_count=$((cleared_count + 1))
          fi
        done <<<"$sockets"
      fi
    fi
  done
  if [ $cleared_count -gt 0 ]; then log_success "Cleared $cleared_count SSH control sockets"; fi
  return 0
}

ssh_show_hosts_help() {
  echo "Usage: cpc clear-ssh-hosts [--all] [--dry-run]"
  echo "Clears VM entries from ~/.ssh/known_hosts."
}

ssh_show_maps_help() {
  echo "Usage: cpc clear-ssh-maps [--all] [--dry-run]"
  echo "Clears active SSH connections and control sockets for VMs."
}

export -f cpc_ssh ssh_clear_hosts ssh_clear_maps
