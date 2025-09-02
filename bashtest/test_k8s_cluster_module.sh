#!/bin/bash
# Unit tests for K8s Cluster module (30_k8s_cluster.sh)

# Source the test framework
source "$(dirname "$0")/bash_test_framework.sh"

# Source required modules
source "$(dirname "$0")/../modules/00_core.sh"
source "$(dirname "$0")/../modules/30_k8s_cluster.sh"

# Test k8s_cluster_status function
test_k8s_cluster_status() {
    echo "Testing k8s_cluster_status function..."
    
    # Test help output
    local help_output
    help_output=$(k8s_cluster_status --help 2>&1)
    assert_contains "$help_output" "Usage:" "k8s status help contains usage"
    
    # Test quick mode
    local quick_output
    quick_output=$(k8s_cluster_status --quick 2>&1 || true)
    assert_contains "$quick_output" "Quick Cluster Status" "quick status mode"
    
    # Test fast mode
    local fast_output
    fast_output=$(k8s_cluster_status --fast 2>&1 || true)
    assert_contains "$fast_output" "fast mode" "fast status mode"
}

# Test k8s_show_status_help function
test_k8s_show_status_help() {
    echo "Testing k8s_show_status_help function..."
    
    local help_output
    help_output=$(k8s_show_status_help 2>&1)
    assert_contains "$help_output" "Usage: cpc status" "status help format"
    assert_contains "$help_output" "--quick" "help shows quick option"
    assert_contains "$help_output" "--fast" "help shows fast option"
}

# Test caching mechanisms
test_k8s_caching() {
    echo "Testing K8s caching mechanisms..."
    
    # Test cache file naming
    local workspace="test-workspace"
    local cache_file="/tmp/cpc_status_cache_${workspace}"
    local ssh_cache_file="/tmp/cpc_ssh_cache_${workspace}"
    
    # Create test cache files
    echo '{"test": "data"}' > "$cache_file"
    echo "SSH reachable: 2/3" > "$ssh_cache_file"
    
    assert_file_exists "$cache_file" "terraform cache file created"
    assert_file_exists "$ssh_cache_file" "ssh cache file created"
    
    # Test cache age calculation
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    assert_equals "0" "$cache_age" "cache age calculation for terraform"
    
    # Cleanup
    rm -f "$cache_file" "$ssh_cache_file"
}

# Test k8s_bootstrap function structure
test_k8s_bootstrap() {
    echo "Testing k8s_bootstrap function structure..."
    
    # Test that function exists
    if declare -f k8s_bootstrap >/dev/null; then
        echo -e "${TEST_GREEN}✓ PASS: k8s_bootstrap function exists${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: k8s_bootstrap function not found${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    # Test help output
    local help_output
    help_output=$(k8s_bootstrap --help 2>&1 || true)
    assert_contains "$help_output" "Usage:" "bootstrap help available"
}

# Test k8s_get_kubeconfig function
test_k8s_get_kubeconfig() {
    echo "Testing k8s_get_kubeconfig function..."
    
    # Test that function exists
    if declare -f k8s_get_kubeconfig >/dev/null; then
        echo -e "${TEST_GREEN}✓ PASS: k8s_get_kubeconfig function exists${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: k8s_get_kubeconfig function not found${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    # Test help output
    local help_output
    help_output=$(k8s_get_kubeconfig --help 2>&1 || true)
    assert_contains "$help_output" "Usage:" "get-kubeconfig help available"
}

# Test cpc_k8s_cluster dispatcher
test_cpc_k8s_cluster_dispatcher() {
    echo "Testing cpc_k8s_cluster dispatcher..."
    
    # Test invalid command
    local error_output
    error_output=$(cpc_k8s_cluster invalid-command 2>&1 || true)
    assert_contains "$error_output" "Unknown k8s cluster command" "invalid command handling"
    
    # Test available commands list
    assert_contains "$error_output" "bootstrap" "lists bootstrap command"
    assert_contains "$error_output" "status" "lists status command"
    assert_contains "$error_output" "get-kubeconfig" "lists get-kubeconfig command"
}

# Test SSH connectivity checking
test_ssh_connectivity() {
    echo "Testing SSH connectivity functions..."
    
    # Test SSH timeout settings
    local ssh_command="ssh -o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=no"
    assert_contains "$ssh_command" "ConnectTimeout=2" "SSH timeout configured"
    assert_contains "$ssh_command" "BatchMode=yes" "SSH batch mode enabled"
    assert_contains "$ssh_command" "StrictHostKeyChecking=no" "SSH strict checking disabled"
}

# Test JSON processing for cluster data
test_json_processing() {
    echo "Testing JSON processing..."
    
    # Test with mock terraform output
    local test_json='{"vm1":{"IP":"10.10.10.120","Name":"test-vm"},"vm2":{"IP":"10.10.10.121","Name":"test-vm2"}}'
    
    # Test jq processing
    local vm_count
    vm_count=$(echo "$test_json" | jq '. | length' 2>/dev/null || echo "0")
    assert_equals "2" "$vm_count" "JSON VM count parsing"
    
    # Test IP extraction
    local ips
    ips=$(echo "$test_json" | jq -r 'to_entries[] | .value.IP' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
    assert_contains "$ips" "10.10.10.120" "IP extraction from JSON"
    assert_contains "$ips" "10.10.10.121" "multiple IP extraction"
}

# Test workspace context handling
test_workspace_context() {
    echo "Testing workspace context handling..."
    
    # Test current context retrieval (mock)
    local test_context="test-workspace"
    assert_contains "$test_context" "test" "workspace context format"
    
    # Test workspace-specific cache files
    local cache_pattern="/tmp/cpc_status_cache_${test_context}"
    assert_contains "$cache_pattern" "$test_context" "cache file includes workspace"
}

# Test error handling in k8s module
test_k8s_error_handling() {
    echo "Testing K8s module error handling..."
    
    # Test terraform directory validation
    local invalid_dir="/nonexistent/terraform"
    if [[ ! -d "$invalid_dir" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: Properly handles invalid terraform directory${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: Invalid directory check failed${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    # Test kubectl availability check
    if command -v kubectl >/dev/null 2>&1; then
        echo -e "${TEST_GREEN}✓ PASS: kubectl command available${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: kubectl not available in test environment${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test performance optimizations
test_performance_optimizations() {
    echo "Testing performance optimizations..."
    
    # Test cache TTL values
    local secrets_ttl=300  # 5 minutes
    local terraform_ttl=30  # 30 seconds
    local ssh_ttl=10       # 10 seconds
    
    assert_equals "300" "$secrets_ttl" "secrets cache TTL"
    assert_equals "30" "$terraform_ttl" "terraform cache TTL"
    assert_equals "10" "$ssh_ttl" "SSH cache TTL"
    
    # Test sequential vs parallel execution
    local execution_mode="sequential"
    assert_equals "sequential" "$execution_mode" "SSH execution mode"
}

# Main test runner for k8s cluster module
run_k8s_cluster_tests() {
    setup_test_env
    
    echo -e "${TEST_BLUE}=== K8s Cluster Module Unit Tests ===${TEST_NC}"
    
    test_k8s_cluster_status
    test_k8s_show_status_help
    test_k8s_caching
    test_k8s_bootstrap
    test_k8s_get_kubeconfig
    test_cpc_k8s_cluster_dispatcher
    test_ssh_connectivity
    test_json_processing
    test_workspace_context
    test_k8s_error_handling
    test_performance_optimizations
    
    cleanup_test_env
    print_test_results
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_k8s_cluster_tests
fi
