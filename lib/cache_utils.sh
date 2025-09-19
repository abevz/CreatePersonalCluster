#!/bin/bash
# =============================================================================
# CPC Cache Utilities Library (cache_utils.sh)
# =============================================================================
# Cache management utilities for CPC

# Ensure this library is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This library should not be run directly. Use the main cpc script." >&2
  exit 1
fi

#----------------------------------------------------------------------
# Cache Utility Functions
#----------------------------------------------------------------------

# check_cache_freshness() - Determines if the cached secrets are still valid
function check_cache_freshness() {
  local cache_file="$1"
  local secrets_file="$2"
  
  if [[ ! -f "$cache_file" || ! -f "$secrets_file" ]]; then
    echo "missing"
    return 1
  fi
  
  local cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
  local secrets_mtime=$(stat -c %Y "$secrets_file" 2>/dev/null || echo 0)
  
  if [[ $secrets_mtime -gt $cache_mtime ]]; then
    echo "stale"
    return 1
  fi
  
  echo "fresh"
  return 0
}

# update_cache_timestamp() - Updates the cache file with the latest secrets and timestamp
function update_cache_timestamp() {
  local cache_file="$1"
  local data="$2"
  
  echo "$data" > "$cache_file"
  echo "# Cache updated: $(date)" >> "$cache_file"
  log_debug "Updated cache file: $cache_file"
}

# clear_all_caches() - Clears all CPC cache files (renamed from core_clear_cache)
function clear_all_caches() {
  local cache_files=(
    "/tmp/cpc_secrets_cache"
    "/tmp/cpc_env_cache.sh"
    "/tmp/cpc_status_cache"
    "/tmp/cpc_ssh_cache"
    "/tmp/cpc_*_cache*"
  )
  
  for cache_file in "${cache_files[@]}"; do
    if [[ -f "$cache_file" ]]; then
      rm -f "$cache_file"
      log_debug "Removed cache file: $cache_file"
    elif [[ "$cache_file" == *'*' ]]; then
      # Handle glob patterns
      rm -f $cache_file 2>/dev/null || true
      log_debug "Removed cache files matching: $cache_file"
    fi
  done
  
  log_success "All caches cleared successfully"
}
