#!/bin/bash

# modules/80_ssh.sh - SSH Management Module
# Part of CPC (Create Personal Cluster) - Modular Architecture
#
# This module provides comprehensive SSH management functionality for CPC clusters.
#
# Functions provided:
# - cpc_ssh()                    - Main entry point for ssh command
# - ssh_clear_hosts()            - Clear VM IP addresses from ~/.ssh/known_hosts
# - ssh_clear_maps()             - Clear SSH control sockets and connections for VMs
# - ssh_show_hosts_help()        - Display help for clear-ssh-hosts command
# - ssh_show_maps_help()         - Display help for clear-ssh-maps command
# - ssh_get_vm_ips_from_context() - Get VM IPs from a specific Tofu context
# - ssh_kill_connections()       - Kill active SSH connections for VMs
#
# Dependencies:
# - lib/logging.sh for logging functions
# - modules/00_core.sh for core utilities like get_repo_path, get_current_cluster_context
# - Terraform/OpenTofu state for VM IP discovery

#----------------------------------------------------------------------
# SSH Management Functions
#----------------------------------------------------------------------

# Main entry point for CPC SSH functionality
cpc_ssh() {
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
    log_error "Unknown SSH command: ${1:-}"
    log_info "Available commands: clear-ssh-hosts, clear-ssh-maps"
    return 1
    ;;
  esac
}

# Clear VM IP addresses from ~/.ssh/known_hosts
ssh_clear_hosts() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    ssh_show_hosts_help
    return 0
  fi

  # Parse command line arguments
  local clear_all=false
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case $1 in
    --all)
      clear_all=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      log_info "Use 'cpc clear-ssh-hosts --help' for usage information."
      return 1
      ;;
    esac
  done

  # Check if ~/.ssh/known_hosts exists
  if [ ! -f ~/.ssh/known_hosts ]; then
    log_warning "No ~/.ssh/known_hosts file found. Nothing to clear."
    return 0
  fi

  local current_ctx
  current_ctx=$(get_current_cluster_context) || return 1
  local repo_root
  repo_root=$(get_repo_path) || return 1

  log_info "Clearing SSH known_hosts entries for VM IP addresses..."

  # Collect all VM IPs to remove
  local vm_ips_to_clear=()
  local vm_hostnames_to_clear=()

  if [ "$clear_all" = true ]; then
    log_info "Collecting VM IPs from all contexts..."

    # Get all available workspaces
    pushd "$repo_root/terraform" >/dev/null || {
      log_error "Failed to access terraform directory"
      return 1
    }
    local workspaces
    workspaces=$(tofu workspace list | grep -v '^\*' | sed 's/^[ *]*//' | grep -v '^default$')
    popd >/dev/null

    for workspace in $workspaces; do
      log_info "  Checking context: $workspace"
      local ips
      ips=$(ssh_get_vm_ips_from_context "$workspace")
      if [ -n "$ips" ]; then
        while IFS= read -r ip; do
          if [ -n "$ip" ]; then
            vm_ips_to_clear+=("$ip")
          fi
        done <<<"$ips"
        log_info "    Found IPs: $(echo "$ips" | tr '\n' ' ')"
      else
        log_warning "    No VMs found in context '$workspace'"
      fi
    done
  else
    # --- НАЧАЛО ИСПРАВЛЕНИЯ ---
    log_info "Collecting VM info from Terraform output for context: $current_ctx"

    # 1. Получаем ВСЮ информацию одним вызовом
    local all_tf_outputs
    all_tf_outputs=$(_get_terraform_outputs_json)

    if [[ -z "$all_tf_outputs" || "$all_tf_outputs" == "null" ]]; then
      log_warning "No VM info found in Terraform output for context '${current_ctx}'"
      log_info "Make sure VMs are deployed with 'cpc deploy apply'"
      return 0
    fi

    # 2. Используем правильные, более точные jq запросы
    readarray -t vm_ips_to_clear < <(echo "$all_tf_outputs" | jq -r '.cluster_summary.value | .[].IP')
    readarray -t vm_hostnames_to_clear < <(echo "$all_tf_outputs" | jq -r '.cluster_summary.value | .[].hostname')

    log_info "  Found IPs: ${vm_ips_to_clear[*]}"
    log_info "  Found Hostnames: ${vm_hostnames_to_clear[*]}"
    # --- КОНЕЦ ИСПРАВЛЕНИЯ ---
  fi

  # Add short hostnames (without domain suffix)
  local short_hostnames=()
  for hostname in "${vm_hostnames_to_clear[@]}"; do
    local short_name
    short_name=$(echo "$hostname" | cut -d. -f1)
    if [[ "$short_name" != "$hostname" ]]; then
      short_hostnames+=("$short_name")
    fi
  done

  # Add short hostnames to the list
  if [ ${#short_hostnames[@]} -gt 0 ]; then
    vm_hostnames_to_clear+=("${short_hostnames[@]}")
  fi

  # Remove duplicates from IPs and hostnames
  vm_ips_to_clear=($(printf '%s\n' "${vm_ips_to_clear[@]}" | sort -u))
  vm_hostnames_to_clear=($(printf '%s\n' "${vm_hostnames_to_clear[@]}" | sort -u))

  if [ ${#vm_ips_to_clear[@]} -eq 0 ]; then
    log_warning "No VM IP addresses found to clear."
    return 0
  fi

  log_info "VM entries to clear from ~/.ssh/known_hosts:"
  log_info "  IP addresses:"
  for ip in "${vm_ips_to_clear[@]}"; do
    log_info "    - $ip"
  done

  log_info "  Hostnames:"
  for hostname in "${vm_hostnames_to_clear[@]}"; do
    log_info "    - $hostname"
  done

  if [ "$dry_run" = true ]; then
    log_warning "Dry run mode - showing what would be removed:"
    for ip in "${vm_ips_to_clear[@]}"; do
      local entries
      entries=$(grep -n "^$ip " ~/.ssh/known_hosts 2>/dev/null || true)
      if [ -n "$entries" ]; then
        log_warning "  Would remove entries for $ip:"
        echo "$entries" | sed 's/^/    /'
      else
        log_info "  No entries found for $ip"
      fi
    done
    log_info "Run without --dry-run to actually remove entries."
    return 0
  fi

  # Create backup of known_hosts
  local backup_file=~/.ssh/known_hosts.backup.$(date +%Y%m%d_%H%M%S)
  cp ~/.ssh/known_hosts "$backup_file"
  log_info "Created backup: $backup_file"

  # Remove entries using ssh-keygen -R for reliable removal
  local removed_count=0

  # For IPs
  for ip in "${vm_ips_to_clear[@]}"; do
    if ssh-keygen -R "$ip" &>/dev/null; then
      log_success "  Removed entries for IP $ip"
      removed_count=$((removed_count + 1))
    fi
  done

  # For hostnames
  for hostname in "${vm_hostnames_to_clear[@]}"; do
    # Skip empty hostnames
    [ -z "$hostname" ] && continue

    local output
    output=$(ssh-keygen -R "$hostname" 2>&1)
    if [ $? -eq 0 ] || [[ "$output" == *"Host $hostname found:"* ]]; then
      log_success "  Removed entries for hostname $hostname"
      removed_count=$((removed_count + 1))
    fi
  done

  if [ $removed_count -gt 0 ]; then
    log_success "Successfully removed $removed_count SSH known_hosts entries."
    log_info "Backup saved to: $backup_file"
  else
    log_warning "No SSH known_hosts entries were removed."
    # Remove backup if nothing was changed
    rm -f "$backup_file"
  fi

  log_success "SSH known_hosts cleanup completed."
}

# Clear SSH control sockets and connections for VMs
ssh_clear_maps() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    ssh_show_maps_help
    return 0
  fi

  # Parse command line arguments
  local clear_all=false
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case $1 in
    --all)
      clear_all=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      log_info "Use 'cpc clear-ssh-maps --help' for usage information."
      return 1
      ;;
    esac
  done

  local current_ctx
  current_ctx=$(get_current_cluster_context) || return 1
  local repo_root
  repo_root=$(get_repo_path) || return 1

  log_info "Clearing SSH control sockets and connections..."

  # Collect all VM IPs to clear connections for
  local vm_ips_to_clear=()

  if [ "$clear_all" = true ]; then
    log_info "Collecting VM IPs from all contexts..."

    # Get all available workspaces
    pushd "$repo_root/terraform" >/dev/null || {
      log_error "Failed to access terraform directory"
      return 1
    }
    local workspaces
    workspaces=$(tofu workspace list | grep -v '^\*' | sed 's/^[ *]*//' | grep -v '^default$')
    popd >/dev/null

    for workspace in $workspaces; do
      log_info "  Checking context: $workspace"
      local ips
      ips=$(ssh_get_vm_ips_from_context "$workspace")
      if [ -n "$ips" ]; then
        while IFS= read -r ip; do
          if [ -n "$ip" ]; then
            vm_ips_to_clear+=("$ip")
          fi
        done <<<"$ips"
        log_info "    Found IPs: $(echo "$ips" | tr '\n' ' ')"
      else
        log_warning "    No VMs found in context '$workspace'"
      fi
    done
  else
    log_info "Collecting VM IPs from current context: $current_ctx"
    local ips
    ips=$(ssh_get_vm_ips_from_context "$current_ctx")
    if [ -n "$ips" ]; then
      while IFS= read -r ip; do
        if [ -n "$ip" ]; then
          vm_ips_to_clear+=("$ip")
        fi
      done <<<"$ips"
      log_info "  Found IPs: $(echo "$ips" | tr '\n' ' ')"
    else
      log_warning "No VMs found in current context '$current_ctx'"
      log_info "Make sure VMs are deployed with 'cpc deploy apply'"
      return 0
    fi
  fi

  # Remove duplicates from IPs
  vm_ips_to_clear=($(printf '%s\n' "${vm_ips_to_clear[@]}" | sort -u))

  if [ ${#vm_ips_to_clear[@]} -eq 0 ]; then
    log_warning "No VM IP addresses found to clear connections for."
    return 0
  fi

  log_info "VM IPs to clear SSH connections for:"
  for ip in "${vm_ips_to_clear[@]}"; do
    log_info "  - $ip"
  done

  if [ "$dry_run" = true ]; then
    log_warning "Dry run mode - showing what would be cleared:"
    for ip in "${vm_ips_to_clear[@]}"; do
      ssh_check_connections_for_ip "$ip" true
    done
    log_info "Run without --dry-run to actually clear connections."
    return 0
  fi

  # Clear SSH connections and control sockets
  local cleared_count=0

  for ip in "${vm_ips_to_clear[@]}"; do
    if ssh_kill_connections "$ip"; then
      cleared_count=$((cleared_count + 1))
    fi
  done

  # Clear SSH control sockets
  ssh_clear_control_sockets_all

  if [ $cleared_count -gt 0 ]; then
    log_success "Successfully cleared SSH connections for $cleared_count VMs."
  else
    log_warning "No active SSH connections found to clear."
  fi

  log_success "SSH connection cleanup completed."
}

# Get VM IPs from a specific Tofu context
ssh_get_vm_ips_from_context() {
  local context="$1"
  local repo_root
  repo_root=$(get_repo_path)
  local terraform_dir="${repo_root}/terraform"

  pushd "$terraform_dir" >/dev/null || return 1

  local original_workspace
  original_workspace=$(tofu workspace show)

  # Убедимся, что мы в правильном воркспейсе
  if [[ "$original_workspace" != "$context" ]]; then
    tofu workspace select "$context" >/dev/null
  fi

  # ПРАВИЛЬНЫЙ ВЫЗОВ: используем cluster_summary и jq для извлечения IP
  local vm_ips
  vm_ips=$(tofu output -json cluster_summary | jq -r '.[].IP')

  # Возвращаемся в исходный воркспейс, если мы его меняли
  if [[ "$original_workspace" != "$context" ]]; then
    tofu workspace select "$original_workspace" >/dev/null
  fi

  popd >/dev/null || return 1

  # Проверка, что мы что-то получили
  if [[ -z "$vm_ips" ]]; then
    return 1
  fi

  echo "$vm_ips"
}

# Check SSH connections for a specific IP (with dry run option)
ssh_check_connections_for_ip() {
  local ip="$1"
  local dry_run="${2:-false}"

  # Check for active SSH connections
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

# Kill SSH connections for a specific IP
ssh_kill_connections() {
  local ip="$1"

  log_info "Clearing SSH connections for $ip..."

  # Check for active SSH connections first
  local active_connections
  active_connections=$(ps aux | grep -E "ssh.*$ip" | grep -v grep | grep -v "clear-ssh-maps" || true)

  if [ -n "$active_connections" ]; then
    log_info "  Found active SSH connections for $ip"

    # Get SSH process IDs for this IP
    local ssh_pids
    ssh_pids=$(ps aux | grep -E "ssh.*$ip" | grep -v grep | grep -v "clear-ssh-maps" | awk '{print $2}' || true)

    if [ -n "$ssh_pids" ]; then
      # Kill SSH processes
      for pid in $ssh_pids; do
        if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
          if kill "$pid" 2>/dev/null; then
            log_success "    Killed SSH process $pid for $ip"
          else
            log_warning "    Could not kill SSH process $pid for $ip"
          fi
        fi
      done
      return 0
    fi
  else
    log_info "  No active SSH connections found for $ip"
    return 1
  fi
}

# Clear all SSH control sockets
ssh_clear_control_sockets_all() {
  log_info "Clearing SSH control sockets..."

  # Common SSH control socket locations
  local control_dirs=(
    "$HOME/.ssh/sockets"
    "$HOME/.ssh/master"
    "/tmp"
  )

  local cleared_count=0

  for dir in "${control_dirs[@]}"; do
    if [ -d "$dir" ]; then
      # Find and remove SSH control sockets
      local sockets
      sockets=$(find "$dir" -name "ssh-*" -type s 2>/dev/null || true)
      if [ -n "$sockets" ]; then
        while IFS= read -r socket; do
          if [ -S "$socket" ]; then
            rm -f "$socket"
            log_success "  Removed control socket: $socket"
            cleared_count=$((cleared_count + 1))
          fi
        done <<<"$sockets"
      fi
    fi
  done

  if [ $cleared_count -gt 0 ]; then
    log_success "Cleared $cleared_count SSH control sockets"
  else
    log_info "No SSH control sockets found to clear"
  fi
}

# Display help for clear-ssh-hosts command
ssh_show_hosts_help() {
  echo "Usage: cpc clear-ssh-hosts [--all] [--dry-run]"
  echo ""
  echo "Clear VM IP addresses from ~/.ssh/known_hosts to resolve SSH key conflicts"
  echo "when VMs are recreated with the same IP addresses but new SSH keys."
  echo ""
  echo "Options:"
  echo "  --all       Clear all VM IPs from all contexts (not just current)"
  echo "  --dry-run   Show what would be removed without actually removing"
  echo ""
  echo "The command will:"
  echo "  1. Get VM IP addresses from current Terraform/Tofu outputs"
  echo "  2. Remove matching entries from ~/.ssh/known_hosts"
  echo "  3. Display summary of removed entries"
  echo ""
  echo "Example usage:"
  echo "  cpc clear-ssh-hosts           # Clear IPs from current context"
  echo "  cpc clear-ssh-hosts --all     # Clear IPs from all contexts"
  echo "  cpc clear-ssh-hosts --dry-run # Preview what would be removed"
}

# Display help for clear-ssh-maps command
ssh_show_maps_help() {
  echo "Usage: cpc clear-ssh-maps [--all] [--dry-run]"
  echo ""
  echo "Clear SSH control sockets and active connections for cluster VMs."
  echo "This helps resolve issues with stale SSH connections that can interfere"
  echo "with automation tasks."
  echo ""
  echo "Options:"
  echo "  --all       Clear SSH connections for all contexts (not just current)"
  echo "  --dry-run   Show what would be cleared without actually clearing"
  echo ""
  echo "The command will:"
  echo "  1. Get VM IP addresses from Terraform/Tofu outputs"
  echo "  2. Kill active SSH processes connected to those IPs"
  echo "  3. Remove SSH control sockets from common locations"
  echo "  4. Display summary of cleared connections"
  echo ""
  echo "Example usage:"
  echo "  cpc clear-ssh-maps           # Clear SSH connections for current context"
  echo "  cpc clear-ssh-maps --all     # Clear SSH connections for all contexts"
  echo "  cpc clear-ssh-maps --dry-run # Preview what would be cleared"
}

#----------------------------------------------------------------------
# Export functions for use by other modules
#----------------------------------------------------------------------
export -f cpc_ssh
export -f ssh_clear_hosts
export -f ssh_clear_maps
export -f ssh_get_vm_ips_from_context
export -f ssh_kill_connections
export -f ssh_clear_control_sockets_all
export -f ssh_show_hosts_help
export -f ssh_show_maps_help
export -f ssh_check_connections_for_ip

#----------------------------------------------------------------------
# Module help function
#----------------------------------------------------------------------
ssh_help() {
  echo "SSH Module (modules/80_ssh.sh)"
  echo "  clear-ssh-hosts [opts]     - Clear VM IPs from SSH known_hosts"
  echo "  clear-ssh-maps [opts]      - Clear SSH control sockets and connections"
  echo ""
  echo "Functions:"
  echo "  cpc_ssh()                       - Main SSH command dispatcher"
  echo "  ssh_clear_hosts()               - Clear SSH known_hosts entries for VMs"
  echo "  ssh_clear_maps()                - Clear SSH connections and control sockets"
  echo "  ssh_get_vm_ips_from_context()   - Get VM IPs from Tofu context"
  echo "  ssh_kill_connections()          - Kill SSH connections for specific IP"
  echo "  ssh_clear_control_sockets_all() - Clear all SSH control sockets"
}

export -f ssh_help
