#!/bin/bash
# =============================================================================
# CPC Error Handling Library
# =============================================================================
# Centralized error handling system for CreatePersonalCluster

# Error codes and categories
declare -r ERROR_NETWORK=100
declare -r ERROR_AUTH=101
declare -r ERROR_CONFIG=102
declare -r ERROR_DEPENDENCY=103
declare -r ERROR_TIMEOUT=104
declare -r ERROR_VALIDATION=105
declare -r ERROR_EXECUTION=106
declare -r ERROR_UNKNOWN=199

# Error severity levels
declare -r SEVERITY_CRITICAL=1
declare -r SEVERITY_HIGH=2
declare -r SEVERITY_MEDIUM=3
declare -r SEVERITY_LOW=4
declare -r SEVERITY_INFO=5

# Global error tracking
declare -a ERROR_STACK=()
declare -i ERROR_COUNT=0
declare -i LAST_ERROR_CODE=0
declare LAST_ERROR_MESSAGE=""
declare ERROR_CORRELATION_ID=""

# Initialize error handling
error_init() {
    ERROR_STACK=()
    ERROR_COUNT=0
    LAST_ERROR_CODE=0
    LAST_ERROR_MESSAGE=""
    ERROR_CORRELATION_ID=$(date +%s)-$$
    log_debug "Error handling initialized with correlation ID: $ERROR_CORRELATION_ID"
}

# Push error to stack
error_push() {
    local code="$1"
    local message="$2"
    local severity="${3:-$SEVERITY_MEDIUM}"
    local context="${4:-}"

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local error_entry="$timestamp|$code|$severity|$message|$context"
    ERROR_STACK+=("$error_entry")

    ERROR_COUNT=$((ERROR_COUNT + 1))
    LAST_ERROR_CODE="$code"
    LAST_ERROR_MESSAGE="$message"

    log_error "[$code] $message"
    if [[ -n "$context" ]]; then
        log_debug "Context: $context"
    fi
}

# Get last error
error_get_last() {
    if [[ ${#ERROR_STACK[@]} -gt 0 ]]; then
        echo "${ERROR_STACK[-1]}"
    fi
}

# Get error count
error_get_count() {
    echo "$ERROR_COUNT"
}

# Check if there are critical errors
error_has_critical() {
    for error in "${ERROR_STACK[@]}"; do
        IFS='|' read -r timestamp code severity message context <<< "$error"
        if [[ "$severity" -eq "$SEVERITY_CRITICAL" ]]; then
            return 0
        fi
    done
    return 1
}

# Clear error stack
error_clear() {
    ERROR_STACK=()
    ERROR_COUNT=0
    LAST_ERROR_CODE=0
    LAST_ERROR_MESSAGE=""
}

# Handle error with appropriate action
error_handle() {
    local code="$1"
    local message="$2"
    local severity="${3:-$SEVERITY_MEDIUM}"
    local action="${4:-continue}" # continue, retry, abort, warn

    error_push "$code" "$message" "$severity"

    case "$action" in
        "abort")
            log_fatal "Critical error encountered. Aborting operation."
            ;;
        "retry")
            log_warning "Error encountered. Will retry operation."
            return 1  # Signal to retry
            ;;
        "warn")
            log_warning "Non-critical error: $message"
            return 0  # Continue execution
            ;;
        "continue"|*)
            log_error "Error encountered but continuing: $message"
            return 0
            ;;
    esac
}

# Validate command execution
error_validate_command() {
    local command="$1"
    local expected_exit="${2:-0}"
    local error_message="${3:-Command failed}"
    local severity="${4:-$SEVERITY_MEDIUM}"

    log_debug "Executing: $command"

    if eval "$command"; then
        return 0
    else
        local actual_exit=$?
        error_handle "$ERROR_EXECUTION" "$error_message (exit code: $actual_exit)" "$severity"
        return 1
    fi
}

# Validate file existence
error_validate_file() {
    local file_path="$1"
    local error_message="${2:-File not found: $file_path}"

    if [[ -f "$file_path" ]]; then
        return 0
    else
        error_handle "$ERROR_VALIDATION" "$error_message" "$SEVERITY_HIGH"
        return 1
    fi
}

# Validate directory existence
error_validate_directory() {
    local dir_path="$1"
    local error_message="${2:-Directory not found: $dir_path}"

    if [[ -d "$dir_path" ]]; then
        return 0
    else
        error_handle "$ERROR_VALIDATION" "$error_message" "$SEVERITY_HIGH"
        return 1
    fi
}

# Validate network connectivity
error_validate_network() {
    local host="$1"
    local port="${2:-}"
    local timeout="${3:-5}"
    local error_message="${4:-Network connection failed}"

    if [[ -n "$port" ]]; then
        if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            return 0
        fi
    else
        if timeout "$timeout" ping -c 1 -W 1 "$host" >/dev/null 2>&1; then
            return 0
        fi
    fi

    error_handle "$ERROR_NETWORK" "$error_message (host: $host, port: $port)" "$SEVERITY_HIGH"
    return 1
}

# Validate required command
error_validate_command_exists() {
    local command="$1"
    local package_hint="${2:-}"

    if command -v "$command" >/dev/null 2>&1; then
        return 0
    else
        local message="Required command '$command' not found"
        if [[ -n "$package_hint" ]]; then
            message="$message. Try: $package_hint"
        fi
        error_handle "$ERROR_DEPENDENCY" "$message" "$SEVERITY_CRITICAL" "abort"
        return 1
    fi
}

# Generate error report
error_generate_report() {
    local output_file="${1:-/tmp/cpc_error_report.txt}"

    {
        echo "=== CPC Error Report ==="
        echo "Correlation ID: $ERROR_CORRELATION_ID"
        echo "Timestamp: $(date)"
        echo "Total Errors: $ERROR_COUNT"
        echo ""

        if [[ ${#ERROR_STACK[@]} -gt 0 ]]; then
            echo "=== Error Details ==="
            printf "%-20s %-5s %-8s %-50s %s\n" "TIMESTAMP" "CODE" "SEVERITY" "MESSAGE" "CONTEXT"
            echo "----------------------------------------------------------------------------------------------------"

            for error in "${ERROR_STACK[@]}"; do
                IFS='|' read -r timestamp code severity message context <<< "$error"
                printf "%-20s %-5s %-8s %-50s %s\n" "$timestamp" "$code" "$severity" "$message" "$context"
            done
        else
            echo "No errors recorded."
        fi

        echo ""
        echo "=== System Information ==="
        echo "OS: $(uname -s) $(uname -r)"
        echo "Shell: $SHELL"
        echo "User: $(whoami)"
        echo "Working Directory: $(pwd)"

    } > "$output_file"

    log_info "Error report generated: $output_file"
}

# Export functions
export -f error_init error_push error_get_last error_get_count
export -f error_has_critical error_clear error_handle
export -f error_validate_command error_validate_file error_validate_directory
export -f error_validate_network error_validate_command_exists
export -f error_generate_report
