#!/bin/bash

# modules/20_ansible.sh - Ansible Playbook Management Module
# Part of CPC (Create Personal Cluster) - Modular Architecture
#
# This module provides Ansible playbook execution and inventory management functionality.
#
# Functions provided:
# - cpc_ansible()              - Main entry point for ansible command
# - ansible_run_playbook()     - Execute Ansible playbooks with proper inventory and context
# - ansible_show_help()        - Display help for run-ansible command
# - ansible_list_playbooks()   - List available playbooks in the repository
# - ansible_update_inventory_cache() - Update inventory cache from Terraform state
#
# Dependencies:
# - lib/logging.sh for logging functions
# - modules/00_core.sh for core utilities like get_repo_path, get_current_cluster_context
# - Ansible installation and proper ansible.cfg configuration
# - Terraform/OpenTofu state for inventory generation

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

#----------------------------------------------------------------------
# Ansible Playbook Management Functions
#----------------------------------------------------------------------

# Main entry point for CPC ansible functionality
cpc_ansible() {
  case "${1:-}" in
  run-ansible)
    shift
    ansible_run_playbook_command "$@"
    ;;
  run-command)
    shift
    if [[ "$1" == "-h" || "$1" == "--help" ]] || [[ $# -lt 2 ]]; then
      ansible_show_run_command_help
      return 0
    fi
    ansible_run_shell_command "$@"
    ;;
  update-inventory)
    shift
    ansible_update_inventory_cache_advanced "$@"
    ;;
  *)
    log_error "Unknown ansible command: ${1:-}"
    log_info "Available commands: run-ansible, run-command, update-inventory"
    return 1
    ;;
  esac
}

# Handle the run-ansible command with help and validation
ansible_run_playbook_command() {
  if [[ "$1" == "-h" || "$1" == "--help" ]] || [[ $# -eq 0 ]]; then
    ansible_show_help
    return 0
  fi

  local playbook_name="$1"
  shift # Remove playbook name, rest are ansible options

  # Validate playbook exists
  local repo_path
  repo_path=$(get_repo_path) || return 1
  local playbook_path="$repo_path/ansible/playbooks/$playbook_name"

  if [[ ! -f "$playbook_path" ]]; then
    log_error "Playbook '$playbook_name' not found at $playbook_path"
    log_info "Available playbooks:"
    ansible_list_playbooks
    return 1
  fi

  log_info "Running Ansible playbook: $playbook_name"
  ansible_run_playbook "$playbook_name" "$@"
}

# Display help information for the run-ansible command
ansible_show_help() {
  echo "Usage: cpc run-ansible <playbook_name> [ansible_options]"
  echo ""
  echo "Runs the specified Ansible playbook from the ansible/playbooks/ directory"
  echo "using the current cpc context for inventory and configuration."
  echo ""
  echo "Key features:"
  echo "  - Automatically uses the Tofu inventory for the current context"
  echo "  - Sets ansible_user from ansible.cfg configuration"
  echo "  - Passes current cluster context and Kubernetes version as variables"
  echo "  - Uses SSH settings optimized for VM connections"
  echo ""
  echo "Examples:"
  echo "  cpc run-ansible initialize_kubernetes_cluster_with_dns.yml"
  echo "  cpc run-ansible regenerate_certificates_with_dns.yml"
  echo "  cpc run-ansible deploy_kubernetes_cluster.yml"
  echo "  cpc run-ansible bootstrap_master_node.yml --check"
  echo ""
  echo "Available playbooks (run 'ls \$REPO_PATH/ansible/playbooks/' to see all):"
  ansible_list_playbooks
}

# List available Ansible playbooks in the repository
ansible_list_playbooks() {
  local repo_path
  repo_path=$(get_repo_path) || return 1

  if [ -d "$repo_path/ansible/playbooks" ]; then
    ls "$repo_path/ansible/playbooks"/*.yml "$repo_path/ansible/playbooks"/*.yaml 2>/dev/null | xargs -n1 basename | sed 's/^/  - /' || log_warning "No playbooks found in $repo_path/ansible/playbooks"
  else
    log_warning "Ansible playbooks directory not found at $repo_path/ansible/playbooks"
  fi
}

# Execute a shell command on target hosts using Ansible
ansible_run_shell_command() {
  if [[ $# -lt 2 ]]; then
    ansible_show_run_command_help
    return 1
  fi

  local target="$1"
  local shell_cmd="$2"

  log_info "Running command on $target: $shell_cmd"
  ansible_run_playbook "pb_run_command.yml" -l "$target" -e "command_to_run=$shell_cmd"
}

# Display help information for the run-command function
ansible_show_run_command_help() {
  echo "Usage: cpc run-command <target_hosts_or_group> \"<shell_command_to_run>\""
  echo ""
  echo "Runs a shell command on specified hosts or groups using Ansible."
  echo ""
  echo "Parameters:"
  echo "  target_hosts_or_group   - Target hosts or inventory groups"
  echo "  shell_command_to_run    - Shell command to execute"
  echo ""
  echo "Examples:"
  echo "  cpc run-command control_plane \"hostname -f\""
  echo "  cpc run-command all \"sudo apt update\""
  echo "  cpc run-command workers \"systemctl status kubelet\""
  echo ""
  echo "Available target groups: all, control_plane, workers"
}

# Execute Ansible playbooks with proper context and inventory

# modules/20_ansible.sh

function ansible_run_playbook() {
  local playbook_name=$1
  shift
  
  # Prepare inventory
  local temp_inventory_file
  temp_inventory_file=$(ansible_prepare_inventory "$@")
  if [[ $? -ne 0 ]]; then
    return 1
  fi
  
  # Add temporary inventory to arguments if it was created
  if [[ -n "$temp_inventory_file" ]]; then
    set -- "$@" -i "$temp_inventory_file"
  fi
  
  # Load environment variables
  local env_vars
  env_vars=$(ansible_load_environment_variables)
  
  # Prepare secret variables
  local secret_vars
  secret_vars=$(ansible_prepare_secret_variables)
  
  # Construct command array - pass all remaining args as separate parameters
  local cmd_array
  ansible_construct_command_array cmd_array "$playbook_name" "$temp_inventory_file" "$env_vars" "$secret_vars" "$@"
  
  # Execute command
  ansible_execute_command cmd_array "$playbook_name"
  local result=$?
  
  # Clean up temporary files
  ansible_cleanup_temp_files "$temp_inventory_file"
  
  return $result
}

# ansible_execute_command() - Execute ansible command with proper error handling
function ansible_execute_command() {
  local -n cmd_array_ref=$1  # nameref parameter
  local playbook_name="$2"
  local repo_root
  repo_root=$(get_repo_path)
  local ansible_dir="$repo_root/ansible"
  
  log_info "Running: ${cmd_array_ref[*]}"

  pushd "$ansible_dir" >/dev/null || {
    error_handle "$ERROR_EXECUTION" "Failed to change to ansible directory: $ansible_dir" "$SEVERITY_HIGH"
    return 1
  }

  # Create command string safely
  local cmd_str
  printf -v cmd_str '%q ' "${cmd_array_ref[@]}"
  cmd_str=${cmd_str% }  # Remove trailing space
  
  if eval "$cmd_str"; then
    log_success "Ansible playbook $playbook_name completed successfully"
    return 0
  else
    local exit_code=$?
    log_error "Ansible playbook $playbook_name failed (exit code: $exit_code)"
    return $exit_code
  fi

  popd >/dev/null
}

# Update Ansible inventory cache from Terraform state
ansible_update_inventory_cache() {
  log_info "Updating inventory cache..."
  
  # Get cluster summary
  local cluster_summary
  cluster_summary=$(ansible_get_cluster_summary)
  
  # Create basic inventory if cluster summary was retrieved
  if [[ -n "$cluster_summary" ]]; then
    ansible_create_basic_inventory "$cluster_summary"
  fi
}

# Advanced inventory cache update with comprehensive cluster information
ansible_update_inventory_cache_advanced() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: cpc update-inventory"
    echo ""
    echo "Update the Ansible inventory cache from current cluster state."
    echo "This command fetches the latest cluster information and updates"
    echo "the inventory cache file used by Ansible playbooks."
    echo ""
    echo "This is automatically called before Ansible operations, but can be"
    echo "run manually to troubleshoot inventory issues."
    return 0
  fi

  log_info "Updating Ansible inventory cache..."

  # Validate terraform directory
  if ! ansible_validate_terraform_directory; then
    return 1
  fi

  # Setup AWS credentials
  ansible_setup_aws_credentials

  # Fetch cluster information
  local cluster_summary
  cluster_summary=$(ansible_fetch_cluster_information)
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  # Generate inventory JSON
  local inventory_json
  inventory_json=$(ansible_generate_inventory_json "$cluster_summary")

  # Write inventory cache
  ansible_write_inventory_cache "$inventory_json"
}

#----------------------------------------------------------------------
# Helper Functions for Refactoring
#----------------------------------------------------------------------

# ansible_create_temp_inventory() - Create temporary inventory file
# This function was called but not defined - creating it now
function ansible_create_temp_inventory() {
  local temp_file
  temp_file=$(mktemp /tmp/ansible_inventory_XXXXXX.ini)
  
  if [[ $? -ne 0 ]]; then
    log_error "Failed to create temporary file for inventory"
    return 1
  fi
  
  # Use the advanced inventory cache update to populate the temp file
  local repo_root
  repo_root=$(get_repo_path) || return 1
  local cache_file="$repo_root/.ansible_inventory_cache.json"
  
  if [[ -f "$cache_file" ]]; then
    # Convert JSON cache to INI format for ansible-playbook with host variables
    {
      echo "[all:vars]"
      echo "ansible_python_interpreter=/usr/bin/python3"
      echo ""
      echo "[control_plane]"
      # Add control plane hosts with their variables
      jq -r '.control_plane.hosts[]' "$cache_file" 2>/dev/null | while read -r host; do
        echo "$host"
        # Add host-specific variables
        jq -r --arg host "$host" '._meta.hostvars[$host] | to_entries[] | "\($host) \(.key)=\(.value)"' "$cache_file" 2>/dev/null
      done
      echo ""
      echo "[workers]"
      # Add worker hosts with their variables
      jq -r '.workers.hosts[]' "$cache_file" 2>/dev/null | while read -r host; do
        echo "$host"
        # Add host-specific variables
        jq -r --arg host "$host" '._meta.hostvars[$host] | to_entries[] | "\($host) \(.key)=\(.value)"' "$cache_file" 2>/dev/null
      done
    } > "$temp_file"
  else
    log_warning "No inventory cache found, creating basic inventory"
    # Create basic inventory if cache doesn't exist
    {
      echo "[all:vars]"
      echo "ansible_python_interpreter=/usr/bin/python3"
      echo ""
      echo "[control_plane]"
      echo "# Add control plane nodes here"
      echo ""
      echo "[workers]"
      echo "# Add worker nodes here"
    } > "$temp_file"
  fi
  
  echo "$temp_file"
}

# ansible_create_basic_inventory() - Create basic inventory structure from cluster summary
function ansible_create_basic_inventory() {
  local cluster_summary="$1"
  local repo_root
  repo_root=$(get_repo_path) || return 1
  local cache_file="$repo_root/.ansible_inventory_cache.json"

  if [ -n "$cluster_summary" ]; then
    # Generate inventory from cluster_summary
    local inventory_json
    inventory_json=$(echo "$cluster_summary" | jq '{
              "_meta": {
                  "hostvars": (
                      to_entries | map({
                          key: .value.IP,
                          value: {
                              "ansible_host": .value.IP,
                              "node_name": .key,
                              "hostname": .value.hostname,
                              "vm_id": .value.VM_ID,
                              "k8s_role": (if (.key | contains("controlplane")) then "control-plane" else "worker" end)
                          }
                      }) | from_entries
                  )
              },
              "all": {
                  "children": ["control_plane", "workers"]
              },
              "control_plane": {
                  "hosts": [to_entries | map(select(.key | contains("controlplane")) | .value.IP) | .[]]
              },
              "workers": {
                  "hosts": [to_entries | map(select(.key | contains("worker")) | .value.IP) | .[]]
              }
          }')

    # Write to cache file
    echo "$inventory_json" >"$cache_file"
    log_success "Inventory cache updated"
  fi
}

# ansible_prepare_inventory() - Create temporary inventory file if not provided by user
function ansible_prepare_inventory() {
  local temp_inventory_file=""
  
  # If there is no inventory (-i) in arguments, create temporary
  if ! [[ "$*" =~ -i ]]; then
    temp_inventory_file=$(ansible_create_temp_inventory)
    if [[ $? -ne 0 || -z "$temp_inventory_file" ]]; then
      log_error "Failed to create temporary Ansible inventory."
      return 1
    fi
  fi
  
  echo "$temp_inventory_file"
}

# ansible_load_environment_variables() - Load environment variables from context-specific .env file
function ansible_load_environment_variables() {
  local repo_root
  repo_root=$(get_repo_path)
  local current_ctx
  current_ctx=$(get_current_cluster_context)
  local env_file="$repo_root/envs/$current_ctx.env"
  local env_vars=()

  if [[ -f "$env_file" ]]; then
    log_debug "Loading variables from $env_file for Ansible..."
    while IFS= read -r line; do
      # Skip empty lines and lines starting with #
      [[ -n "$line" && ! "$line" =~ ^\s*# ]] || continue
      
      # Remove inline comments (everything after #)
      line="${line%%#*}"
      # Trim whitespace
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      
      # Only add non-empty lines
      [[ -n "$line" ]] && env_vars+=("$line")
    done <"$env_file"
  fi
  
  # Return the array (this will be captured as a string, but we'll handle it differently)
  echo "${env_vars[@]}"
}

# ansible_prepare_secret_variables() - Prepare secret variables for Ansible execution
function ansible_prepare_secret_variables() {
  # List of secrets that will be automatically passed to Ansible if they exist in the environment.
  # They are loaded by the load_secrets function from 00_core.sh
  local secret_vars_to_pass=(
    "HARBOR_HOSTNAME"
    "HARBOR_ROBOT_USERNAME"
    "HARBOR_ROBOT_TOKEN"
    "DOCKER_HUB_USERNAME"
    "DOCKER_HUB_PASSWORD"
    # Add other secrets here if needed in Ansible
  )

  local secret_vars=()
  log_debug "Adding secrets from environment to Ansible command..."
  for var_name in "${secret_vars_to_pass[@]}"; do
    # The construction ${!var_name} is an indirect reference to the variable's value.
    if [[ -n "${!var_name}" ]]; then
      # Pass the variable to Ansible. Ansible prefers lowercase variables.
      local ansible_var_name
      ansible_var_name=$(echo "$var_name" | tr '[:upper:]' '[:lower:]')
      secret_vars+=("$ansible_var_name=${!var_name}")
      log_debug "  -> Passing secret: $ansible_var_name"
    fi
  done
  
  echo "${secret_vars[@]}"
}

# ansible_construct_command_array() - Build the final ansible-playbook command array
function ansible_construct_command_array() {
  local -n _result=$1  # nameref parameter
  local playbook_name="$2"
  local temp_inventory_file="$3"
  local env_vars="$4"
  local secret_vars="$5"
  shift 5  # Remove the first 5 parameters
  
  local repo_root
  repo_root=$(get_repo_path)
  local ansible_dir="$repo_root/ansible"
  
  _result=("ansible-playbook" "playbooks/$playbook_name")
  
  # Add SSH extra args as separate arguments
  _result+=("--ssh-extra-args")
  _result+=("-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")
  
  # Add environment variables (split the string into array)
  if [[ -n "$env_vars" ]]; then
    read -ra env_array <<< "$env_vars"
    for var in "${env_array[@]}"; do
      _result+=("-e" "$var")
    done
  fi
  
  # Add secret variables (split the string into array)
  if [[ -n "$secret_vars" ]]; then
    read -ra secret_array <<< "$secret_vars"
    for var in "${secret_array[@]}"; do
      _result+=("-e" "$var")
    done
  fi
  
  # Add ansible_user
  local ansible_user
  ansible_user=$(grep -Po '^remote_user\s*=\s*\K.*' "$ansible_dir/ansible.cfg")
  _result+=("-e" "ansible_user=$ansible_user")
  
  # Add temporary inventory if it exists
  if [[ -n "$temp_inventory_file" ]]; then
    _result+=("-i" "$temp_inventory_file")
  fi
  
  # Process remaining user-provided arguments
  local ansible_flags=("-h" "--help" "-v" "--verbose" "-C" "--check" "-D" "--diff" 
                      "-b" "--become" "-K" "--ask-become-pass" "-k" "--ask-pass"
                      "-t" "--tags" "--skip-tags" "-l" "--limit" "-f" "--forks"
                      "-u" "--user" "-c" "--connection" "-T" "--timeout"
                      "--step" "--syntax-check" "--list-tasks" "--list-tags" "--list-hosts")
  
  while [[ $# -gt 0 ]]; do
    arg="$1"
    if [[ "$arg" =~ ^[A-Z_]+=.+ ]]; then
      # This looks like a key=value variable, add -e prefix
      _result+=("-e" "$arg")
    elif [[ " ${ansible_flags[*]} " =~ " $arg " ]]; then
      # This is a known ansible flag
      _result+=("$arg")
    else
      # Unknown argument, add it as-is (might be a value for a previous flag)
      _result+=("$arg")
    fi
    shift
  done
}

# ansible_cleanup_temp_files() - Clean up temporary files created during execution
function ansible_cleanup_temp_files() {
  local temp_inventory_file="$1"
  
  # Remove temporary inventory if it was created
  if [[ -n "$temp_inventory_file" ]]; then
    rm "$temp_inventory_file"
  fi
}

# ansible_validate_terraform_directory() - Validate that terraform directory exists and is accessible
function ansible_validate_terraform_directory() {
  local repo_root
  repo_root=$(get_repo_path) || return 1
  local terraform_dir="$repo_root/terraform"

  if [ ! -d "$terraform_dir" ]; then
    log_error "terraform directory not found at $terraform_dir"
    return 1
  fi
  
  return 0
}

# ansible_setup_aws_credentials() - Set up AWS credentials for terraform backend access
function ansible_setup_aws_credentials() {
  # Export AWS credentials for terraform backend (needed for tofu output)
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
  export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
}

#----------------------------------------------------------------------
# Module help function
#----------------------------------------------------------------------
ansible_help() {
  echo "Ansible Module (modules/20_ansible.sh)"
  echo "  run-ansible <playbook> [opts] - Execute Ansible playbook with context"
  echo "  update-inventory              - Update inventory cache from cluster state"
  echo ""
  echo "Functions:"
  echo "  cpc_ansible()                          - Main ansible command dispatcher"
  echo "  ansible_run_playbook()                 - Execute playbooks with inventory and context"
  echo "  ansible_show_help()                    - Display run-ansible help"
  echo "  ansible_list_playbooks()               - List available playbooks"
  echo "  ansible_update_inventory_cache()       - Update inventory cache from Terraform"
  echo "  ansible_update_inventory_cache_advanced() - Advanced inventory update with cluster info"
}

#----------------------------------------------------------------------
# Missing Helper Functions (created during refactoring)
#----------------------------------------------------------------------

# ansible_get_cluster_summary() - Get cluster summary from terraform output
function ansible_get_cluster_summary() {
  local repo_root
  repo_root=$(get_repo_path) || return 1
  local terraform_dir="$repo_root/terraform"

  if [ -d "$terraform_dir" ]; then
    pushd "$terraform_dir" >/dev/null || {
      log_error "Failed to change to terraform directory: $terraform_dir"
      return 1
    }

    local cluster_summary
    cluster_summary=$(tofu output -json cluster_summary 2>/dev/null | jq -r '.value // empty')

    if [ -n "$cluster_summary" ]; then
      popd >/dev/null || true
      echo "$cluster_summary"
      return 0
    else
      log_warning "Could not get cluster_summary from terraform, using existing cache"
      popd >/dev/null || true
      return 1
    fi
  else
    log_warning "Terraform directory not found at $terraform_dir"
    return 1
  fi
}

# ansible_fetch_cluster_information() - Retrieve cluster information from tofu/terraform
function ansible_fetch_cluster_information() {
  local repo_root
  repo_root=$(get_repo_path) || return 1
  local terraform_dir="$repo_root/terraform"

  if [ -d "$terraform_dir" ]; then
    pushd "$terraform_dir" >/dev/null || {
      log_error "Failed to change to terraform directory: $terraform_dir"
      return 1
    }

    local cluster_info
    cluster_info=$(tofu output -json cluster_info 2>/dev/null | jq -r '.value // empty')

    if [ -n "$cluster_info" ]; then
      popd >/dev/null || true
      echo "$cluster_info"
      return 0
    else
      log_error "Could not get cluster_info from terraform"
      popd >/dev/null || true
      return 1
    fi
  else
    log_error "Terraform directory not found at $terraform_dir"
    return 1
  fi
}

# ansible_generate_inventory_json() - Transform cluster summary into Ansible inventory JSON
function ansible_generate_inventory_json() {
  local cluster_summary="$1"
  
  if [ -z "$cluster_summary" ]; then
    log_error "No cluster summary provided"
    return 1
  fi
  
  # Generate inventory JSON from cluster summary
  local inventory_json
  inventory_json=$(echo "$cluster_summary" | jq '{
            "_meta": {
                "hostvars": (
                    to_entries | map({
                        key: .value.IP,
                        value: {
                            "ansible_host": .value.IP,
                            "node_name": .key,
                            "hostname": .value.hostname,
                            "vm_id": .value.VM_ID,
                            "k8s_role": (if (.key | contains("controlplane")) then "control-plane" else "worker" end)
                        }
                    }) | from_entries
                )
            },
            "all": {
                "children": ["control_plane", "workers"]
            },
            "control_plane": {
                "hosts": [to_entries | map(select(.key | contains("controlplane")) | .value.IP) | .[]]
            },
            "workers": {
                "hosts": [to_entries | map(select(.key | contains("worker")) | .value.IP) | .[]]
            }
        }')

  echo "$inventory_json"
}

# ansible_write_inventory_cache() - Write inventory JSON to cache file
function ansible_write_inventory_cache() {
  local inventory_json="$1"
  local repo_root
  repo_root=$(get_repo_path) || return 1
  local cache_file="$repo_root/.ansible_inventory_cache.json"

  # Write to cache file
  echo "$inventory_json" >"$cache_file"

  log_success "Ansible inventory cache updated at $cache_file"
  log_info "Inventory contents:"
  jq '.' "$cache_file"
}
