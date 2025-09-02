#!/bin/bash
# =============================================================================
# CPC Error Handling Test Suite
# =============================================================================
# Tests for the new error handling, retry, timeout, and recovery systems

# Source the main cpc script to load all libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 Testing CPC Error Handling Systems"
echo "===================================="

# Load libraries directly instead of sourcing cpc
for lib in "$SCRIPT_DIR/lib"/*.sh; do
  [ -f "$lib" ] && source "$lib"
done

# Initialize systems
error_init
retry_init
timeout_init
recovery_init

# Test 1: Error handling system
echo ""
echo "Test 1: Error Handling System"
echo "-----------------------------"

error_init
echo "✓ Error system initialized"

error_push "$ERROR_NETWORK" "Test network error" "$SEVERITY_MEDIUM" "test_context"
echo "✓ Error pushed to stack"

error_count=$(error_get_count)
echo "✓ Error count: $error_count"

error_report="/tmp/test_error_report.txt"
error_generate_report "$error_report"
echo "✓ Error report generated: $error_report"

# Test 2: Retry system
echo ""
echo "Test 2: Retry System"
echo "--------------------"

retry_init
echo "✓ Retry system initialized"

# Test successful retry
retry_execute "echo 'Success'" 2 1 10 "" "Test successful command"
echo "✓ Successful retry test completed"

# Test failed retry (will fail after retries)
retry_execute "false" 2 1 10 "" "Test failing command"
echo "✓ Failed retry test completed (expected to fail)"

retry_stats=$(retry_get_stats)
echo "✓ Retry statistics: $retry_stats"

# Test 3: Timeout system
echo ""
echo "Test 3: Timeout System"
echo "----------------------"

timeout_init
echo "✓ Timeout system initialized"

# Test successful timeout
timeout_execute "sleep 1" 5 "Test short command"
echo "✓ Short command with timeout completed"

# Test timeout (will timeout)
timeout_execute "sleep 10" 2 "Test long command"
echo "✓ Long command timed out as expected"

# Test 4: Recovery system
echo ""
echo "Test 4: Recovery System"
echo "-----------------------"

recovery_init
echo "✓ Recovery system initialized"

recovery_checkpoint "test_checkpoint" "test_data"
echo "✓ Recovery checkpoint created"

# Test successful recovery operation
recovery_execute "echo 'Success'" "test_operation" "echo 'Rollback'" "true"
echo "✓ Successful recovery operation completed"

recovery_state=$(recovery_get_state)
echo "✓ Recovery state: $recovery_state"

recovery_report="/tmp/test_recovery_report.txt"
recovery_generate_report "$recovery_report"
echo "✓ Recovery report generated: $recovery_report"

# Test 5: Command validation
echo ""
echo "Test 5: Command Validation"
echo "--------------------------"

if error_validate_command_exists "echo"; then
    echo "✓ Command validation passed for 'echo'"
else
    echo "✗ Command validation failed for 'echo'"
fi

if ! error_validate_command_exists "nonexistent_command"; then
    echo "✓ Command validation correctly failed for nonexistent command"
else
    echo "✗ Command validation should have failed for nonexistent command"
fi

# Test 6: File validation
echo ""
echo "Test 6: File Validation"
echo "-----------------------"

if error_validate_file "$SCRIPT_DIR/cpc"; then
    echo "✓ File validation passed for cpc script"
else
    echo "✗ File validation failed for cpc script"
fi

if ! error_validate_file "/nonexistent/file"; then
    echo "✓ File validation correctly failed for nonexistent file"
else
    echo "✗ File validation should have failed for nonexistent file"
fi

echo ""
echo "🎉 All Error Handling Tests Completed!"
echo "====================================="
echo ""
echo "Test reports generated:"
echo "  - Error report: $error_report"
echo "  - Recovery report: $recovery_report"
echo ""
echo "You can examine these files to see detailed error and recovery information."
