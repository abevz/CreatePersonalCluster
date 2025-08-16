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
        *)
            log_error "Unknown proxmox command: $command"
            return 1
            ;;
    esac
}

# Add VM command - interactively add a new VM
function proxmox_add_vm() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
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
        return 0
    fi

    log_info "=== Interactive VM Addition ==="
    echo ""
    
    # Get current context
    current_ctx=$(get_current_cluster_context)
    log_info "Current cluster context: $current_ctx"
    
    # Ask for node type
    echo ""
    echo "Select node type:"
    echo "1) Worker node"
    echo "2) Control plane node"
    echo ""
    read -p "Enter your choice (1-2): " node_type_choice
    
    case $node_type_choice in
        1)
            node_type="worker"
            node_prefix="worker"
            ;;
        2)
            node_type="controlplane"
            node_prefix="controlplane"
            ;;
        *)
            log_error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
    
    # Find next available worker/controlplane number
    env_file="$REPO_PATH/envs/$current_ctx.env"
    current_additional=""
    if [ -f "$env_file" ]; then
        # Get all ADDITIONAL_WORKERS values and combine them
        current_additional=$(grep -E "^ADDITIONAL_WORKERS=" "$env_file" | cut -d'=' -f2 | tr -d '"' | paste -sd ',' | tr -d '\n' || echo "")
        # Remove empty values and clean up
        current_additional=$(echo "$current_additional" | sed 's/,\+/,/g' | sed 's/^,\|,$//g' | sed 's/,,\+/,/g')
        if [ "$current_additional" = "" ]; then
            current_additional=""
        fi
    fi
    
    # Determine next node number
    if [ "$node_type" = "worker" ]; then
        # Count existing workers (worker1, worker2 are base, so start from worker3)
        next_num=3
        while true; do
            # Check all formats: worker3, worker-3
            if [[ "$current_additional" == *"worker-$next_num"* || "$current_additional" == *"worker$next_num"* ]]; then
                ((next_num++))
            else
                break
            fi
        done
        new_node_name="worker-$next_num"
    else
        # Control plane logic
        current_additional_cp=$(grep -E "^ADDITIONAL_CONTROLPLANES=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        # Count existing control planes (controlplane is base, so start from controlplane2)
        next_num=2
        while true; do
            if [[ "$current_additional_cp" == *"controlplane-$next_num"* || "$current_additional_cp" == *"controlplane$next_num"* ]]; then
                ((next_num++))
            else
                break
            fi
        done
        new_node_name="controlplane-$next_num"
    fi
    
    echo ""
    log_info "New node will be: $new_node_name (type: $node_type)"
    echo ""
    read -p "Continue? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        return 0
    fi
    
    # Update environment file
    if [ -f "$env_file" ]; then
        if [ "$node_type" = "worker" ]; then
            # Remove all existing ADDITIONAL_WORKERS lines (including commented ones)
            sed -i '/^#\?ADDITIONAL_WORKERS=/d' "$env_file"
            
            if [ -z "$current_additional" ]; then
                echo "ADDITIONAL_WORKERS=\"$new_node_name\"" >> "$env_file"
            else
                # Add to existing list
                new_additional="$current_additional,$new_node_name"
                echo "ADDITIONAL_WORKERS=\"$new_additional\"" >> "$env_file"
            fi
        else
            # Control plane
            current_additional_cp=$(grep -E "^ADDITIONAL_CONTROLPLANES=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
            if [ -z "$current_additional_cp" ]; then
                # Check if line exists
                if grep -q "^ADDITIONAL_CONTROLPLANES=" "$env_file"; then
                    sed -i "s/^ADDITIONAL_CONTROLPLANES=.*/ADDITIONAL_CONTROLPLANES=\"$new_node_name\"/" "$env_file"
                else
                    echo "ADDITIONAL_CONTROLPLANES=\"$new_node_name\"" >> "$env_file"
                fi
            else
                # Add to existing list
                new_additional_cp="$current_additional_cp,$new_node_name"
                sed -i "s/^ADDITIONAL_CONTROLPLANES=.*/ADDITIONAL_CONTROLPLANES=\"$new_additional_cp\"/" "$env_file"
            fi
        fi
        log_success "Updated $env_file with $new_node_name"
    else
        log_error "Environment file not found: $env_file"
        exit 1
    fi
    
    # Apply Terraform changes
    log_info "Creating VM with Terraform..."
    
    # Pre-generate hostname file for the new node to avoid "file not found" error
    if [[ "$node_type" == "worker" ]]; then
        # Get the release letter from environment file
        release_letter=$(grep -E "^RELEASE_LETTER=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        
        if [ -z "$release_letter" ]; then
            log_validation "Warning: RELEASE_LETTER not found in environment file, using first letter of workspace name"
            release_letter="${current_ctx:0:1}"
        fi
        
        # Generate expected hostname
        node_num=$(echo "$new_node_name" | grep -Eo '[0-9]+$')
        expected_hostname="${release_letter}w${node_num}.bevz.net"
        
        log_info "Using release letter '${release_letter}' for hostname generation"
        log_info "Expected hostname for new node: ${expected_hostname}"
        
        # Create snippets directory if it doesn't exist
        snippets_dir="$REPO_PATH/terraform/snippets"
        mkdir -p "$snippets_dir"
        
        # Generate temp cloud-init user-data file
        temp_userdata="$snippets_dir/node-${release_letter}w${node_num}-userdata.yaml"
        
        # Copy template or create minimal file if no template exists
        template_file="$snippets_dir/node-template-userdata.yaml"
        if [ -f "$template_file" ]; then
            cp "$template_file" "$temp_userdata"
            # Replace hostname placeholder
            sed -i "s/HOSTNAME_PLACEHOLDER/$expected_hostname/g" "$temp_userdata"
        else
            cat > "$temp_userdata" << EOF
#cloud-config
hostname: $expected_hostname
fqdn: $expected_hostname
manage_etc_hosts: true
EOF
        fi
        
        log_info "Pre-generated cloud-init hostname file for $expected_hostname"
    fi
    
    # Generate hostnames (this may fail for new nodes, but we've pre-created the file above)
    "$REPO_PATH/cpc" generate-hostnames || true
    
    # Now run terraform apply
    if ! "$REPO_PATH/cpc" deploy apply -auto-approve; then
        log_error "Failed to apply Terraform changes"
        exit 1
    fi
    
    # After VM creation, regenerate hostnames to ensure everything is updated
    log_info "Regenerating hostname configurations..."
    if ! "$REPO_PATH/cpc" generate-hostnames; then
        log_validation "Warning: Failed to regenerate hostnames, you may need to run this manually"
    fi
    
    log_success "Successfully created VM $new_node_name!"
    log_info "To join the node to Kubernetes cluster, use:"
    echo "  ./cpc add-nodes --target-hosts \"$new_node_name\" --node-type \"$node_type\""
}

# Remove VM command - interactively remove a VM
function proxmox_remove_vm() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
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
        return 0
    fi

    log_info "=== Interactive VM Removal ==="
    echo ""
    
    # Get current context
    current_ctx=$(get_current_cluster_context)
    log_info "Current cluster context: $current_ctx"
    
    # Get additional workers and control planes
    env_file="$REPO_PATH/envs/$current_ctx.env"
    current_additional_workers=""
    current_additional_controlplanes=""
    if [ -f "$env_file" ]; then
        # Get all ADDITIONAL_WORKERS values and combine them
        current_additional_workers=$(grep -E "^ADDITIONAL_WORKERS=" "$env_file" | cut -d'=' -f2 | tr -d '"' | paste -sd ',' | tr -d '\n' || echo "")
        # Remove empty values and clean up
        current_additional_workers=$(echo "$current_additional_workers" | sed 's/,\+/,/g' | sed 's/^,\|,$//g' | sed 's/,,\+/,/g')
        if [ "$current_additional_workers" = "" ]; then
            current_additional_workers=""
        fi
        
        # Get all ADDITIONAL_CONTROLPLANES values and combine them
        current_additional_controlplanes=$(grep -E "^ADDITIONAL_CONTROLPLANES=" "$env_file" | cut -d'=' -f2 | tr -d '"' | paste -sd ',' | tr -d '\n' || echo "")
        # Remove empty values and clean up
        current_additional_controlplanes=$(echo "$current_additional_controlplanes" | sed 's/,\+/,/g' | sed 's/^,\|,$//g' | sed 's/,,\+/,/g')
        if [ "$current_additional_controlplanes" = "" ]; then
            current_additional_controlplanes=""
        fi
    fi
    
    # Combine all additional nodes
    all_nodes=()
    if [ -n "$current_additional_workers" ]; then
        IFS=',' read -ra worker_nodes <<< "$current_additional_workers"
        for node in "${worker_nodes[@]}"; do
            all_nodes+=("$node (worker)")
        done
    fi
    if [ -n "$current_additional_controlplanes" ]; then
        IFS=',' read -ra cp_nodes <<< "$current_additional_controlplanes"
        for node in "${cp_nodes[@]}"; do
            all_nodes+=("$node (control plane)")
        done
    fi
    
    if [ ${#all_nodes[@]} -eq 0 ]; then
        log_validation "No additional nodes found to remove."
        log_validation "Base nodes (controlplane, worker1, worker2) cannot be removed with this command."
        exit 1
    fi
    
    # Show available nodes
    echo ""
    log_info "Available nodes to remove:"
    for i in "${!all_nodes[@]}"; do
        echo "$((i+1)). ${all_nodes[i]}"
    done
    
    echo
    read -p "Enter the number of the node to remove: " choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#all_nodes[@]} ]; then
        log_error "Invalid choice."
        exit 1
    fi
    
    selected_node="${all_nodes[$((choice-1))]}"
    # Extract just the node name (before the parentheses)
    node_name="${selected_node%% (*}"
    # Extract node type (between parentheses)
    node_type="${selected_node##*\(}"
    node_type="${node_type%\)*}"
    
    echo ""
    log_error "This will remove node: $node_name (type: $node_type)"
    log_error "The VM will be destroyed and cannot be recovered!"
    echo ""
    read -p "Are you sure? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        return 0
    fi
    
    # Remove from appropriate variable
    if [ "$node_type" = "worker" ]; then
        # Remove from ADDITIONAL_WORKERS
        log_debug "current_additional_workers='$current_additional_workers'"
        log_debug "node_name='$node_name'"
        
        # Extract numeric part of node name (e.g., worker3 -> 3)
        node_number=""
        if [[ "$node_name" =~ ^worker-([0-9]+)$ ]]; then
            node_number="${BASH_REMATCH[1]}"
            log_debug "detected new format node name with number $node_number"
        elif [[ "$node_name" =~ ^worker([0-9]+)$ ]]; then
            node_number="${BASH_REMATCH[1]}"
            log_debug "detected legacy format node name with number $node_number"
        fi
        
        if [ -n "$current_additional_workers" ]; then
            IFS=',' read -ra worker_array <<< "$current_additional_workers"
            log_debug "worker_array=(${worker_array[@]})"
            
            new_workers=()
            for worker in "${worker_array[@]}"; do
                log_debug "checking worker='$worker' vs node_name='$node_name'"
                
                # Check for both old and new format matches
                if [ "$worker" != "$node_name" ]; then
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
            
            log_debug "new_workers=(${new_workers[@]})"
            log_debug "new_workers length=${#new_workers[@]}"
            
            # Remove all existing ADDITIONAL_WORKERS lines (including commented ones)
            sed -i '/^#\?ADDITIONAL_WORKERS=/d' "$env_file"
            
            if [ ${#new_workers[@]} -eq 0 ]; then
                echo 'ADDITIONAL_WORKERS=""' >> "$env_file"
            else
                new_additional_workers=$(IFS=','; echo "${new_workers[*]}")
                echo "ADDITIONAL_WORKERS=\"$new_additional_workers\"" >> "$env_file"
            fi
        fi
    else
        # Remove from ADDITIONAL_CONTROLPLANES
        
        # Extract numeric part of node name (e.g., controlplane2 -> 2)
        node_number=""
        if [[ "$node_name" =~ ^controlplane-([0-9]+)$ ]]; then
            node_number="${BASH_REMATCH[1]}"
            log_debug "detected new format controlplane name with number $node_number"
        elif [[ "$node_name" =~ ^controlplane([0-9]+)$ ]]; then
            node_number="${BASH_REMATCH[1]}"
            log_debug "detected legacy format controlplane name with number $node_number"
        fi
        
        if [ -n "$current_additional_controlplanes" ]; then
            IFS=',' read -ra cp_array <<< "$current_additional_controlplanes"
            log_debug "cp_array=(${cp_array[@]})"
            
            new_cps=()
            for cp in "${cp_array[@]}"; do
                log_debug "checking cp='$cp' vs node_name='$node_name'"
                
                # Check for both old and new format matches
                if [ "$cp" != "$node_name" ]; then
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
                new_additional_controlplanes=$(IFS=','; echo "${new_cps[*]}")
                echo "ADDITIONAL_CONTROLPLANES=\"$new_additional_controlplanes\"" >> "$env_file"
            fi
        fi
    fi
    
    log_success "Updated configuration file"
    
    # Get VM info before destruction to verify removal
    log_info "Getting current VM information..."
    vm_count_before=$("$REPO_PATH/cpc" deploy output -json cluster_summary 2>/dev/null | jq '. | length' 2>/dev/null || echo "unknown")
    
    # Destroy VM with Terraform
    log_info "Destroying VM with Terraform..."
    if ! "$REPO_PATH/cpc" deploy apply -auto-approve; then
        log_error "Failed to apply Terraform changes"
        exit 1
    fi
    
    # Verify VM was actually removed
    log_info "Verifying VM removal..."
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
    
    log_info "Note: If the node was part of Kubernetes cluster, you may need to manually clean up the cluster state."
}

log_debug "Module 10_proxmox.sh loaded successfully"
