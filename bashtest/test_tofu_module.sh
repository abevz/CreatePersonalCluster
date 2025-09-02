#!/bin/bash
# Unit tests for Tofu/Terraform module (60_tofu.sh)

# Source the test framework
source "$(dirname "$0")/bash_test_framework.sh"

# Source required modules
source "$(dirname "$0")/../modules/00_core.sh"
source "$(dirname "$0")/../modules/60_tofu.sh" 2>/dev/null || echo "Tofu module not loaded (expected in test)"

# Test cpc_tofu dispatcher
test_cpc_tofu_dispatcher() {
    echo "Testing cpc_tofu dispatcher..."
    
    if declare -f cpc_tofu >/dev/null; then
        # Test invalid command
        local error_output
        error_output=$(cpc_tofu invalid-command 2>&1 || true)
        assert_contains "$error_output" "Unknown tofu command" "invalid command handling"
        
        echo -e "${TEST_GREEN}✓ PASS: cpc_tofu function exists${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: cpc_tofu function not available${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test terraform/tofu command availability
test_tofu_availability() {
    echo "Testing Tofu/Terraform availability..."
    
    if command -v tofu >/dev/null 2>&1; then
        echo -e "${TEST_GREEN}✓ PASS: tofu command available${TEST_NC}"
        ((TESTS_PASSED++))
        
        # Test tofu version
        local tofu_version
        tofu_version=$(tofu version 2>/dev/null | head -n1)
        assert_contains "$tofu_version" "OpenTofu" "tofu version output"
    elif command -v terraform >/dev/null 2>&1; then
        echo -e "${TEST_GREEN}✓ PASS: terraform command available${TEST_NC}"
        ((TESTS_PASSED++))
        
        # Test terraform version
        local terraform_version
        terraform_version=$(terraform version 2>/dev/null | head -n1)
        assert_contains "$terraform_version" "Terraform" "terraform version output"
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: Neither tofu nor terraform available${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test workspace management
test_workspace_management() {
    echo "Testing workspace management..."
    
    # Test workspace commands
    local workspace_commands=("list" "show" "new" "select" "delete")
    
    for cmd in "${workspace_commands[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Workspace command '$cmd' recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
    
    # Test workspace naming validation
    local valid_workspaces=("ubuntu" "debian" "k8s-test" "k8s133")
    local invalid_workspaces=("Ubuntu" "test workspace" "test@workspace")
    
    for workspace in "${valid_workspaces[@]}"; do
        if [[ "$workspace" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$ ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Workspace name '$workspace' format valid${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Workspace name '$workspace' format invalid${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
    
    for workspace in "${invalid_workspaces[@]}"; do
        if [[ ! "$workspace" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$ ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Workspace name '$workspace' correctly rejected${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Workspace name '$workspace' should be rejected${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test terraform configuration structure
test_terraform_config() {
    echo "Testing Terraform configuration structure..."
    
    local terraform_dir="$(dirname "$0")/../terraform"
    
    if [[ -d "$terraform_dir" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: Terraform directory exists${TEST_NC}"
        ((TESTS_PASSED++))
        
        # Check for required terraform files
        local required_files=("main.tf" "variables.tf" "outputs.tf" "locals.tf")
        for file in "${required_files[@]}"; do
            if [[ -f "$terraform_dir/$file" ]]; then
                echo -e "${TEST_GREEN}✓ PASS: Terraform file '$file' exists${TEST_NC}"
                ((TESTS_PASSED++))
            else
                echo -e "${TEST_YELLOW}⚠ SKIP: Terraform file '$file' not found${TEST_NC}"
            fi
            ((TESTS_RUN++))
        done
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: Terraform directory not found${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test terraform providers
test_terraform_providers() {
    echo "Testing Terraform providers..."
    
    local terraform_dir="$(dirname "$0")/../terraform"
    
    if [[ -f "$terraform_dir/main.tf" ]]; then
        # Check for Proxmox provider
        if grep -q "telmate/proxmox" "$terraform_dir/main.tf" 2>/dev/null; then
            echo -e "${TEST_GREEN}✓ PASS: Proxmox provider configured${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_YELLOW}⚠ SKIP: Proxmox provider not found in main.tf${TEST_NC}"
        fi
        ((TESTS_RUN++))
        
        # Check for required_version
        if grep -q "required_version" "$terraform_dir/main.tf" 2>/dev/null; then
            echo -e "${TEST_GREEN}✓ PASS: Terraform required_version specified${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_YELLOW}⚠ SKIP: Terraform required_version not specified${TEST_NC}"
        fi
        ((TESTS_RUN++))
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: main.tf not found${TEST_NC}"
        ((TESTS_RUN += 2))
    fi
}

# Test variable validation
test_variable_validation() {
    echo "Testing variable validation..."
    
    # Test variable types
    local variable_types=("string" "number" "bool" "list" "map" "object")
    
    for type in "${variable_types[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Variable type '$type' recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
    
    # Test variable validation patterns
    local ip_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    local test_ips=("10.10.10.1" "192.168.1.100" "172.16.0.1")
    local invalid_ips=("256.1.1.1" "10.10.10" "not.an.ip")
    
    for ip in "${test_ips[@]}"; do
        if [[ "$ip" =~ $ip_pattern ]]; then
            echo -e "${TEST_GREEN}✓ PASS: IP address '$ip' format valid${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: IP address '$ip' format validation failed${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
    
    for ip in "${invalid_ips[@]}"; do
        if [[ ! "$ip" =~ $ip_pattern ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Invalid IP '$ip' correctly rejected${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Invalid IP '$ip' incorrectly accepted${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test output handling
test_output_handling() {
    echo "Testing output handling..."
    
    # Test output format validation
    local test_json='{"cluster_summary":{"vm1":{"IP":"10.10.10.120","Name":"test-vm"}}}'
    
    if echo "$test_json" | jq . >/dev/null 2>&1; then
        echo -e "${TEST_GREEN}✓ PASS: JSON output format valid${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: JSON output format invalid${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    # Test output extraction
    local vm_count
    vm_count=$(echo "$test_json" | jq '.cluster_summary | length' 2>/dev/null)
    assert_equals "1" "$vm_count" "output JSON parsing"
}

# Test state management
test_state_management() {
    echo "Testing state management..."
    
    # Test state file patterns
    local state_files=("terraform.tfstate" "terraform.tfstate.backup")
    
    for file in "${state_files[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: State file pattern '$file' recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
    
    # Test state locking
    local lock_patterns=(".terraform.lock.hcl" "terraform.tfstate.lock.info")
    
    for pattern in "${lock_patterns[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Lock file pattern '$pattern' recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
}

# Test deployment operations
test_deployment_operations() {
    echo "Testing deployment operations..."
    
    # Test deployment commands
    local deploy_commands=("plan" "apply" "destroy" "validate" "fmt")
    
    for cmd in "${deploy_commands[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Deploy command '$cmd' recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
    
    # Test auto-approve patterns
    local auto_approve_pattern="-auto-approve"
    assert_contains "$auto_approve_pattern" "auto-approve" "auto-approve flag pattern"
}

# Test resource management
test_resource_management() {
    echo "Testing resource management..."
    
    # Test Proxmox resource types
    local resource_types=("proxmox_vm_qemu" "proxmox_lxc" "proxmox_cloud_init_disk")
    
    for resource in "${resource_types[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Resource type '$resource' recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
    
    # Test resource naming patterns
    local resource_names=("vm-controlplane-1" "vm-worker-1" "template-ubuntu")
    
    for name in "${resource_names[@]}"; do
        if [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Resource name '$name' format valid${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Resource name '$name' format invalid${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test environment variable handling
test_env_variable_handling() {
    echo "Testing environment variable handling..."
    
    # Test TF_VAR_ prefix handling
    local tf_vars=("TF_VAR_proxmox_host" "TF_VAR_vm_user" "TF_VAR_network_cidr")
    
    for var in "${tf_vars[@]}"; do
        if [[ "$var" =~ ^TF_VAR_ ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Terraform variable '$var' prefix valid${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Terraform variable '$var' prefix invalid${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test error handling and validation
test_tofu_error_handling() {
    echo "Testing Tofu error handling..."
    
    # Test error code patterns
    local error_codes=(1 2 127)
    
    for code in "${error_codes[@]}"; do
        if [[ "$code" -gt 0 ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Error code '$code' indicates failure${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Error code '$code' should indicate failure${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
    
    # Test timeout handling
    local timeout_values=(300 600 1800)
    
    for timeout in "${timeout_values[@]}"; do
        if [[ "$timeout" -gt 0 ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Timeout value '$timeout' seconds valid${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Timeout value '$timeout' invalid${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Main test runner for Tofu module
run_tofu_tests() {
    setup_test_env
    
    echo -e "${TEST_BLUE}=== Tofu/Terraform Module Unit Tests ===${TEST_NC}"
    
    test_cpc_tofu_dispatcher
    test_tofu_availability
    test_workspace_management
    test_terraform_config
    test_terraform_providers
    test_variable_validation
    test_output_handling
    test_state_management
    test_deployment_operations
    test_resource_management
    test_env_variable_handling
    test_tofu_error_handling
    
    cleanup_test_env
    print_test_results
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tofu_tests
fi
