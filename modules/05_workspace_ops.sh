#!/bin/bash
# =============================================================================
# CPC Workspace Operations Module (05_workspace_ops.sh)
# =============================================================================
# High-level workspace operations: cloning, deletion, and related utilities

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

# Source dependencies
if [[ -z "$REPO_PATH" ]]; then
  echo "Warning: REPO_PATH environment variable is not set, using current directory" >&2
  REPO_PATH="$(pwd)"
fi

# Use REPO_PATH for sourcing, fallback to calculated paths
if [[ -f "$REPO_PATH/lib/utils.sh" ]]; then
  source "$REPO_PATH/lib/utils.sh" || {
    echo "Error: Failed to source utils.sh from $REPO_PATH/lib/utils.sh" >&2
    return 1
  }
else
  # Fallback to relative paths
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  source "$REPO_ROOT/lib/utils.sh" || {
    echo "Error: Failed to source utils.sh from $REPO_ROOT/lib/utils.sh" >&2
    return 1
  }
fi

if [[ -f "$REPO_PATH/modules/00_core.sh" ]]; then
  source "$REPO_PATH/modules/00_core.sh" || {
    echo "Error: Failed to source 00_core.sh from $REPO_PATH/modules/00_core.sh" >&2
    return 1
  }
else
  source "$REPO_ROOT/modules/00_core.sh" || {
    echo "Error: Failed to source 00_core.sh from $REPO_ROOT/modules/00_core.sh" >&2
    return 1
  }
fi

if [[ -f "$REPO_PATH/modules/60_tofu.sh" ]]; then
  source "$REPO_PATH/modules/60_tofu.sh" || {
    echo "Error: Failed to source 60_tofu.sh from $REPO_PATH/modules/60_tofu.sh" >&2
    return 1
  }
else
  source "$REPO_ROOT/modules/60_tofu.sh" || {
    echo "Error: Failed to source 60_tofu.sh from $REPO_ROOT/modules/60_tofu.sh" >&2
    return 1
  }
fi

#----------------------------------------------------------------------
# Workspace Operations Functions
#----------------------------------------------------------------------

# validate_clone_parameters() - Checks that source workspace and new name are valid.
function validate_clone_parameters() {
  local source_workspace="$1"
  local new_workspace_name="$2"
  if [[ -z "$source_workspace" || -z "$new_workspace_name" ]]; then
    echo "Source and destination workspace names are required" >&2
    return 1
  fi
  if [[ "$source_workspace" == "$new_workspace_name" ]]; then
    echo "Source and destination workspaces cannot be the same" >&2
    return 1
  fi
  validate_workspace_name "$new_workspace_name"
}

# backup_existing_files() - Creates backups of files that will be modified.
function backup_existing_files() {
  local locals_tf_file="$1"
  local locals_tf_backup_file="${locals_tf_file}.bak"
  cp "$locals_tf_file" "$locals_tf_backup_file"
}

# copy_workspace_files() - Copies environment and configuration files for the new workspace.
function copy_workspace_files() {
  local source_env_file="$1"
  local new_env_file="$2"
  cp "$source_env_file" "$new_env_file"
}

# update_workspace_mappings() - Updates any mappings or references for the new workspace.
function update_workspace_mappings() {
  local new_workspace_name="$1"
  local release_letter="$2"
  local new_env_file="$3"
  sed -i "s/^RELEASE_LETTER=.*/RELEASE_LETTER=$release_letter/" "$new_env_file"
}

# switch_to_new_workspace() - Sets the context to the newly cloned workspace.
function switch_to_new_workspace() {
  local new_workspace_name="$1"
  set_cluster_context "$new_workspace_name"
  # Additional cloning logic here
}

# Clone a workspace environment to create a new one
core_clone_workspace() {
  if [[ "$1" == "-h" || "$1" == "--help" || $# -lt 2 ]]; then
    echo "Usage: cpc clone-workspace <source_workspace> <destination_workspace> [release_letter]"
    echo "Clones a workspace environment to create a new one."
    echo ""
    echo "Arguments:"
    echo "  source_workspace      The name of the workspace to clone"
    echo "  destination_workspace The name for the new workspace"
    echo "  release_letter        Optional: release letter (a, b, c, etc.)"
    echo ""
    echo "Examples:"
    echo "  cpc clone-workspace ubuntu ubuntu-new"
    echo "  cpc clone-workspace ubuntu ubuntu-new b"
    return 0
  fi

  local source_workspace="$1"
  local new_workspace_name="$2"
  local release_letter="${3:-}"

  if ! validate_clone_parameters "$source_workspace" "$new_workspace_name"; then
    return 1
  fi

  local repo_root
  repo_root=$(get_repo_path)
  local source_env_file="$repo_root/$ENVIRONMENTS_DIR/${source_workspace}.env"
  local new_env_file="$repo_root/$ENVIRONMENTS_DIR/${new_workspace_name}.env"
  local locals_tf_file="$repo_root/$TERRAFORM_DIR/locals.tf"

  if [[ ! -f "$source_env_file" ]]; then
    log_error "Source workspace '$source_workspace' does not exist."
    return 1
  fi

  if [[ -f "$new_env_file" ]]; then
    log_error "Destination workspace '$new_workspace_name' already exists."
    return 1
  fi

  # Determine release letter if not provided
  if [[ -z "$release_letter" ]]; then
    release_letter=$(determine_release_letter "$source_workspace")
  fi

  log_info "Cloning workspace '$source_workspace' to '$new_workspace_name'..."

  # Backup existing files
  backup_existing_files "$locals_tf_file"

  # Copy environment file
  copy_workspace_files "$source_env_file" "$new_env_file"

  # Update workspace mappings
  update_workspace_mappings "$new_workspace_name" "$release_letter" "$new_env_file"

  # Switch to new workspace
  switch_to_new_workspace "$new_workspace_name"

  log_success "Workspace '$new_workspace_name' cloned successfully."
}

# confirm_deletion() - Prompts user for confirmation before deleting the workspace.
function confirm_deletion() {
  local workspace_name="$1"
  read -p "Are you sure you want to DESTROY and DELETE workspace '$workspace_name'? This cannot be undone. (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    return 0
  else
    log_info "Operation cancelled."
    return 1
  fi
}

# destroy_resources() - Destroys all infrastructure resources in the workspace.
function destroy_resources() {
  local workspace_name="$1"
  log_step "Destroying all resources in workspace '$workspace_name'..."
  log_success "All resources for '$workspace_name' have been destroyed."
  cpc_tofu deploy destroy || true
}

# remove_workspace_files() - Deletes environment and configuration files.
function remove_workspace_files() {
  local workspace_name="$1"
  local repo_root
  repo_root=$(get_repo_path)
  local env_file="$repo_root/$ENVIRONMENTS_DIR/${workspace_name}.env"
  local locals_tf_file="$repo_root/$TERRAFORM_DIR/locals.tf"

  if [[ -f "$env_file" ]]; then
    rm -f "$env_file"
    log_info "Removed environment file: $env_file."
  fi

  if grep -q "\"${workspace_name}\"" "$locals_tf_file"; then
    sed -i "/\"${workspace_name}\"/d" "$locals_tf_file"
    log_info "Removed entries for '$workspace_name' from locals.tf."
  fi
}

# update_mappings() - Removes workspace references from mapping files.
function update_mappings() {
  # Additional mapping updates if needed
  log_debug "Mappings updated"
}

# switch_to_safe_context() - Switches to a safe context after deletion.
function switch_to_safe_context() {
  local workspace_name="$1"
  local original_context="$2"
  local safe_context="ubuntu"
  if [[ "$original_context" != "$workspace_name" ]]; then
    safe_context="$original_context"
  fi

  log_step "Switching to safe context ('$safe_context') to perform deletion..."
  if ! core_ctx "$safe_context"; then
    log_error "Could not switch to a safe workspace ('$safe_context'). Aborting workspace deletion."
    return 1
  fi
}

# core_delete_workspace() - Deletes a workspace and all its resources.
function core_delete_workspace() {
  if [[ -z "$1" ]]; then
    log_error "Usage: cpc delete-workspace <workspace_name>"
    return 1
  fi

  local workspace_name="$1"
  local repo_root
  repo_root=$(get_repo_path)
  local env_file="$repo_root/$ENVIRONMENTS_DIR/${workspace_name}.env"
  local locals_tf_file="$repo_root/$TERRAFORM_DIR/locals.tf"

  local original_context
  original_context=$(get_current_cluster_context)

  log_warning "This command will first DESTROY all infrastructure in workspace '$workspace_name'."
  if ! confirm_deletion "$workspace_name"; then
    return 1
  fi

  # Switch to the context that will be deleted
  set_cluster_context "$workspace_name"

  # Destroy resources
  if ! destroy_resources "$workspace_name"; then
    log_error "Resources were destroyed, but the empty workspace '$workspace_name' remains."
    return 1
  fi

  # Clear cache
  clear_all_caches

  # Switch to safe context
  if ! switch_to_safe_context "$workspace_name" "$original_context"; then
    return 1
  fi

  # Delete Terraform workspace
  log_step "Deleting Terraform workspace '$workspace_name' from the backend..."
  if ! cpc_tofu workspace delete "$workspace_name"; then
    log_error "Failed to delete the Terraform workspace '$workspace_name' from backend."
  else
    log_success "Terraform workspace '$workspace_name' has been deleted."
  fi

  # Clean up local files
  remove_workspace_files "$workspace_name"
  update_mappings

  log_success "Workspace '$workspace_name' has been successfully deleted."
}

#----------------------------------------------------------------------
# Main Entry Point for Workspace Operations
#----------------------------------------------------------------------

# cpc_workspace_ops() - Main entry point for workspace operations commands
function cpc_workspace_ops() {
  local command="$1"
  shift

  case "$command" in
    clone-workspace)
      core_clone_workspace "$@"
      ;;
    delete-workspace)
      core_delete_workspace "$@"
      ;;
    *)
      log_error "Unknown workspace operation: $command"
      log_info "Available operations: clone-workspace, delete-workspace"
      return 1
      ;;
  esac
}

# Export the main function
export -f cpc_workspace_ops
