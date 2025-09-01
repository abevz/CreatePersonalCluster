#!/bin/bash
# =============================================================================
# CPC Timeout Library
# =============================================================================
# Timeout handling and management for CreatePersonalCluster

# Default timeout values (in seconds)
declare -i DEFAULT_COMMAND_TIMEOUT=300      # 5 minutes
declare -i DEFAULT_NETWORK_TIMEOUT=30       # 30 seconds
declare -i DEFAULT_ANSIBLE_TIMEOUT=1800     # 30 minutes
declare -i DEFAULT_KUBECTL_TIMEOUT=120      # 2 minutes
declare -i DEFAULT_TERRAFORM_TIMEOUT=3600   # 1 hour

# Timeout tracking
declare -a ACTIVE_TIMEOUTS=()
declare -i TIMEOUT_COUNT=0

# Initialize timeout system
timeout_init() {
    ACTIVE_TIMEOUTS=()
    TIMEOUT_COUNT=0
    log_debug "Timeout system initialized"
}

# Execute command with timeout
timeout_execute() {
    local command="$1"
    local timeout_seconds="${2:-$DEFAULT_COMMAND_TIMEOUT}"
    local description="${3:-Command execution}"
    local cleanup_command="${4:-}"

    local timeout_id="timeout_$$_$TIMEOUT_COUNT"
    TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))

    log_info "Executing $description with ${timeout_seconds}s timeout"

    # Add to active timeouts
    ACTIVE_TIMEOUTS+=("$timeout_id")

    # Execute with timeout
    if timeout "$timeout_seconds" bash -c "$command"; then
        local exit_code=$?
        # Remove from active timeouts
        ACTIVE_TIMEOUTS=("${ACTIVE_TIMEOUTS[@]/$timeout_id}")
        return $exit_code
    else
        local exit_code=$?
        log_warning "$description timed out after ${timeout_seconds}s"

        # Execute cleanup if provided
        if [[ -n "$cleanup_command" ]]; then
            log_info "Executing cleanup: $cleanup_command"
            eval "$cleanup_command" || log_warning "Cleanup command failed"
        fi

        # Remove from active timeouts
        ACTIVE_TIMEOUTS=("${ACTIVE_TIMEOUTS[@]/$timeout_id}")

        error_handle "$ERROR_TIMEOUT" "$description timed out after ${timeout_seconds}s" "$SEVERITY_HIGH"
        return 124  # timeout exit code
    fi
}

# Execute network operation with timeout
timeout_network_operation() {
    local command="$1"
    local description="${2:-Network operation}"
    local timeout_seconds="${3:-$DEFAULT_NETWORK_TIMEOUT}"

    timeout_execute "$command" "$timeout_seconds" "$description"
}

# Execute Ansible operation with timeout
timeout_ansible_operation() {
    local ansible_command="$1"
    local description="${2:-Ansible operation}"
    local timeout_seconds="${3:-$DEFAULT_ANSIBLE_TIMEOUT}"

    # Ansible-specific cleanup (kill any hanging ansible processes)
    local cleanup_command="pkill -f 'ansible-playbook' || true"

    timeout_execute "$ansible_command" "$timeout_seconds" "$description" "$cleanup_command"
}

# Execute kubectl operation with timeout
timeout_kubectl_operation() {
    local kubectl_command="$1"
    local description="${2:-kubectl operation}"
    local timeout_seconds="${3:-$DEFAULT_KUBECTL_TIMEOUT}"

    timeout_execute "$kubectl_command" "$timeout_seconds" "$description"
}

# Execute Terraform/OpenTofu operation with timeout
timeout_terraform_operation() {
    local tf_command="$1"
    local description="${2:-Terraform operation}"
    local timeout_seconds="${3:-$DEFAULT_TERRAFORM_TIMEOUT}"

    # Terraform-specific cleanup
    local cleanup_command="pkill -f 'terraform|tofu' || true"

    timeout_execute "$tf_command" "$timeout_seconds" "$description" "$cleanup_command"
}

# Execute with progress monitoring and timeout
timeout_with_progress() {
    local command="$1"
    local timeout_seconds="${2:-$DEFAULT_COMMAND_TIMEOUT}"
    local description="${3:-Operation}"
    local progress_interval="${4:-10}"

    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout_seconds))

    log_info "Starting $description (timeout: ${timeout_seconds}s)"

    # Start command in background
    eval "$command" &
    local pid=$!

    # Monitor progress
    while kill -0 "$pid" 2>/dev/null; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local remaining=$((end_time - current_time))

        if [[ $remaining -le 0 ]]; then
            log_warning "$description timed out"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            kill -KILL "$pid" 2>/dev/null || true
            error_handle "$ERROR_TIMEOUT" "$description timed out after ${timeout_seconds}s" "$SEVERITY_HIGH"
            return 124
        fi

        # Show progress every interval
        if [[ $((elapsed % progress_interval)) -eq 0 ]]; then
            local progress=$((elapsed * 100 / timeout_seconds))
            log_info "$description progress: ${progress}% (${elapsed}s elapsed, ${remaining}s remaining)"
        fi

        sleep 1
    done

    # Wait for command to finish and get exit code
    wait "$pid"
    local exit_code=$?

    local total_time=$(( $(date +%s) - start_time ))
    log_success "$description completed in ${total_time}s"

    return $exit_code
}

# Check if operation is within time budget
timeout_check_budget() {
    local start_time="$1"
    local budget_seconds="$2"
    local operation_name="${3:-operation}"

    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    if [[ $elapsed -ge $budget_seconds ]]; then
        error_handle "$ERROR_TIMEOUT" "$operation_name exceeded time budget (${elapsed}s >= ${budget_seconds}s)" "$SEVERITY_HIGH"
        return 1
    else
        local remaining=$((budget_seconds - elapsed))
        log_debug "$operation_name time budget: ${elapsed}s used, ${remaining}s remaining"
        return 0
    fi
}

# Get active timeout count
timeout_get_active_count() {
    echo "${#ACTIVE_TIMEOUTS[@]}"
}

# Cancel all active timeouts
timeout_cancel_all() {
    local count="${#ACTIVE_TIMEOUTS[@]}"
    if [[ $count -gt 0 ]]; then
        log_warning "Cancelling $count active timeout operations"
        for timeout_id in "${ACTIVE_TIMEOUTS[@]}"; do
            # Try to find and kill processes associated with this timeout
            # This is a best-effort cleanup
            pkill -f "$timeout_id" 2>/dev/null || true
        done
        ACTIVE_TIMEOUTS=()
    fi
}

# Set custom timeout values from configuration
timeout_load_config() {
    local config_file="${1:-$SCRIPT_DIR/config.conf}"

    if [[ -f "$config_file" ]]; then
        # Read timeout values from config if they exist
        local cmd_timeout
        cmd_timeout=$(grep -Po '^command_timeout\s*=\s*\K.*' "$config_file" 2>/dev/null || echo "")
        [[ -n "$cmd_timeout" ]] && DEFAULT_COMMAND_TIMEOUT="$cmd_timeout"

        local net_timeout
        net_timeout=$(grep -Po '^network_timeout\s*=\s*\K.*' "$config_file" 2>/dev/null || echo "")
        [[ -n "$net_timeout" ]] && DEFAULT_NETWORK_TIMEOUT="$net_timeout"

        local ansible_timeout
        ansible_timeout=$(grep -Po '^ansible_timeout\s*=\s*\K.*' "$config_file" 2>/dev/null || echo "")
        [[ -n "$ansible_timeout" ]] && DEFAULT_ANSIBLE_TIMEOUT="$ansible_timeout"

        log_debug "Loaded timeout configuration from $config_file"
    fi
}

# Export functions
export -f timeout_init timeout_execute timeout_network_operation
export -f timeout_ansible_operation timeout_kubectl_operation timeout_terraform_operation
export -f timeout_with_progress timeout_check_budget
export -f timeout_get_active_count timeout_cancel_all timeout_load_config
