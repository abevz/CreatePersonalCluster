#!/bin/bash
# =============================================================================
# CPC General Utilities Library (utils.sh)
# =============================================================================
# General-purpose utility functions for CPC

# Ensure this library is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This library should not be run directly. Use the main cpc script." >&2
  exit 1
fi

#----------------------------------------------------------------------
# General Utility Functions
#----------------------------------------------------------------------

# validate_workspace_name() - Validates that a workspace name follows the required pattern
function validate_workspace_name() {
  local workspace_name="$1"
  
  # Check length (1-50 characters)
  if [[ ${#workspace_name} -lt 1 || ${#workspace_name} -gt 50 ]]; then
    log_error "Workspace name must be between 1 and 50 characters"
    return 1
  fi
  
  # Check pattern (alphanumeric, hyphens, underscores only)
  if [[ ! "$workspace_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Workspace name can only contain letters, numbers, hyphens, and underscores"
    return 1
  fi
  
  # Check for reserved names
  local reserved_names=("default" "null" "none" "test" "temp" "tmp")
  for reserved in "${reserved_names[@]}"; do
    if [[ "$workspace_name" == "$reserved" ]]; then
      log_error "Workspace name '$workspace_name' is reserved"
      return 1
    fi
  done
  
  return 0
}
