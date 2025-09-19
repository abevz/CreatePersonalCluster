#!/bin/bash
# modules/10_proxmox.sh - Proxmox VM management module
# Part of the modular CPC architecture

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This module should not be run directly. Use the main cpc script." >&2
    exit 1
fi

# Module: Proxmox VM functionality
log_debug "Loading module: 10_proxmox.sh - Proxmox VM management"

# Function to handle all Proxmox VM commands
function cpc_proxmox() {
    local command="$1"
    shift
    
    case "$command" in
        add-vm)
            proxmox_add_vm "$@"
            ;;
        remove-vm)
            proxmox_remove_vm "$@"
            ;;
        template)
            proxmox_create_template "$@"
            ;;
        vmctl)
            proxmox_vm_control "$@"
            ;;
        *)
            log_error "Unknown proxmox command: $command"
            return 1
            ;;
    esac
}

# Phase 1: User Interface and Input Handling Functions

function _display_add_vm_help() {
    echo "Usage: cpc add-vm"
    echo ""
    echo "Interactively add a new VM and update configuration."
    echo "This command will:"
    echo "1. Ask for node type (worker or control plane)"
    echo "2. Generate a unique node name"
    echo "3. Update Terraform configuration"
    echo "4. Create the VM"
    echo ""
    echo "Note: To join to Kubernetes after VM creation, use:"
    echo "  ./cpc add-nodes --target-hosts \"<node-name>\" --node-type \"<type>\""
}

function _display_remove_vm_help() {
    echo "Usage: cpc remove-vm"
    echo ""
    echo "Interactively remove a VM and update configuration."
    echo "This command will:"
    echo "1. Show available additional nodes"
    echo "2. Destroy the VM with Terraform"
    echo "3. Update the configuration file"
    echo ""
    echo "Note: To remove from Kubernetes first, use:"
    echo "  ./cpc remove-nodes --target-hosts \"<node-name>\""
}

function _display_template_help() {
    echo "Usage: cpc template"
    echo ""
    echo "Creates a VM template for Kubernetes cluster nodes."
    echo "This command will:"
    echo "1. Set workspace-specific template variables"
    echo "2. Validate required template configuration"
    echo "3. Execute the template creation script"
    echo ""
    echo "Template variables are loaded from envs/<workspace>.env"
}

function _prompt_node_type_selection() {
    echo "" >&2
    echo "Select node type:" >&2
    echo "1) Worker node" >&2
    echo "2) Control plane node" >&2
    echo "" >&2
    read -r -p "Enter your choice (1-2): " node_type_choice
    
    case $node_type_choice in
        1)
            echo "worker"
            return 0
            ;;
        2)
            echo "controlplane"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

function _prompt_user_confirmation() {
    local message_text="$1"
    echo ""
    read -r -p "$message_text Continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    else
        echo "Cancelled."
        return 1
    fi
}

function _prompt_vm_addition_confirmation() {
    local new_node_name="$1"
    local node_type="$2"
    
    echo ""
    log_info "New node will be: $new_node_name (type: $node_type)"
    echo ""
    read -r -p "Continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

function _prompt_node_removal_selection() {
    local -a nodes_array=("$@")
    
    # Show available nodes (to stderr so it doesn't interfere with return value)
    echo "" >&2
    log_info "Available nodes to remove:" >&2
    for i in "${!nodes_array[@]}"; do
        echo "$((i+1)). ${nodes_array[i]}" >&2
    done
    
    echo >&2
    read -r -p "Enter the number of the node to remove: " choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#nodes_array[@]} ]; then
        return 1
    fi
    
    echo "${nodes_array[$((choice-1))]}"
    return 0
}

function _prompt_vm_removal_confirmation() {
    local node_name="$1"
    local node_type="$2"
    
    echo ""
    log_error "This will remove node: $node_name (type: $node_type)"
    log_error "The VM will be destroyed and cannot be recovered!"
    echo ""
    read -r -p "Are you sure? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

function _validate_current_context() {
    local current_ctx
    if ! current_ctx=$(get_current_cluster_context); then
        error_handle "$ERROR_CONFIG" "Failed to get current cluster context" "$SEVERITY_HIGH" "abort"
        exit 1
    fi
    echo "$current_ctx"
}

function _validate_environment_file() {
    local env_file="$1"
    if ! error_validate_file "$env_file" "Environment file not found: $env_file"; then
        return 1
    fi
    return 0
}

# Phase 2: Node Management Logic Functions

function _parse_current_nodes() {
    local env_file="$1"
    
    CURRENT_WORKERS_ARRAY=""
    CURRENT_CONTROLPLANES_ARRAY=""
    
    if [ -f "$env_file" ]; then
        # Get all ADDITIONAL_WORKERS values and combine them
        CURRENT_WORKERS_ARRAY=$(grep -E "^ADDITIONAL_WORKERS=" "$env_file" | cut -d'=' -f2 | tr -d '"' | paste -sd ',' | tr -d '\n' || echo "")
        # Remove empty values and clean up
        CURRENT_WORKERS_ARRAY=$(echo "$CURRENT_WORKERS_ARRAY" | sed 's/,\+/,/g' | sed 's/^,\|,$//g' | sed 's/,,\+/,/g')
        if [ "$CURRENT_WORKERS_ARRAY" = "" ]; then
            CURRENT_WORKERS_ARRAY=""
        fi
        
        # Get all ADDITIONAL_CONTROLPLANES values and combine them
        CURRENT_CONTROLPLANES_ARRAY=$(grep -E "^ADDITIONAL_CONTROLPLANES=" "$env_file" | cut -d'=' -f2 | tr -d '"' | paste -sd ',' | tr -d '\n' || echo "")
        # Remove empty values and clean up
        CURRENT_CONTROLPLANES_ARRAY=$(echo "$CURRENT_CONTROLPLANES_ARRAY" | sed 's/,\+/,/g' | sed 's/^,\|,$//g' | sed 's/,,\+/,/g')
        if [ "$CURRENT_CONTROLPLANES_ARRAY" = "" ]; then
            CURRENT_CONTROLPLANES_ARRAY=""
        fi
    fi
}

function _generate_next_node_name() {
    local node_type="$1"
    
    if [ "$node_type" = "worker" ]; then
        # Count existing workers (worker1, worker2 are base, so start from worker3)
        local next_num=3
        while true; do
            # Check all formats: worker3, worker-3
            if [[ "$CURRENT_WORKERS_ARRAY" == *"worker-$next_num"* || "$CURRENT_WORKERS_ARRAY" == *"worker$next_num"* ]]; then
                ((next_num++))
            else
                break
            fi
        done
        echo "worker-$next_num"
    else
        # Control plane logic (controlplane is base, so start from controlplane2)
        local next_num=2
        while true; do
            if [[ "$CURRENT_CONTROLPLANES_ARRAY" == *"controlplane-$next_num"* || "$CURRENT_CONTROLPLANES_ARRAY" == *"controlplane$next_num"* ]]; then
                ((next_num++))
            else
                break
            fi
        done
        echo "controlplane-$next_num"
    fi
}

function _validate_node_name_uniqueness() {
    local node_name="$1"
    
    # Check against both worker and control plane arrays
    if [[ "$CURRENT_WORKERS_ARRAY" == *"$node_name"* || "$CURRENT_CONTROLPLANES_ARRAY" == *"$node_name"* ]]; then
        log_error "Node name $node_name already exists"
        return 1
    fi
    return 0
}

function _get_removable_nodes() {
    local env_file="$1"
    
    _parse_current_nodes "$env_file"
    
    local all_nodes=()
    
    if [ -n "$CURRENT_WORKERS_ARRAY" ]; then
        IFS=',' read -ra worker_nodes <<< "$CURRENT_WORKERS_ARRAY"
        for node in "${worker_nodes[@]}"; do
            all_nodes+=("$node (worker)")
        done
    fi
    if [ -n "$CURRENT_CONTROLPLANES_ARRAY" ]; then
        IFS=',' read -ra cp_nodes <<< "$CURRENT_CONTROLPLANES_ARRAY"
        for node in "${cp_nodes[@]}"; do
            all_nodes+=("$node (control plane)")
        done
    fi
    
    # Return array elements separated by newlines
    for node in "${all_nodes[@]}"; do
        echo "$node"
    done
}

function _prompt_node_selection() {
    if [ ${#REMOVABLE_NODES_ARRAY[@]} -eq 0 ]; then
        log_validation "No additional nodes found to remove."
        log_validation "Base nodes (controlplane, worker1, worker2) cannot be removed with this command."
        exit 1
    fi
    
    # Show available nodes
    echo ""
    log_info "Available nodes to remove:"
    for i in "${!REMOVABLE_NODES_ARRAY[@]}"; do
        echo "$((i+1)). ${REMOVABLE_NODES_ARRAY[i]}"
    done
    
    echo
    read -r -p "Enter the number of the node to remove: " choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#REMOVABLE_NODES_ARRAY[@]} ]; then
        log_error "Invalid choice."
        exit 1
    fi
    
    echo "${REMOVABLE_NODES_ARRAY[$((choice-1))]}"
}

function _parse_selected_node() {
    local selected_node_string="$1"
    
    # Extract just the node name (before the parentheses)
    SELECTED_NODE_NAME="${selected_node_string%% (*}"
    # Extract node type (between parentheses)
    SELECTED_NODE_TYPE="${selected_node_string##*\(}"
    SELECTED_NODE_TYPE="${SELECTED_NODE_TYPE%\)*}"
}

# Phase 3: Environment File Operations Functions

function _add_worker_to_env() {
    local env_file="$1"
    local node_name="$2"
    local existing_workers="$3"
    
    # Remove all existing ADDITIONAL_WORKERS lines (including commented ones)
    sed -i '/^#\?ADDITIONAL_WORKERS=/d' "$env_file"

    if [ -z "$existing_workers" ]; then
        echo "ADDITIONAL_WORKERS=\"$node_name\"" >> "$env_file"
    else
        # Add to existing list
        local new_additional="$existing_workers,$node_name"
        echo "ADDITIONAL_WORKERS=\"$new_additional\"" >> "$env_file"
    fi
    
    log_success "Updated $env_file with $node_name"
}

function _add_controlplane_to_env() {
    local env_file="$1"
    local node_name="$2"
    local existing_controlplanes="$3"
    
    if [ -z "$existing_controlplanes" ]; then
        # Check if line exists
        if grep -q "^ADDITIONAL_CONTROLPLANES=" "$env_file"; then
            sed -i "s/^ADDITIONAL_CONTROLPLANES=.*/ADDITIONAL_CONTROLPLANES=\"$node_name\"/" "$env_file"
        else
            echo "ADDITIONAL_CONTROLPLANES=\"$node_name\"" >> "$env_file"
        fi
    else
        # Add to existing list
        local new_additional_cp="$existing_controlplanes,$node_name"
        sed -i "s/^ADDITIONAL_CONTROLPLANES=.*/ADDITIONAL_CONTROLPLANES=\"$new_additional_cp\"/" "$env_file"
    fi
    
    log_success "Updated $env_file with $node_name"
}

function _normalize_node_name_for_removal() {
    local node_name="$1"
    
    # Extract numeric part of node name (e.g., worker3 -> 3)
    local node_number=""
    if [[ "$node_name" =~ ^worker-([0-9]+)$ ]]; then
        node_number="${BASH_REMATCH[1]}"
    elif [[ "$node_name" =~ ^worker([0-9]+)$ ]]; then
        node_number="${BASH_REMATCH[1]}"
    elif [[ "$node_name" =~ ^controlplane-([0-9]+)$ ]]; then
        node_number="${BASH_REMATCH[1]}"
    elif [[ "$node_name" =~ ^controlplane([0-9]+)$ ]]; then
        node_number="${BASH_REMATCH[1]}"
    fi
    
    echo "$node_number"
}

function _remove_worker_from_env() {
    local env_file="$1"
    local node_name_to_remove="$2"
    
    local node_number
    node_number=$(_normalize_node_name_for_removal "$node_name_to_remove")
    
    log_debug "current_additional_workers='$CURRENT_WORKERS_ARRAY'"
    log_debug "node_name='$node_name_to_remove'"
    
    if [ -n "$CURRENT_WORKERS_ARRAY" ]; then
        IFS=',' read -ra worker_array <<< "$CURRENT_WORKERS_ARRAY"
        log_debug "worker_array=(${worker_array[*]})"
        
        local new_workers=()
        for worker in "${worker_array[@]}"; do
            log_debug "checking worker='$worker' vs node_name='$node_name_to_remove'"
            
            # Check for both old and new format matches
            if [ "$worker" != "$node_name_to_remove" ]; then
                # If we have a node number, also check the alternate format
                if [ -n "$node_number" ]; then
                    # Check if worker is either worker3 or worker-3 when node_name is the other format
                    if [ "$worker" != "worker$node_number" ] && [ "$worker" != "worker-$node_number" ]; then
                        new_workers+=("$worker")
                        log_debug "keeping worker='$worker'"
                    else
                        log_debug "removing worker='$worker' (matched by number)"
                    fi
                else
                    # Standard exact name check
                    new_workers+=("$worker")
                    log_debug "keeping worker='$worker'"
                fi
            else
                log_debug "removing worker='$worker'"
            fi
        done
        
        log_debug "new_workers=(${new_workers[*]})"
        log_debug "new_workers length=${#new_workers[@]}"
        
        # Remove all existing ADDITIONAL_WORKERS lines (including commented ones)
        sed -i '/^#\?ADDITIONAL_WORKERS=/d' "$env_file"
        
        if [ ${#new_workers[@]} -eq 0 ]; then
            echo 'ADDITIONAL_WORKERS=""' >> "$env_file"
        else
            local new_additional_workers
            new_additional_workers=$(IFS=','; echo "${new_workers[*]}")
            echo "ADDITIONAL_WORKERS=\"$new_additional_workers\"" >> "$env_file"
        fi
    fi
}

function _remove_controlplane_from_env() {
    local env_file="$1"
    local node_name_to_remove="$2"
    
    local node_number
    node_number=$(_normalize_node_name_for_removal "$node_name_to_remove")
    
    if [ -n "$CURRENT_CONTROLPLANES_ARRAY" ]; then
        IFS=',' read -ra cp_array <<< "$CURRENT_CONTROLPLANES_ARRAY"
        log_debug "cp_array=(${cp_array[*]})"
        
        local new_cps=()
        for cp in "${cp_array[@]}"; do
            log_debug "checking cp='$cp' vs node_name='$node_name_to_remove'"
            
            # Check for both old and new format matches
            if [ "$cp" != "$node_name_to_remove" ]; then
                # If we have a node number, also check the alternate format
                if [ -n "$node_number" ]; then
                    # Check if cp is either controlplane2 or controlplane-2 when node_name is the other format
                    if [ "$cp" != "controlplane$node_number" ] && [ "$cp" != "controlplane-$node_number" ]; then
                        new_cps+=("$cp")
                        log_debug "keeping cp='$cp'"
                    else
                        log_debug "removing cp='$cp' (matched by number)"
                    fi
                else
                    # Standard exact name check
                    new_cps+=("$cp")
                    log_debug "keeping cp='$cp'"
                fi
            else
                log_debug "removing cp='$cp'"
            fi
        done
        
        # Remove all existing ADDITIONAL_CONTROLPLANES lines (including commented ones)
        sed -i '/^#\?ADDITIONAL_CONTROLPLANES=/d' "$env_file"
        
        if [ ${#new_cps[@]} -eq 0 ]; then
            echo 'ADDITIONAL_CONTROLPLANES=""' >> "$env_file"
        else
            local new_additional_controlplanes
            new_additional_controlplanes=$(IFS=','; echo "${new_cps[*]}")
            echo "ADDITIONAL_CONTROLPLANES=\"$new_additional_controlplanes\"" >> "$env_file"
        fi
    fi
}

# Phase 4: Terraform and External Operations Functions

function _execute_terraform_vm_creation() {
    log_info "Creating VM with Terraform..."
    
    # Reload environment variables from current environment file
    if [[ -n "$current_ctx" ]]; then
        env_file="$REPO_PATH/envs/$current_ctx.env"
        if [[ -f "$env_file" ]]; then
            log_debug "Reloading environment variables from $env_file"
            source "$env_file"
        fi
    fi
    
    # Ensure environment variables are exported for Terraform
    export TF_VAR_additional_workers="$ADDITIONAL_WORKERS"
    export TF_VAR_additional_controlplanes="$ADDITIONAL_CONTROLPLANES"
    export TF_VAR_release_letter="$RELEASE_LETTER"
    
    log_debug "Terraform variables: TF_VAR_additional_workers='$TF_VAR_additional_workers', TF_VAR_release_letter='$TF_VAR_release_letter'"
    
    if ! timeout_terraform_operation \
         "cd '$REPO_PATH/terraform' && tofu apply -auto-approve" \
         "Terraform VM creation" \
         "$DEFAULT_TERRAFORM_TIMEOUT"; then
        error_handle "$ERROR_EXECUTION" "Terraform apply failed for VM creation" "$SEVERITY_HIGH"
        return 1
    fi
    return 0
}

function _execute_terraform_vm_destruction() {
    log_info "Destroying VM with Terraform..."
    if ! "$REPO_PATH/cpc" deploy apply -auto-approve; then
        log_error "Failed to apply Terraform changes"
        return 1
    fi
    return 0
}

function _regenerate_hostnames() {
    log_info "Regenerating hostname configurations..."
    if ! "$REPO_PATH/cpc" generate-hostnames; then
        log_validation "Warning: Failed to regenerate hostnames, you may need to run this manually"
        return 1
    fi
    return 0
}

function _get_current_vm_count() {
    local vm_count
    vm_count=$("$REPO_PATH/cpc" deploy output -json cluster_summary 2>/dev/null | jq '. | length' 2>/dev/null || echo "unknown")
    echo "$vm_count"
}

function _verify_vm_removal() {
    local vm_count_before="$1"
    
    log_info "Verifying VM removal..."
    local vm_count_after
    vm_count_after=$(_get_current_vm_count)
    
    if [[ "$vm_count_before" != "unknown" && "$vm_count_after" != "unknown" && "$vm_count_after" -lt "$vm_count_before" ]]; then
        log_success "Successfully removed VM from infrastructure!"
        log_success "VM count reduced from $vm_count_before to $vm_count_after"
        return 0
    elif [[ "$vm_count_before" != "unknown" && "$vm_count_after" != "unknown" && "$vm_count_after" -eq "$vm_count_before" ]]; then
        log_validation "Warning: VM count unchanged ($vm_count_before). VM may not have been removed."
        log_validation "This could be due to configuration caching. Try running:"
        log_validation "  ./cpc deploy apply -auto-approve"
        log_validation "to manually complete the removal."
        return 1
    else
        log_success "VM removal completed (verification unavailable)"
        return 0
    fi
}

# Phase 5: Template Operations Functions

function _initialize_template_creation() {
    # Initialize recovery for template creation
    recovery_checkpoint "template_creation_start" "Starting template creation process"

    # Ensure workspace-specific template variables are set with error handling
    local current_ctx
    if ! current_ctx=$(get_current_cluster_context); then
        error_handle "$ERROR_CONFIG" "Failed to get current cluster context for template creation" "$SEVERITY_HIGH" "abort"
        exit 1
    fi

    log_info "Setting template variables for workspace '$current_ctx'..."
    echo "$current_ctx"
}

function _setup_template_variables() {
    local context="$1"
    
    # Execute with recovery
    if ! recovery_execute \
         "set_workspace_template_vars '$context'" \
         "set_template_vars" \
         "log_warning 'Failed to set template variables, manual cleanup may be needed'" \
         "validate_template_vars"; then
        log_error "Failed to set template variables"
        return 1
    fi
    return 0
}

function _execute_template_script() {
    log_info "Creating VM template using script..."

    # Execute template script with timeout and error handling
    if ! timeout_execute \
         "$REPO_PATH/scripts/template.sh" \
         "$DEFAULT_COMMAND_TIMEOUT" \
         "Template creation script" \
         "cleanup_template_creation"; then
        error_handle "$ERROR_EXECUTION" "Template creation script failed" "$SEVERITY_HIGH"
        return 1
    fi
    return 0
}

function _verify_vm_removal() {
    local node_name="$1"
    
    log_info "Verifying VM removal..."
    local vm_count_after
    vm_count_after=$("$REPO_PATH/cpc" deploy output -json cluster_summary 2>/dev/null | jq '. | length' 2>/dev/null || echo "unknown")
    
    if [[ "$vm_count_before" != "unknown" && "$vm_count_after" != "unknown" && "$vm_count_after" -lt "$vm_count_before" ]]; then
        log_success "Successfully removed VM $node_name from infrastructure!"
        log_success "VM count reduced from $vm_count_before to $vm_count_after"
    elif [[ "$vm_count_before" != "unknown" && "$vm_count_after" != "unknown" && "$vm_count_after" -eq "$vm_count_before" ]]; then
        log_validation "Warning: VM count unchanged ($vm_count_before). VM may not have been removed."
        log_validation "This could be due to configuration caching. Try running:"
        log_validation "  ./cpc deploy apply -auto-approve"
        log_validation "to manually complete the removal."
    else
        log_success "VM removal completed (verification unavailable)"
    fi
}

function _verify_vm_removal_preparation() {
    local node_name="$1"
    
    # Get VM info before destruction to verify removal
    log_info "Getting current VM information..."
    vm_count_before=$("$REPO_PATH/cpc" deploy output -json cluster_summary 2>/dev/null | jq '. | length' 2>/dev/null || echo "unknown")
}

function _initialize_template_creation_recovery() {
    recovery_checkpoint "template_creation_start" "Starting template creation process"
}

# Phase 6: Recovery and Validation Functions

function _initialize_vm_operation_recovery() {
    local operation_type="$1"
    recovery_checkpoint "proxmox_${operation_type}_vm_start" "Starting VM ${operation_type} process"
}

function _finalize_vm_operation_recovery() {
    local operation_type="$1"
    local vm_name="$2"
    log_success "Successfully ${operation_type}d VM $vm_name!"
    if [[ "$operation_type" == "create" ]]; then
        log_info "To join the node to Kubernetes cluster, use:"
        echo "  ./cpc add-nodes --target-hosts \"$vm_name\" --node-type \"worker\""
    fi
}

function _validate_node_addition_result() {
    local env_file="$1"
    local node_type="$2"
    local node_name="$3"

    if [ "$node_type" = "worker" ]; then
        grep -q "ADDITIONAL_WORKERS.*$node_name" "$env_file"
    else
        grep -q "ADDITIONAL_CONTROLPLANES.*$node_name" "$env_file"
    fi
}

function _validate_template_setup_result() {
    validate_template_vars
}

function _validate_env_file_update_result() {
    local env_file="$1"
    local node_type="$2"
    local new_node_name="$3"

    if [ "$node_type" = "worker" ]; then
        grep -q "ADDITIONAL_WORKERS.*$new_node_name" "$env_file"
    else
        grep -q "ADDITIONAL_CONTROLPLANES.*$new_node_name" "$env_file"
    fi
}

function _validate_node_removal_result() {
    local env_file="$1"
    local node_name="$2"
    local vm_count_before="$3"
    local vm_count_after="$4"
    
    # Check that node was removed from environment file
    if grep -q "$node_name" "$env_file"; then
        log_validation "Warning: Node $node_name may still exist in environment file"
        return 1
    fi
    
    # Check VM count if available
    if [[ "$vm_count_before" != "unknown" && "$vm_count_after" != "unknown" && "$vm_count_after" -ge "$vm_count_before" ]]; then
        log_validation "Warning: VM count did not decrease as expected"
        return 1
    fi
    
    return 0
}

# Add VM command - interactively add a new VM
function proxmox_add_vm() {
    # Display help if requested
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        _display_add_vm_help
        return 0
    fi

    local target_node="$1"

    # Initialize recovery for this operation
    _initialize_vm_operation_recovery "proxmox_add_vm_start" "Starting VM addition process"

    # Get current context with error handling
    if ! current_ctx=$(get_current_cluster_context); then
        error_handle "$ERROR_CONFIG" "Failed to get current cluster context" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    log_info "Current cluster context: $current_ctx"

    # Validate environment file exists
    env_file="$REPO_PATH/envs/$current_ctx.env"
    if ! error_validate_file "$env_file" "Environment file not found: $env_file"; then
        return 1
    fi
    
    # Determine node type from argument or prompt user
    if [ -n "$target_node" ]; then
        # Auto-detect node type from target name
        if [[ "$target_node" =~ ^controlplane ]]; then
            node_type="controlplane"
            log_info "=== VM Addition: $target_node (control plane) ==="
        elif [[ "$target_node" =~ ^worker ]]; then
            node_type="worker"
            log_info "=== VM Addition: $target_node (worker) ==="
        else
            log_error "Invalid node name format. Expected: 'controlplane-X' or 'worker-X'"
            log_info "Examples: controlplane-3, worker-4"
            exit 1
        fi
    else
        # Interactive mode
        log_info "=== Interactive VM Addition ==="
        echo ""
        
        # Get node type from user
        if ! node_type=$(_prompt_node_type_selection); then
            log_error "Invalid choice. Exiting."
            exit 1
        fi
    fi
    
    echo ""
    
    # Parse current nodes from environment file
    _parse_current_nodes "$env_file"
    
    # Generate or use specified node name
    if [ -n "$target_node" ]; then
        new_node_name="$target_node"
        
        # Validate the target node name doesn't already exist
        if [ "$node_type" = "worker" ]; then
            for existing_worker in "${ADDITIONAL_WORKERS[@]}"; do
                if [ "$existing_worker" = "$new_node_name" ]; then
                    log_error "Worker node '$new_node_name' already exists"
                    exit 1
                fi
            done
        else # controlplane
            for existing_cp in "${ADDITIONAL_CONTROLPLANES[@]}"; do
                if [ "$existing_cp" = "$new_node_name" ]; then
                    log_error "Control plane node '$new_node_name' already exists"
                    exit 1
                fi
            done
        fi
    else
        # Generate next available node name
        if ! new_node_name=$(_generate_next_node_name "$node_type"); then
            log_error "Failed to generate next node name"
            return 1
        fi
    fi
    
    # Confirm with user
    if ! _prompt_vm_addition_confirmation "$new_node_name" "$node_type"; then
        echo "Cancelled."
        return 0
    fi
    
    # Update environment file with recovery
    log_info "Updating environment configuration..."
    if ! recovery_execute \
         "update_environment_file '$env_file' '$node_type' '$new_node_name' '' ''" \
         "update_env_file" \
         "log_warning 'Failed to update environment file, manual cleanup may be needed'" \
         "_validate_env_file_update_result '$env_file' '$node_type' '$new_node_name'"; then
        log_error "Failed to update environment file"
        return 1
    fi

    # Create VM with Terraform
    if ! _execute_terraform_vm_creation; then
        return 1
    fi
    
    # Regenerate hostnames configuration
    _regenerate_hostnames
    
    log_success "Successfully created VM $new_node_name!"
    log_info "To join the node to Kubernetes cluster, use:"
    echo "  ./cpc add-nodes --target-hosts \"$new_node_name\" --node-type \"$node_type\""
}

# Remove VM command - interactively remove a VM
function proxmox_remove_vm() {
    # Display help if requested
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        _display_remove_vm_help
        return 0
    fi

    local target_node="$1"
    
    # Get current context
    current_ctx=$(get_current_cluster_context)
    log_info "Current cluster context: $current_ctx"
    
    # Get removable nodes from environment file
    env_file="$REPO_PATH/envs/$current_ctx.env"
    if ! all_nodes=$(_get_removable_nodes "$env_file"); then
        log_validation "No additional nodes found to remove."
        log_validation "Base nodes (controlplane, worker1, worker2) cannot be removed with this command."
        exit 1
    fi
    
    # Parse removable nodes array
    IFS=$'\n' read -rd '' -a nodes_array <<< "$all_nodes" || true
    
    if [ ${#nodes_array[@]} -eq 0 ]; then
        log_validation "No additional nodes found to remove."
        log_validation "Base nodes (controlplane, worker1, worker2) cannot be removed with this command."
        exit 1
    fi
    
    # If no target node specified, show interactive selection
    if [ -z "$target_node" ]; then
        log_info "=== Interactive VM Removal ==="
        echo ""
        
        # Show available nodes and get user selection
        if ! selected_info=$(_prompt_node_removal_selection "${nodes_array[@]}"); then
            log_error "Invalid choice."
            exit 1
        fi
    else
        # Find the specified node in the available nodes
        selected_info=""
        for node in "${nodes_array[@]}"; do
            node_name="${node%% (*}"
            if [ "$node_name" = "$target_node" ]; then
                selected_info="$node"
                break
            fi
        done
        
        if [ -z "$selected_info" ]; then
            log_error "Node '$target_node' not found in removable nodes."
            log_info "Available nodes to remove:"
            for node in "${nodes_array[@]}"; do
                echo "  - ${node%% (*}"
            done
            exit 1
        fi
        
        log_info "=== VM Removal: $target_node ==="
        echo ""
    fi
    
    # Parse selected node info
    node_name="${selected_info%% (*}"
    node_type="${selected_info##*\(}"
    node_type="${node_type%\)*}"
    
    # Confirm removal with user
    if ! _prompt_vm_removal_confirmation "$node_name" "$node_type"; then
        echo "Cancelled."
        return 0
    fi
    
    # Remove from environment file
    # Parse current nodes first to populate global arrays
    _parse_current_nodes "$env_file"
    
    if [ "$node_type" = "worker" ]; then
        _remove_worker_from_env "$env_file" "$node_name"
    else
        _remove_controlplane_from_env "$env_file" "$node_name"
    fi
    
    log_success "Updated configuration file"
    
    # Verify VM removal before destruction
    _verify_vm_removal_preparation "$node_name"
    
    # Destroy VM with Terraform
    if ! _execute_terraform_vm_destruction; then
        exit 1
    fi
    
    # Verify VM was actually removed
    _verify_vm_removal "$node_name"
    
    log_info "Note: If the node was part of Kubernetes cluster, you may need to manually clean up the cluster state."
}

# Create VM template for Kubernetes
function proxmox_create_template() {
    # Display help if requested
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        _display_template_help
        return 0
    fi

    # Initialize recovery for template creation
    _initialize_template_creation_recovery

    # Get current context and setup template variables
    local current_ctx
    if ! current_ctx=$(_initialize_template_creation); then
        return 1
    fi

    log_info "Setting template variables for workspace '$current_ctx'..."

    # Setup workspace-specific template variables with recovery
    if ! recovery_execute \
         "_setup_template_variables '$current_ctx'" \
         "set_template_vars" \
         "log_warning 'Failed to set template variables, manual cleanup may be needed'" \
         "_validate_template_setup_result"; then
        log_error "Failed to set template variables"
        return 1
    fi

    # Validate essential template variables with enhanced error handling
    if ! error_validate_template_vars; then
        error_handle "$ERROR_CONFIG" "Template variables not properly set for workspace '$current_ctx'" "$SEVERITY_CRITICAL" "abort"
        return 1
    fi

    log_info "Creating VM template using script..."

    # Execute template script with timeout and error handling
    if ! timeout_execute \
         "$REPO_PATH/scripts/template.sh" \
         "$DEFAULT_COMMAND_TIMEOUT" \
         "Template creation script" \
         "cleanup_template_creation"; then
        error_handle "$ERROR_EXECUTION" "Template creation script failed" "$SEVERITY_HIGH"
        return 1
    fi

    recovery_checkpoint "template_creation_complete" "Template creation completed successfully"
    log_success "VM template created successfully"
}

# Helper function to validate template variables
function validate_template_vars() {
    [[ -n "$TEMPLATE_VM_ID" && -n "$TEMPLATE_VM_NAME" && -n "$IMAGE_NAME" && -n "$IMAGE_LINK" ]]
}

# Helper function to validate essential template variables with detailed error reporting
function error_validate_template_vars() {
    local missing_vars=()

    if [[ -z "$TEMPLATE_VM_ID" ]]; then
        missing_vars+=("TEMPLATE_VM_ID")
    fi
    if [[ -z "$TEMPLATE_VM_NAME" ]]; then
        missing_vars+=("TEMPLATE_VM_NAME")
    fi
    if [[ -z "$IMAGE_NAME" ]]; then
        missing_vars+=("IMAGE_NAME")
    fi
    if [[ -z "$IMAGE_LINK" ]]; then
        missing_vars+=("IMAGE_LINK")
    fi

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error_handle "$ERROR_CONFIG" "Missing required template variables: ${missing_vars[*]}" "$SEVERITY_CRITICAL"
        return 1
    fi

    return 0
}

# Cleanup function for template creation failures
function cleanup_template_creation() {
    log_warning "Cleaning up after template creation failure..."

    # Add cleanup logic here - could include:
    # - Removing partially created VMs
    # - Cleaning up temporary files
    # - Resetting template variables

    log_info "Cleanup completed"
}

# VM control (placeholder function)
function proxmox_vm_control() {
    log_info "VM control (start, stop, create, delete) is primarily managed by Tofu in this project."
    log_info "Please use 'tofu apply', 'tofu destroy', or modify your .tfvars and re-apply."
    log_info "Example: To stop a VM, you might comment it out in Tofu and apply, or use Proxmox UI/API directly."
    # Placeholder for future direct VM interactions if needed via Proxmox API etc.
    # ansible_run_playbook "pb_vm_control.yml" "localhost" "-e vm_name=$1 -e action=$2"
}

# Helper function to update environment file
function update_environment_file() {
    local env_file="$1"
    local node_type="$2"
    local new_node_name="$3"
    local current_additional="$4"
    local current_additional_cp="$5"

    if [ "$node_type" = "worker" ]; then
        _add_worker_to_env "$env_file" "$new_node_name" "$current_additional"
    else
        _add_controlplane_to_env "$env_file" "$new_node_name" "$current_additional_cp"
    fi
}

# Helper function to validate environment file update
function validate_env_file_update() {
    local env_file="$1"
    local node_type="$2"
    local new_node_name="$3"

    if [ "$node_type" = "worker" ]; then
        grep -q "ADDITIONAL_WORKERS.*$new_node_name" "$env_file"
    else
        grep -q "ADDITIONAL_CONTROLPLANES.*$new_node_name" "$env_file"
    fi
}

log_debug "Module 10_proxmox.sh loaded successfully"
