#!/bin/bash
# Bash Test Framework for CPC
# Provides utilities for testing bash functions and scripts

# Colors for test output
readonly TEST_RED='\033[0;31m'
readonly TEST_GREEN='\033[0;32m'
readonly TEST_YELLOW='\033[1;33m'
readonly TEST_BLUE='\033[0;34m'
readonly TEST_NC='\033[0m' # No Color

# Test statistics
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Test configuration
TEST_WORKSPACE="test-framework-$(date +%s)"
TEST_LOG_FILE="/tmp/cpc_test_$(date +%s).log"
ORIGINAL_WORKSPACE=""

# Setup test environment
setup_test_env() {
    echo -e "${TEST_BLUE}=== Setting up test environment ===${TEST_NC}"
    
    # Save original workspace
    if ORIGINAL_WORKSPACE=$(./cpc ctx 2>/dev/null | grep "Current cluster context:" | cut -d' ' -f4); then
        echo "Saved original workspace: $ORIGINAL_WORKSPACE"
    fi
    
    # Create test directory structure
    mkdir -p /tmp/cpc_test_env
    export CPC_TEST_MODE=1
    export CPC_TEST_DIR="/tmp/cpc_test_env"
    
    echo "Test environment ready"
}

# Cleanup test environment  
cleanup_test_env() {
    echo -e "${TEST_BLUE}=== Cleaning up test environment ===${TEST_NC}"
    
    # Restore original workspace if it exists
    if [[ -n "$ORIGINAL_WORKSPACE" ]]; then
        ./cpc ctx "$ORIGINAL_WORKSPACE" >/dev/null 2>&1 || true
    fi
    
    # Clean test workspace if created
    if [[ -n "$TEST_WORKSPACE" ]]; then
        ./cpc delete-workspace "$TEST_WORKSPACE" >/dev/null 2>&1 || true
    fi
    
    # Clean temporary files
    rm -rf /tmp/cpc_test_env 2>/dev/null || true
    rm -f "$TEST_LOG_FILE" 2>/dev/null || true
    
    echo "Cleanup completed"
}

# Assert functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="${3:-assertion}"
    
    ((TESTS_RUN++))
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: $test_name${TEST_NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${TEST_RED}✗ FAIL: $test_name${TEST_NC}"
        echo -e "${TEST_RED}  Expected: '$expected'${TEST_NC}"
        echo -e "${TEST_RED}  Actual:   '$actual'${TEST_NC}"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="${3:-contains assertion}"
    
    ((TESTS_RUN++))
    
    if [[ "$haystack" =~ $needle ]]; then
        echo -e "${TEST_GREEN}✓ PASS: $test_name${TEST_NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${TEST_RED}✗ FAIL: $test_name${TEST_NC}"
        echo -e "${TEST_RED}  String '$haystack' does not contain '$needle'${TEST_NC}"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_command_succeeds() {
    local command="$1"
    local test_name="${2:-command success}"
    
    ((TESTS_RUN++))
    
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${TEST_GREEN}✓ PASS: $test_name${TEST_NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${TEST_RED}✗ FAIL: $test_name${TEST_NC}"
        echo -e "${TEST_RED}  Command failed: $command${TEST_NC}"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_command_fails() {
    local command="$1"
    local test_name="${2:-command failure}"
    
    ((TESTS_RUN++))
    
    if ! eval "$command" >/dev/null 2>&1; then
        echo -e "${TEST_GREEN}✓ PASS: $test_name${TEST_NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${TEST_RED}✗ FAIL: $test_name${TEST_NC}"
        echo -e "${TEST_RED}  Command should have failed: $command${TEST_NC}"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_exists() {
    local filepath="$1"
    local test_name="${2:-file exists: $filepath}"
    
    ((TESTS_RUN++))
    
    if [[ -f "$filepath" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: $test_name${TEST_NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${TEST_RED}✗ FAIL: $test_name${TEST_NC}"
        echo -e "${TEST_RED}  File does not exist: $filepath${TEST_NC}"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_not_exists() {
    local filepath="$1"
    local test_name="${2:-file does not exist: $filepath}"
    
    ((TESTS_RUN++))
    
    if [[ ! -f "$filepath" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: $test_name${TEST_NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${TEST_RED}✗ FAIL: $test_name${TEST_NC}"
        echo -e "${TEST_RED}  File should not exist: $filepath${TEST_NC}"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test runner functions
run_test_suite() {
    local test_suite_name="$1"
    local test_function="$2"
    
    echo -e "${TEST_BLUE}=== Running Test Suite: $test_suite_name ===${TEST_NC}"
    
    # Run the test function
    if declare -f "$test_function" >/dev/null; then
        "$test_function"
    else
        echo -e "${TEST_RED}Test function '$test_function' not found${TEST_NC}"
        return 1
    fi
}

# Print test results
print_test_results() {
    echo
    echo -e "${TEST_BLUE}=== Test Results ===${TEST_NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "${TEST_GREEN}Passed: $TESTS_PASSED${TEST_NC}"
    echo -e "${TEST_RED}Failed: $TESTS_FAILED${TEST_NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo
        echo -e "${TEST_RED}Failed tests:${TEST_NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "${TEST_RED}  - $test${TEST_NC}"
        done
        return 1
    else
        echo -e "${TEST_GREEN}All tests passed!${TEST_NC}"
        return 0
    fi
}

# Mock functions for testing
mock_sops_decrypt() {
    cat << 'EOF'
PROXMOX_HOST: test-proxmox.local
PROXMOX_USERNAME: test-user
VM_USERNAME: ubuntu
VM_SSH_KEY: /home/user/.ssh/id_rsa
HARBOR_HOSTNAME: harbor.test.local
EOF
}

mock_terraform_output() {
    cat << 'EOF'
{
  "vm1": {
    "IP": "10.10.10.120",
    "Name": "test-controlplane-1"
  },
  "vm2": {
    "IP": "10.10.10.125",
    "Name": "test-worker-1"
  }
}
EOF
}

# Export functions for use in test scripts
export -f setup_test_env cleanup_test_env
export -f assert_equals assert_contains assert_command_succeeds assert_command_fails
export -f assert_file_exists assert_file_not_exists
export -f run_test_suite print_test_results
export -f mock_sops_decrypt mock_terraform_output
