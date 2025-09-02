#!/bin/bash
# =============================================================================
# CPC Retry Library
# =============================================================================
# Retry mechanisms with exponential backoff for CreatePersonalCluster

# Default retry configuration
declare -i DEFAULT_MAX_RETRIES=3
declare -i DEFAULT_BASE_DELAY=2
declare -i DEFAULT_MAX_DELAY=60
declare DEFAULT_BACKOFF_MULTIPLIER=2

# Retry statistics
declare -i RETRY_TOTAL_ATTEMPTS=0
declare -i RETRY_SUCCESSFUL_ATTEMPTS=0
declare -i RETRY_FAILED_ATTEMPTS=0

# Initialize retry system
retry_init() {
    RETRY_TOTAL_ATTEMPTS=0
    RETRY_SUCCESSFUL_ATTEMPTS=0
    RETRY_FAILED_ATTEMPTS=0
    log_debug "Retry system initialized"
}

# Calculate delay with exponential backoff and jitter
retry_calculate_delay() {
    local attempt="$1"
    local base_delay="${2:-$DEFAULT_BASE_DELAY}"
    local max_delay="${3:-$DEFAULT_MAX_DELAY}"
    local multiplier="${4:-$DEFAULT_BACKOFF_MULTIPLIER}"

    local delay=$((base_delay * (multiplier ** (attempt - 1))))

    # Apply maximum delay limit
    if [[ $delay -gt $max_delay ]]; then
        delay=$max_delay
    fi

    # Add jitter (±25% randomization)
    local jitter_range=$((delay / 4))
    if [[ $jitter_range -eq 0 ]]; then
        jitter_range=1
    fi
    local jitter=$((RANDOM % (jitter_range * 2) - jitter_range))
    delay=$((delay + jitter))

    # Ensure minimum delay of 1 second
    if [[ $delay -lt 1 ]]; then
        delay=1
    fi

    echo "$delay"
}

# Execute command with retry logic
retry_execute() {
    local command="$1"
    local max_retries="${2:-$DEFAULT_MAX_RETRIES}"
    local base_delay="${3:-$DEFAULT_BASE_DELAY}"
    local max_delay="${4:-$DEFAULT_MAX_DELAY}"
    local retry_condition="${5:-}" # Optional condition to check for retry
    local description="${6:-Command execution}"

    local attempt=1
    local last_exit_code=0

    while [[ $attempt -le $((max_retries + 1)) ]]; do
        RETRY_TOTAL_ATTEMPTS=$((RETRY_TOTAL_ATTEMPTS + 1))

        log_info "$description (attempt $attempt/$(($max_retries + 1)))"

        # Execute command
        if eval "$command"; then
            RETRY_SUCCESSFUL_ATTEMPTS=$((RETRY_SUCCESSFUL_ATTEMPTS + 1))
            log_success "$description succeeded on attempt $attempt"
            return 0
        else
            last_exit_code=$?
            log_warning "$description failed on attempt $attempt (exit code: $last_exit_code)"

            # Check if we should retry based on custom condition
            if [[ -n "$retry_condition" ]]; then
                if ! eval "$retry_condition"; then
                    log_info "Custom retry condition not met, not retrying"
                    break
                fi
            fi

            # Check if we've exhausted all retries
            if [[ $attempt -gt $max_retries ]]; then
                RETRY_FAILED_ATTEMPTS=$((RETRY_FAILED_ATTEMPTS + 1))
                error_handle "$ERROR_EXECUTION" "$description failed after $max_retries retries" "$SEVERITY_HIGH"
                return $last_exit_code
            fi

            # Calculate delay and wait
            local delay
            delay=$(retry_calculate_delay "$attempt" "$base_delay" "$max_delay")
            log_info "Retrying in $delay seconds..."
            sleep "$delay"
        fi

        attempt=$((attempt + 1))
    done

    return $last_exit_code
}

# Retry network operation
retry_network_operation() {
    local command="$1"
    local description="${2:-Network operation}"
    local max_retries="${3:-5}"  # More retries for network
    local base_delay="${4:-5}"   # Longer base delay for network

    # Network-specific retry condition (retry on connection errors)
    local retry_condition='[[ $last_exit_code -eq 1 || $last_exit_code -eq 28 || $last_exit_code -eq 130 ]]'

    retry_execute "$command" "$max_retries" "$base_delay" "$DEFAULT_MAX_DELAY" "$retry_condition" "$description"
}

# Retry Ansible operation
retry_ansible_operation() {
    local playbook_command="$1"
    local description="${2:-Ansible operation}"
    local max_retries="${3:-2}"  # Fewer retries for Ansible (expensive operations)

    # Ansible-specific retry condition (retry on network/auth errors, not on playbook logic errors)
    local retry_condition='[[ $last_exit_code -eq 1 || $last_exit_code -eq 2 || $last_exit_code -eq 4 ]]'

    retry_execute "$playbook_command" "$max_retries" "$DEFAULT_BASE_DELAY" "$DEFAULT_MAX_DELAY" "$retry_condition" "$description"
}

# Retry with custom validation
retry_with_validation() {
    local command="$1"
    local validation_command="$2"
    local description="${3:-Operation with validation}"
    local max_retries="${4:-$DEFAULT_MAX_RETRIES}"

    local attempt=1
    local last_exit_code=0

    while [[ $attempt -le $((max_retries + 1)) ]]; do
        RETRY_TOTAL_ATTEMPTS=$((RETRY_TOTAL_ATTEMPTS + 1))

        log_info "$description (attempt $attempt/$(($max_retries + 1)))"

        # Execute main command
        if eval "$command"; then
            # Execute validation command
            if eval "$validation_command"; then
                RETRY_SUCCESSFUL_ATTEMPTS=$((RETRY_SUCCESSFUL_ATTEMPTS + 1))
                log_success "$description succeeded and validated on attempt $attempt"
                return 0
            else
                log_warning "Validation failed on attempt $attempt"
                last_exit_code=1
            fi
        else
            last_exit_code=$?
            log_warning "$description failed on attempt $attempt (exit code: $last_exit_code)"
        fi

        # Check if we've exhausted all retries
        if [[ $attempt -gt $max_retries ]]; then
            RETRY_FAILED_ATTEMPTS=$((RETRY_FAILED_ATTEMPTS + 1))
            error_handle "$ERROR_EXECUTION" "$description failed validation after $max_retries retries" "$SEVERITY_HIGH"
            return $last_exit_code
        fi

        # Calculate delay and wait
        local delay
        delay=$(retry_calculate_delay "$attempt")
        log_info "Retrying in $delay seconds..."
        sleep "$delay"

        attempt=$((attempt + 1))
    done

    return $last_exit_code
}

# Get retry statistics
retry_get_stats() {
    echo "Retry Statistics:"
    echo "  Total attempts: $RETRY_TOTAL_ATTEMPTS"
    echo "  Successful: $RETRY_SUCCESSFUL_ATTEMPTS"
    echo "  Failed: $RETRY_FAILED_ATTEMPTS"

    if [[ $RETRY_TOTAL_ATTEMPTS -gt 0 ]]; then
        local success_rate=$((RETRY_SUCCESSFUL_ATTEMPTS * 100 / RETRY_TOTAL_ATTEMPTS))
        echo "  Success rate: $success_rate%"
    fi
}

# Export functions
export -f retry_init retry_calculate_delay retry_execute
export -f retry_network_operation retry_ansible_operation retry_with_validation
export -f retry_get_stats
