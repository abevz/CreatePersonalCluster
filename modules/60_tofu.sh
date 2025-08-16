#!/bin/bash
# modules/60_tofu.sh - Terraform/OpenTofu management module
# Part of the modular CPC architecture

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This module should not be run directly. Use the main cpc script." >&2
    exit 1
fi

# Module: Terraform/OpenTofu functionality
log_debug "Loading module: 60_tofu.sh - Terraform/OpenTofu management"

# Function to handle all Terraform/OpenTofu commands
function cpc_tofu() {
    local command="$1"
    shift
    
    case "$command" in
        deploy)
            tofu_deploy "$@"
            ;;
        start-vms)
            tofu_start_vms "$@"
            ;;
        stop-vms)
            tofu_stop_vms "$@"
            ;;
        generate-hostnames|gen_hostnames)
            tofu_generate_hostnames "$@"
            ;;
        get-kubeconfig)
            tofu_get_kubeconfig "$@"
            ;;
        *)
            log_error "Unknown tofu command: $command"
            return 1
            ;;
    esac
}

# Deploy command - runs OpenTofu/Terraform commands in context
function tofu_deploy() {
    if [[ "$1" == "-h" || "$1" == "--help" ]] || [[ $# -eq 0 ]]; then
        echo "Usage: cpc deploy <tofu_cmd> [options]"
        echo ""
        echo "Run any OpenTofu/Terraform command in the current cpc context."
        echo ""
        echo "Common commands:"
        echo "  plan       Generate and show an execution plan"
        echo "  apply      Build or change infrastructure"
        echo "  destroy    Destroy infrastructure"
        echo "  output     Show output values"
        echo "  init       Initialize a working directory"
        echo "  validate   Validate the configuration files"
        echo "  refresh    Update state file against real resources"
        echo ""
        echo "Examples:"
        echo "  cpc deploy plan"
        echo "  cpc deploy apply -auto-approve"
        echo "  cpc deploy destroy -auto-approve"
        echo "  cpc deploy output k8s_node_ips"
        echo ""
        echo "The command will:"
        echo "  - Load workspace environment variables"
        echo "  - Set appropriate Terraform variables"
        echo "  - Select the correct workspace"
        echo "  - Generate hostname configurations (for plan/apply)"
        echo "  - Execute the OpenTofu command with context-specific tfvars"
        return 0
    fi

    check_secrets_loaded
    current_ctx=$(get_current_cluster_context)

    tf_dir="$REPO_PATH/terraform"
    tfvars_file="$tf_dir/environments/${current_ctx}.tfvars"

    log_info "Preparing to run 'tofu $*' for context '$current_ctx' in $tf_dir..."

    # Load RELEASE_LETTER from workspace environment file if it exists
    env_file="$REPO_PATH/envs/$current_ctx.env"
    if [ -f "$env_file" ]; then
        RELEASE_LETTER=$(grep -E "^RELEASE_LETTER=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        if [ -n "$RELEASE_LETTER" ]; then
            export TF_VAR_release_letter="$RELEASE_LETTER"
            log_info "Using RELEASE_LETTER='$RELEASE_LETTER' from workspace environment file"
        fi
        
        ADDITIONAL_WORKERS=$(grep -E "^ADDITIONAL_WORKERS=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        if [ -n "$ADDITIONAL_WORKERS" ]; then
            export TF_VAR_additional_workers="$ADDITIONAL_WORKERS"
            log_info "Using ADDITIONAL_WORKERS='$ADDITIONAL_WORKERS' from workspace environment file"
        fi
        
        ADDITIONAL_CONTROLPLANES=$(grep -E "^ADDITIONAL_CONTROLPLANES=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        if [ -n "$ADDITIONAL_CONTROLPLANES" ]; then
            export TF_VAR_additional_controlplanes="$ADDITIONAL_CONTROLPLANES"
            log_info "Using ADDITIONAL_CONTROLPLANES='$ADDITIONAL_CONTROLPLANES' from workspace environment file"
        fi
        
        # Static IP configuration variables
        STATIC_IP_BASE=$(grep -E "^STATIC_IP_BASE=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        if [ -n "$STATIC_IP_BASE" ]; then
            export TF_VAR_static_ip_base="$STATIC_IP_BASE"
            log_info "Using STATIC_IP_BASE='$STATIC_IP_BASE' from workspace environment file"
        fi
        
        STATIC_IP_GATEWAY=$(grep -E "^STATIC_IP_GATEWAY=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        if [ -n "$STATIC_IP_GATEWAY" ]; then
            export TF_VAR_static_ip_gateway="$STATIC_IP_GATEWAY"
            log_info "Using STATIC_IP_GATEWAY='$STATIC_IP_GATEWAY' from workspace environment file"
        fi
        
        STATIC_IP_START=$(grep -E "^STATIC_IP_START=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        if [ -n "$STATIC_IP_START" ]; then
            export TF_VAR_static_ip_start="$STATIC_IP_START"
            log_info "Using STATIC_IP_START='$STATIC_IP_START' from workspace environment file"
        fi
        
        # Advanced IP block system variables
        NETWORK_CIDR=$(grep -E "^NETWORK_CIDR=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        if [ -n "$NETWORK_CIDR" ]; then
            export TF_VAR_network_cidr="$NETWORK_CIDR"
            log_info "Using NETWORK_CIDR='$NETWORK_CIDR' from workspace environment file"
        fi
        
        WORKSPACE_IP_BLOCK_SIZE=$(grep -E "^WORKSPACE_IP_BLOCK_SIZE=" "$env_file" | cut -d'=' -f2 | tr -d '"' || echo "")
        if [ -n "$WORKSPACE_IP_BLOCK_SIZE" ]; then
            export TF_VAR_workspace_ip_block_size="$WORKSPACE_IP_BLOCK_SIZE"
            log_info "Using WORKSPACE_IP_BLOCK_SIZE='$WORKSPACE_IP_BLOCK_SIZE' from workspace environment file"
        fi
    fi

    pushd "$tf_dir" > /dev/null || { log_error "Failed to change to directory $tf_dir"; exit 1; }
    
    selected_workspace=$(tofu workspace show)
    if [ "$selected_workspace" != "$current_ctx" ]; then
        log_validation "Warning: Current Tofu workspace ('$selected_workspace') does not match cpc context ('$current_ctx')."
        log_validation "Attempting to select workspace '$current_ctx'..."
        tofu workspace select "$current_ctx"
        if [ $? -ne 0 ]; then
            log_error "Error selecting Tofu workspace '$current_ctx'. Please check your Tofu setup."
            popd > /dev/null
            exit 1
        fi
    fi

    tofu_subcommand="$1"
    shift # Remove subcommand, rest are its arguments

    final_tofu_cmd_array=(tofu "$tofu_subcommand")
    
    # Generate node hostname configurations for Proxmox if applying or planning
    if [ "$tofu_subcommand" = "apply" ] || [ "$tofu_subcommand" = "plan" ]; then
        log_info "Generating node hostname configurations..."
        if [ -x "$REPO_PATH/scripts/generate_node_hostnames.sh" ]; then
            pushd "$REPO_PATH/scripts" > /dev/null
            ./generate_node_hostnames.sh
            HOSTNAME_SCRIPT_STATUS=$?
            popd > /dev/null
            
            if [ $HOSTNAME_SCRIPT_STATUS -ne 0 ]; then
                log_validation "Warning: Hostname generation script returned non-zero status. Some VMs may have incorrect hostnames."
            else
                log_success "Hostname configurations generated successfully."
            fi
        else
            log_validation "Warning: Hostname generation script not found or not executable. Some VMs may have incorrect hostnames."
        fi
    fi

    # Check if the subcommand is one that accepts -var-file
    case "$tofu_subcommand" in
        apply|plan|destroy|import|console)
            if [ -f "$tfvars_file" ]; then
                final_tofu_cmd_array+=("-var-file=$tfvars_file")
                log_info "Using tfvars file: $tfvars_file"
            else
                log_validation "Warning: No specific tfvars file found for context '$current_ctx' at $tfvars_file. Using defaults if applicable."
            fi
            ;;
    esac

    # Append remaining user-provided arguments
    if [[ $# -gt 0 ]]; then
        final_tofu_cmd_array+=("$@")
    fi

    log_info "Executing: ${final_tofu_cmd_array[*]}"
    "${final_tofu_cmd_array[@]}"
    cmd_exit_code=$?

    popd > /dev/null || exit 1

    if [ $cmd_exit_code -ne 0 ]; then
        log_error "'${final_tofu_cmd_array[*]}' failed with exit code $cmd_exit_code."
        exit 1
    fi
    log_success "'${final_tofu_cmd_array[*]}' completed successfully for context '$current_ctx'."
}

# Generate hostname configurations
function tofu_generate_hostnames() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: cpc generate-hostnames"
        echo ""
        echo "Generate node hostname snippets for Proxmox VM templates."
        echo ""
        echo "This command generates Proxmox-specific hostname configuration snippets"
        echo "that are used during VM deployment to set proper hostnames for"
        echo "Kubernetes nodes based on the current workspace context."
        return 0
    fi

    check_secrets_loaded
    log_info "Generating node hostname snippets..."
    if [ -x "$REPO_PATH/scripts/generate_node_hostnames.sh" ]; then
        "$REPO_PATH/scripts/generate_node_hostnames.sh"
        if [ $? -eq 0 ]; then
            log_success "Node hostname configurations generated successfully."
        else
            log_error "Hostname generation failed."
            exit 1
        fi
    else
        log_error "Hostname generation script not found at $REPO_PATH/scripts/generate_node_hostnames.sh"
        exit 1
    fi
}

# Start VMs in current context
function tofu_start_vms() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: cpc start-vms"
        echo ""
        echo "Start all VMs in the current cpc context by running 'tofu apply' with vm_started=true."
        echo ""
        echo "This command will:"
        echo "  - Set vm_started=true for all VMs in the workspace"
        echo "  - Apply the changes automatically"
        echo "  - Start all VMs defined in the current context"
        return 0
    fi
    
    current_ctx=$(get_current_cluster_context)
    log_info "Starting VMs for context '$current_ctx'..."
    
    # Call the deploy command internally to start VMs
    tofu_deploy apply -var="vm_started=true" -auto-approve
    if [ $? -ne 0 ]; then
        log_error "Error starting VMs for context '$current_ctx'."
        exit 1
    fi
    log_success "VMs in context '$current_ctx' should now be starting."
}

# Stop VMs in current context
function tofu_stop_vms() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: cpc stop-vms"
        echo ""
        echo "Stop all VMs in the current cpc context by running 'tofu apply' with vm_started=false."
        echo ""
        echo "This command will:"
        echo "  - Set vm_started=false for all VMs in the workspace"
        echo "  - Apply the changes automatically"
        echo "  - Stop all VMs defined in the current context"
        return 0
    fi
    
    current_ctx=$(get_current_cluster_context)
    log_info "Stopping VMs for context '$current_ctx'..."
    
    # Ask for confirmation before stopping VMs
    read -r -p "Are you sure you want to stop all VMs in context '$current_ctx'? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Operation cancelled."
        return 0
    fi
    
    # Call the deploy command internally to stop VMs
    tofu_deploy apply -var="vm_started=false" -auto-approve
    if [ $? -ne 0 ]; then
        log_error "Error stopping VMs for context '$current_ctx'."
        exit 1
    fi
    log_success "VMs in context '$current_ctx' should now be stopping."
}

# Get kubeconfig from control plane
function tofu_get_kubeconfig() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: cpc get-kubeconfig [--copy-to-clipboard] [--set-context]"
        echo ""
        echo "Retrieve the Kubernetes cluster configuration from the control plane node"
        echo "and save it to ~/.kube/config-<context> or update the default kubeconfig."
        echo ""
        echo "Options:"
        echo "  --copy-to-clipboard    Copy the kubeconfig to the system clipboard"
        echo "  --set-context         Set the retrieved config as the default context"
        echo ""
        echo "This command will:"
        echo "  1. Connect to the control plane node and retrieve /etc/kubernetes/admin.conf"
        echo "  2. Update server endpoint to use the control plane node's IP"
        echo "  3. Save the config to ~/.kube/config-<workspace>"
        echo "  4. Optionally set it as the current kubectl context"
        echo ""
        echo "The kubeconfig is automatically modified to use the external IP address"
        echo "of the control plane node for connectivity from outside the cluster."
        return 0
    fi

    local copy_to_clipboard=false
    local set_context=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --copy-to-clipboard)
                copy_to_clipboard=true
                shift
                ;;
            --set-context)
                set_context=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    check_secrets_loaded
    current_ctx=$(get_current_cluster_context)
    
    log_info "Getting kubeconfig for context '$current_ctx'..."

    # Ensure we're in the terraform directory for tofu commands
    tf_dir="$REPO_PATH/terraform"
    pushd "$tf_dir" > /dev/null || { log_error "Failed to change to directory $tf_dir"; exit 1; }

    # Get control plane IP from Terraform/Tofu output
    local control_plane_ip
    control_plane_ip=$(tofu output -json k8s_node_ips 2>/dev/null | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value')
    
    if [ -z "$control_plane_ip" ] || [ "$control_plane_ip" = "null" ]; then
        log_error "Failed to get control plane IP from Tofu output"
        popd > /dev/null
        exit 1
    fi
    
    log_info "Control plane IP: $control_plane_ip"

    # Get control plane node IP and try to resolve hostname
    local control_plane_hostname
    control_plane_hostname=$(tofu output -json k8s_node_hostnames 2>/dev/null | jq -r 'to_entries[] | select(.key | contains("controlplane")) | .value' 2>/dev/null || echo "")
    
    if [ -n "$control_plane_hostname" ] && [ "$control_plane_hostname" != "null" ]; then
        log_info "Control plane hostname: $control_plane_hostname"
    else
        log_validation "Warning: Could not get hostname from Tofu output"
        control_plane_hostname="$control_plane_ip"
    fi

    popd > /dev/null

    # Get SSH user from ansible.cfg
    local ssh_user
    ssh_user=$(get_ansible_ssh_user)
    if [ -z "$ssh_user" ]; then
        log_error "Could not determine SSH user from ansible.cfg"
        exit 1
    fi

    log_info "Retrieving kubeconfig from $ssh_user@$control_plane_ip..."

    # Retrieve admin.conf from the control plane
    local temp_kubeconfig
    temp_kubeconfig=$(mktemp)
    
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
         "$ssh_user@$control_plane_ip" \
         "sudo cat /etc/kubernetes/admin.conf" > "$temp_kubeconfig" 2>/dev/null; then
        log_error "Failed to retrieve kubeconfig from control plane"
        rm -f "$temp_kubeconfig"
        exit 1
    fi

    # Check if we got a valid kubeconfig
    if [ ! -s "$temp_kubeconfig" ]; then
        log_error "Retrieved kubeconfig is empty"
        rm -f "$temp_kubeconfig"
        exit 1
    fi

    # Modify the server endpoint to use the control plane IP
    local modified_kubeconfig
    modified_kubeconfig=$(mktemp)
    
    # Replace the server URL with the external IP
    if command -v yq &> /dev/null; then
        yq eval ".clusters[0].cluster.server = \"https://$control_plane_ip:6443\"" "$temp_kubeconfig" > "$modified_kubeconfig"
        if [ $? -ne 0 ]; then
            log_validation "Warning: Failed to modify server endpoint with yq, using sed fallback"
            sed "s|server: https://.*:6443|server: https://$control_plane_ip:6443|" "$temp_kubeconfig" > "$modified_kubeconfig"
        fi
    else
        log_info "yq not found, using sed to modify server endpoint"
        sed "s|server: https://.*:6443|server: https://$control_plane_ip:6443|" "$temp_kubeconfig" > "$modified_kubeconfig"
    fi

    # Save the kubeconfig
    local kubeconfig_dir="$HOME/.kube"
    local kubeconfig_file="$kubeconfig_dir/config-$current_ctx"
    
    mkdir -p "$kubeconfig_dir"
    cp "$modified_kubeconfig" "$kubeconfig_file"
    chmod 600 "$kubeconfig_file"
    
    log_success "Kubeconfig saved to $kubeconfig_file"

    # Copy to clipboard if requested
    if [ "$copy_to_clipboard" = true ]; then
        if command -v xclip &> /dev/null; then
            cat "$modified_kubeconfig" | xclip -selection clipboard
            log_success "Kubeconfig copied to clipboard"
        elif command -v pbcopy &> /dev/null; then
            cat "$modified_kubeconfig" | pbcopy
            log_success "Kubeconfig copied to clipboard"
        else
            log_validation "Warning: No clipboard utility found (xclip or pbcopy)"
        fi
    fi

    # Set as current context if requested
    if [ "$set_context" = true ]; then
        export KUBECONFIG="$kubeconfig_file"
        log_success "KUBECONFIG environment variable set to $kubeconfig_file"
        log_info "Run 'export KUBECONFIG=$kubeconfig_file' in your shell to use this config"
    fi

    # Display usage information
    log_info "To use this kubeconfig:"
    log_info "  export KUBECONFIG=$kubeconfig_file"
    log_info "  kubectl get nodes"

    # Clean up temporary files
    rm -f "$temp_kubeconfig" "$modified_kubeconfig"
}

# Function to get ansible SSH user from ansible.cfg
function get_ansible_ssh_user() {
    local ansible_cfg="$REPO_PATH/ansible/ansible.cfg"
    if [ -f "$ansible_cfg" ]; then
        grep -E "^remote_user" "$ansible_cfg" | cut -d'=' -f2 | tr -d ' ' || echo "debian"
    else
        echo "debian"  # Default fallback
    fi
}

log_debug "Module 60_tofu.sh loaded successfully"
