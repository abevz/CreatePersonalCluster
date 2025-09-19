#!/bin/bash
# lib/tofu_node_helpers.sh - Helper functions for tofu_update_node_info() refactoring
# Part of the modular CPC architecture

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

# Module: Tofu node info helper functions
log_debug "Loading module: lib/tofu_node_helpers.sh - Tofu node info helper functions"

# validate_cluster_json() - Validates that the provided JSON is valid and contains expected structure
function validate_cluster_json() {
  local summary_json="$1"

  if [[ -z "$summary_json" || "$summary_json" == "null" ]]; then
    error_handle "$ERROR_INPUT" "Received empty or null JSON in validate_cluster_json" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Basic JSON validation
  if ! echo "$summary_json" | jq empty >/dev/null 2>&1; then
    error_handle "$ERROR_INPUT" "Invalid JSON provided to validate_cluster_json" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  log_debug "Cluster JSON validated successfully"
  return 0
}

# extract_node_names() - Extracts node names from the cluster JSON into an array
function extract_node_names() {
  local summary_json="$1"

  local node_names
  if ! node_names=$(echo "$summary_json" | jq -r 'keys_unsorted[]' 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to parse node names from JSON" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Convert to array
  local -a names_array=()
  while IFS= read -r name; do
    names_array+=("$name")
  done <<< "$node_names"

  if [ ${#names_array[@]} -eq 0 ]; then
    error_handle "$ERROR_EXECUTION" "Parsed zero node names from JSON" "$SEVERITY_MEDIUM" "abort"
    return 1
  fi

  log_debug "Extracted ${#names_array[@]} node names"

  # Return array as string representation
  printf '%q ' "${names_array[@]}"
  return 0
}

# extract_node_ips() - Extracts node IP addresses from the cluster JSON into an array
function extract_node_ips() {
  local summary_json="$1"

  local node_ips
  if ! node_ips=$(echo "$summary_json" | jq -r '.[].IP' 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to parse node IPs from JSON" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Convert to array
  local -a ips_array=()
  while IFS= read -r ip; do
    ips_array+=("$ip")
  done <<< "$node_ips"

  if [ ${#ips_array[@]} -eq 0 ]; then
    error_handle "$ERROR_EXECUTION" "Parsed zero node IPs from JSON" "$SEVERITY_MEDIUM" "abort"
    return 1
  fi

  log_debug "Extracted ${#ips_array[@]} node IPs"

  # Return array as string representation
  printf '%q ' "${ips_array[@]}"
  return 0
}

# extract_node_hostnames() - Extracts node hostnames from the cluster JSON into an array
function extract_node_hostnames() {
  local summary_json="$1"

  local node_hostnames
  if ! node_hostnames=$(echo "$summary_json" | jq -r '.[].hostname' 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to parse node hostnames from JSON" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Convert to array
  local -a hostnames_array=()
  while IFS= read -r hostname; do
    hostnames_array+=("$hostname")
  done <<< "$node_hostnames"

  if [ ${#hostnames_array[@]} -eq 0 ]; then
    error_handle "$ERROR_EXECUTION" "Parsed zero node hostnames from JSON" "$SEVERITY_MEDIUM" "abort"
    return 1
  fi

  log_debug "Extracted ${#hostnames_array[@]} node hostnames"

  # Return array as string representation
  printf '%q ' "${hostnames_array[@]}"
  return 0
}

# extract_node_vm_ids() - Extracts VM IDs from the cluster JSON into an array
function extract_node_vm_ids() {
  local summary_json="$1"

  local node_vm_ids
  if ! node_vm_ids=$(echo "$summary_json" | jq -r '.[].VM_ID' 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to parse node VM IDs from JSON" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  # Convert to array
  local -a vm_ids_array=()
  while IFS= read -r vm_id; do
    vm_ids_array+=("$vm_id")
  done <<< "$node_vm_ids"

  if [ ${#vm_ids_array[@]} -eq 0 ]; then
    error_handle "$ERROR_EXECUTION" "Parsed zero node VM IDs from JSON" "$SEVERITY_MEDIUM" "abort"
    return 1
  fi

  log_debug "Extracted ${#vm_ids_array[@]} node VM IDs"

  # Return array as string representation
  printf '%q ' "${vm_ids_array[@]}"
  return 0
}

log_debug "Module lib/tofu_node_helpers.sh loaded successfully"
