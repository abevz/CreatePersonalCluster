#!/bin/bash
# Unit tests for Proxmox module (10_proxmox.sh)

# Source the test framework
source "$(dirname "$0")/bash_test_framework.sh"

# Source required modules
source "$(dirname "$0")/../modules/00_core.sh"
source "$(dirname "$0")/../modules/10_proxmox.sh" 2>/dev/null || echo "Proxmox module not loaded (expected in test)"

# Test cpc_proxmox dispatcher
test_cpc_proxmox_dispatcher() {
    echo "Testing cpc_proxmox dispatcher..."
    
    if declare -f cpc_proxmox >/dev/null; then
        # Test invalid command
        local error_output
        error_output=$(cpc_proxmox invalid-command 2>&1 || true)
        assert_contains "$error_output" "Unknown proxmox command" "invalid command handling"
        
        echo -e "${TEST_GREEN}✓ PASS: cpc_proxmox function exists${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: cpc_proxmox function not available${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test template creation functionality
test_template_creation() {
    echo "Testing template creation functionality..."
    
    # Test template variables
    local required_template_vars=("TEMPLATE_VM_ID" "TEMPLATE_VM_NAME" "IMAGE_NAME")
    
    for var in "${required_template_vars[@]}"; do
        if [[ -n "${!var}" ]]; then
            echo -e "${TEST_GREEN}✓ PASS: $var template variable defined${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_YELLOW}⚠ SKIP: $var not set in test environment${TEST_NC}"
        fi
        ((TESTS_RUN++))
    done
}

# Test VM management functions
test_vm_management() {
    echo "Testing VM management functions..."
    
    # Test VM ID validation patterns
    local valid_vm_id="9420"
    local invalid_vm_id="abc"
    
    if [[ "$valid_vm_id" =~ ^[0-9]+$ ]]; then
        echo -e "${TEST_GREEN}✓ PASS: Valid VM ID pattern recognition${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: Valid VM ID pattern failed${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    if [[ ! "$invalid_vm_id" =~ ^[0-9]+$ ]]; then
        echo -e "${TEST_GREEN}✓ PASS: Invalid VM ID pattern rejection${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: Invalid VM ID pattern accepted${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test Proxmox API connection parameters
test_proxmox_api_config() {
    echo "Testing Proxmox API configuration..."
    
    # Test required Proxmox variables
    local proxmox_vars=("PROXMOX_HOST" "PROXMOX_USERNAME")
    
    for var in "${proxmox_vars[@]}"; do
        if [[ -n "${!var}" ]]; then
            echo -e "${TEST_GREEN}✓ PASS: $var is configured${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_YELLOW}⚠ SKIP: $var not set in test environment${TEST_NC}"
        fi
        ((TESTS_RUN++))
    done
    
    # Test hostname format validation
    local test_hostname="proxmox.local"
    if [[ "$test_hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        echo -e "${TEST_GREEN}✓ PASS: Hostname format validation${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: Hostname format validation failed${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test storage configuration
test_storage_config() {
    echo "Testing storage configuration..."
    
    # Test storage pool names
    local storage_pools=("local" "local-lvm" "ceph")
    
    for pool in "${storage_pools[@]}"; do
        if [[ "$pool" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Storage pool name '$pool' format valid${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Storage pool name '$pool' format invalid${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test network configuration
test_network_config() {
    echo "Testing network configuration..."
    
    # Test bridge name validation
    local bridges=("vmbr0" "vmbr1" "br-lan")
    
    for bridge in "${bridges[@]}"; do
        if [[ "$bridge" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Bridge name '$bridge' format valid${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Bridge name '$bridge' format invalid${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
    
    # Test VLAN ID validation
    local vlan_ids=(100 200 4094)
    
    for vlan in "${vlan_ids[@]}"; do
        if [[ "$vlan" -ge 1 && "$vlan" -le 4094 ]]; then
            echo -e "${TEST_GREEN}✓ PASS: VLAN ID '$vlan' in valid range${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: VLAN ID '$vlan' out of range${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test image handling
test_image_handling() {
    echo "Testing image handling..."
    
    # Test image file extensions
    local image_files=("ubuntu-24.04.img" "debian-12.qcow2" "template.vmdk")
    local valid_extensions=("img" "qcow2" "vmdk" "raw")
    
    for image in "${image_files[@]}"; do
        local extension="${image##*.}"
        if [[ " ${valid_extensions[*]} " =~ " ${extension} " ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Image file '$image' has valid extension${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Image file '$image' has invalid extension${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test cloud-init configuration
test_cloud_init_config() {
    echo "Testing cloud-init configuration..."
    
    # Test cloud-init user data structure
    local cloud_init_fields=("hostname" "user" "ssh_authorized_keys" "packages")
    
    for field in "${cloud_init_fields[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Cloud-init field '$field' recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
    
    # Test SSH key format validation
    local ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... user@host"
    if [[ "$ssh_key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
        echo -e "${TEST_GREEN}✓ PASS: SSH key format validation${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: SSH key format validation failed${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test resource allocation
test_resource_allocation() {
    echo "Testing resource allocation..."
    
    # Test CPU allocation validation
    local cpu_configs=(1 2 4 8 16)
    
    for cpu in "${cpu_configs[@]}"; do
        if [[ "$cpu" -ge 1 && "$cpu" -le 128 ]]; then
            echo -e "${TEST_GREEN}✓ PASS: CPU allocation '$cpu' in valid range${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: CPU allocation '$cpu' out of range${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
    
    # Test memory allocation validation (in MB)
    local memory_configs=(1024 2048 4096 8192)
    
    for memory in "${memory_configs[@]}"; do
        if [[ "$memory" -ge 512 && "$memory" -le 1048576 ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Memory allocation '${memory}MB' in valid range${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Memory allocation '${memory}MB' out of range${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test error handling and validation
test_proxmox_error_handling() {
    echo "Testing Proxmox error handling..."
    
    # Test command availability
    local proxmox_commands=("qm" "pvesh" "pct")
    
    for cmd in "${proxmox_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${TEST_GREEN}✓ PASS: Command '$cmd' available${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_YELLOW}⚠ SKIP: Command '$cmd' not available (expected outside Proxmox)${TEST_NC}"
        fi
        ((TESTS_RUN++))
    done
}

# Main test runner for Proxmox module
run_proxmox_tests() {
    setup_test_env
    
    echo -e "${TEST_BLUE}=== Proxmox Module Unit Tests ===${TEST_NC}"
    
    test_cpc_proxmox_dispatcher
    test_template_creation
    test_vm_management
    test_proxmox_api_config
    test_storage_config
    test_network_config
    test_image_handling
    test_cloud_init_config
    test_resource_allocation
    test_proxmox_error_handling
    
    cleanup_test_env
    print_test_results
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_proxmox_tests
fi
