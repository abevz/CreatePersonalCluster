#!/bin/bash
# lib/tofu_env_helpers.sh - Helper functions for tofu_load_workspace_env_vars() refactoring
# Part of the modular CPC architecture

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

# Module: Tofu environment variable helper functions
log_debug "Loading module: lib/tofu_env_helpers.sh - Tofu environment variable helper functions"

# validate_env_file() - Validates that the environment file exists and is readable
function validate_env_file() {
  local env_file="$1"

  if [ ! -f "$env_file" ]; then
    log_debug "No environment file found at $env_file"
    return 1
  fi

  if [ ! -r "$env_file" ]; then
    error_handle "$ERROR_CONFIG" "Environment file exists but is not readable: $env_file" "$SEVERITY_MEDIUM" "abort"
    return 1
  fi

  log_debug "Environment file validated: $env_file"
  return 0
}

# parse_env_variables() - Parses key-value pairs from the environment file into a structured format
function parse_env_variables() {
  local env_file="$1"

  local var_name var_value line_count=0
  local -A env_vars

  while IFS='=' read -r var_name var_value; do
    line_count=$((line_count + 1))

    # Skip comments and empty lines
    [[ "$var_name" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$var_name" ]] && continue

    # Remove quotes from value
    var_value=$(echo "$var_value" | tr -d '"' 2>/dev/null || echo "")

    # Store in associative array
    env_vars["$var_name"]="$var_value"
  done < <(grep -E "^[A-Z_]+=" "$env_file" 2>/dev/null || true)

  if [ $line_count -eq 0 ]; then
    error_handle "$ERROR_CONFIG" "Environment file exists but contains no valid variables: $env_file" "$SEVERITY_LOW" "continue"
    return 1
  fi

  log_debug "Parsed $line_count environment variables from $env_file"

  # Return the associative array as a string representation
  declare -p env_vars
  return 0
}

# export_terraform_variables() - Exports parsed variables as Terraform environment variables with proper naming
function export_terraform_variables() {
  local env_vars_declaration="$1"

  # Source the associative array declaration
  eval "$env_vars_declaration"

  local exported_count=0

  # Export each variable with proper TF_VAR_ prefix
  for var_name in "${!env_vars[@]}"; do
    var_value="${env_vars[$var_name]}"

    case "$var_name" in
    RELEASE_LETTER)
      [ -n "$var_value" ] && export TF_VAR_release_letter="$var_value" && export RELEASE_LETTER="$var_value" && ((exported_count++))
      ;;
    ADDITIONAL_WORKERS)
      [ -n "$var_value" ] && export TF_VAR_additional_workers="$var_value" && ((exported_count++))
      ;;
    ADDITIONAL_CONTROLPLANES)
      [ -n "$var_value" ] && export TF_VAR_additional_controlplanes="$var_value" && ((exported_count++))
      ;;
    STATIC_IP_BASE)
      [ -n "$var_value" ] && export TF_VAR_static_ip_base="$var_value" && ((exported_count++))
      ;;
    STATIC_IP_GATEWAY)
      [ -n "$var_value" ] && export TF_VAR_static_ip_gateway="$var_value" && ((exported_count++))
      ;;
    STATIC_IP_START)
      [ -n "$var_value" ] && export TF_VAR_static_ip_start="$var_value" && ((exported_count++))
      ;;
    NETWORK_CIDR)
      [ -n "$var_value" ] && export TF_VAR_network_cidr="$var_value" && ((exported_count++))
      ;;
    WORKSPACE_IP_BLOCK_SIZE)
      [ -n "$var_value" ] && export TF_VAR_workspace_ip_block_size="$var_value" && ((exported_count++))
      ;;
    *)
      log_debug "Skipping unknown variable: $var_name"
      ;;
    esac
  done

  log_debug "Exported $exported_count Terraform variables"
  return 0
}

log_debug "Module lib/tofu_env_helpers.sh loaded successfully"
