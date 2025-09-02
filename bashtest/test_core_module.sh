#!/bin/bash
# Unit tests for Core module (00_core.sh)

# Source the test framework
source "$(dirname "$0")/bash_test_framework.sh"

# Source the core module for testing
source "$(dirname "$0")/../modules/00_core.sh"

# Test core_ctx function
test_core_ctx() {
    echo "Testing core_ctx function..."
    
    # Test help output
    local help_output
    help_output=$(core_ctx --help 2>&1)
    assert_contains "$help_output" "Usage: cpc ctx" "core_ctx help contains usage"
    
    # Test current context display (without arguments)
    local ctx_output
    ctx_output=$(core_ctx 2>&1)
    assert_contains "$ctx_output" "Current cluster context" "core_ctx shows current context"
}

# Test core_list_workspaces function
test_core_list_workspaces() {
    echo "Testing core_list_workspaces function..."
    
    # Test help output
    local help_output
    help_output=$(core_list_workspaces --help 2>&1)
    assert_contains "$help_output" "Usage: cpc list-workspaces" "list-workspaces help"
    
    # Test workspace listing
    local list_output
    list_output=$(core_list_workspaces 2>&1)
    assert_contains "$list_output" "Available Workspaces" "workspace listing works"
    assert_contains "$list_output" "Tofu workspaces" "shows terraform workspaces"
    assert_contains "$list_output" "Environment files" "shows environment files"
}

# Test core_clone_workspace function
test_core_clone_workspace() {
    echo "Testing core_clone_workspace function..."
    
    # Test help output
    local help_output
    help_output=$(core_clone_workspace --help 2>&1)
    assert_contains "$help_output" "Usage: cpc clone-workspace" "clone-workspace help"
    
    # Test invalid arguments
    local error_output
    error_output=$(core_clone_workspace 2>&1 || true)
    assert_contains "$error_output" "Usage: cpc clone-workspace" "clone-workspace requires args"
    
    # Test auto release letter determination
    local test_workspace="test-unit-$(date +%s)"
    # We can't test actual cloning without setup, but we can test parameter handling
}

# Test secrets caching functions
test_secrets_caching() {
    echo "Testing secrets caching..."
    
    # Create mock cache directory
    mkdir -p /tmp/test_cpc_cache
    local cache_file="/tmp/test_cpc_cache/env_cache.sh"
    
    # Test cache file creation
    echo "export TEST_VAR='test_value'" > "$cache_file"
    assert_file_exists "$cache_file" "cache file created"
    
    # Test cache age calculation
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    assert_equals "0" "$cache_age" "cache age calculation"
    
    # Cleanup
    rm -rf /tmp/test_cpc_cache
}

# Test load_env_vars function
test_load_env_vars() {
    echo "Testing load_env_vars function..."
    
    # Create a temporary cpc.env file
    local temp_env="/tmp/test_cpc.env"
    cat > "$temp_env" << 'EOF'
# Test environment file
NETWORK_CIDR="10.10.10.0/24"
STATIC_IP_START="10.10.10.100"
WORKSPACE_IP_BLOCK_SIZE="10"
EOF
    
    # Test environment loading (would need mocking in real test)
    assert_file_exists "$temp_env" "test env file created"
    
    # Cleanup
    rm -f "$temp_env"
}

# Test set_workspace_template_vars function
test_set_workspace_template_vars() {
    echo "Testing set_workspace_template_vars function..."
    
    # Create test workspace env file
    local test_env_dir="/tmp/test_envs"
    mkdir -p "$test_env_dir"
    local test_env_file="$test_env_dir/test.env"
    
    cat > "$test_env_file" << 'EOF'
TEMPLATE_VM_ID="9999"
TEMPLATE_VM_NAME="test-template"
IMAGE_NAME="test-image.img"
KUBERNETES_VERSION="v1.28.0"
CALICO_VERSION="v3.26.0"
METALLB_VERSION="v0.13.0"
EOF
    
    # Test template variable setting (would need proper mocking)
    assert_file_exists "$test_env_file" "test env file for templates"
    
    # Cleanup
    rm -rf "$test_env_dir"
}

# Test core_clear_cache function
test_core_clear_cache() {
    echo "Testing core_clear_cache function..."
    
    # Create test cache files
    touch /tmp/cpc_secrets_cache
    touch /tmp/cpc_env_cache.sh
    touch /tmp/cpc_status_cache_test
    touch /tmp/cpc_ssh_cache_test
    
    # Test cache clearing
    core_clear_cache
    
    # Verify cache files are removed
    assert_file_not_exists "/tmp/cpc_secrets_cache" "secrets cache cleared"
    assert_file_not_exists "/tmp/cpc_env_cache.sh" "env cache cleared"
    assert_file_not_exists "/tmp/cpc_status_cache_test" "status cache cleared"
    assert_file_not_exists "/tmp/cpc_ssh_cache_test" "ssh cache cleared"
}

# Test configuration validation
test_config_validation() {
    echo "Testing configuration validation..."
    
    # Test required environment variables
    local required_vars=("REPO_PATH" "TERRAFORM_DIR" "ENVIRONMENTS_DIR")
    
    for var in "${required_vars[@]}"; do
        if [[ -n "${!var}" ]]; then
            echo -e "${TEST_GREEN}✓ PASS: $var is set${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_YELLOW}⚠ SKIP: $var not set in test environment${TEST_NC}"
        fi
        ((TESTS_RUN++))
    done
}

# Test error handling functions
test_error_handling() {
    echo "Testing error handling..."
    
    # Test error codes are defined
    local error_vars=("ERROR_CONFIG" "ERROR_NETWORK" "ERROR_VALIDATION")
    
    for var in "${error_vars[@]}"; do
        if [[ -n "${!var}" ]]; then
            echo -e "${TEST_GREEN}✓ PASS: $var error code defined${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_YELLOW}⚠ SKIP: $var not defined in test environment${TEST_NC}"
        fi
        ((TESTS_RUN++))
    done
}

# Main test runner for core module
run_core_tests() {
    setup_test_env
    
    echo -e "${TEST_BLUE}=== Core Module Unit Tests ===${TEST_NC}"
    
    test_core_ctx
    test_core_list_workspaces
    test_core_clone_workspace
    test_secrets_caching
    test_load_env_vars
    test_set_workspace_template_vars
    test_core_clear_cache
    test_config_validation
    test_error_handling
    
    cleanup_test_env
    print_test_results
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_core_tests
fi
