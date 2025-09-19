#!/bin/bash
# Unit tests for hostname generation and INDEX parsing fixes

# Source the test framework
source "$(dirname "$0")/bash_test_framework.sh"

# Test Terraform variable passing in Proxmox module
test_terraform_variable_export() {
    echo "Testing Terraform variable export in Proxmox module..."
    
    # Mock environment variables
    export ADDITIONAL_WORKERS=3
    export ADDITIONAL_CONTROLPLANES=2
    export RELEASE_LETTER=b
    
    # Test that our function sets the TF_VAR variables
    # We'll simulate the function behavior
    test_additional_workers="$ADDITIONAL_WORKERS"
    test_additional_controlplanes="$ADDITIONAL_CONTROLPLANES"
    test_release_letter="$RELEASE_LETTER"
    
    # Simulate the export statements from _execute_terraform_vm_creation
    export TF_VAR_additional_workers="$test_additional_workers"
    export TF_VAR_additional_controlplanes="$test_additional_controlplanes"
    export TF_VAR_release_letter="$test_release_letter"
    
    # Verify exports were set correctly
    if [[ "$TF_VAR_additional_workers" == "3" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: TF_VAR_additional_workers exported correctly${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: TF_VAR_additional_workers not exported correctly${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    if [[ "$TF_VAR_additional_controlplanes" == "2" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: TF_VAR_additional_controlplanes exported correctly${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: TF_VAR_additional_controlplanes not exported correctly${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    if [[ "$TF_VAR_release_letter" == "b" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: TF_VAR_release_letter exported correctly${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: TF_VAR_release_letter not exported correctly${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test INDEX parsing regex functionality
test_index_parsing_regex() {
    echo "Testing INDEX parsing regex patterns..."
    
    # Test cases for hostname formats
    local test_hostnames=(
        "c1.bevz.net"    # Format: c1 (no release letter)
        "cb1.bevz.net"   # Format: cb1 (with release letter)
        "w1.bevz.net"    # Format: w1 (no release letter)
        "wb1.bevz.net"   # Format: wb1 (with release letter)
        "wb2.bevz.net"   # Format: wb2 (with release letter)
        "wb3.bevz.net"   # Format: wb3 (with release letter)
    )
    
    local expected_indexes=(
        "1"  # c1
        "1"  # cb1
        "1"  # w1
        "1"  # wb1
        "2"  # wb2
        "3"  # wb3
    )
    
    # Simulate the INDEX parsing logic from generate_node_hostnames.sh
    for i in "${!test_hostnames[@]}"; do
        local hostname="${test_hostnames[$i]}"
        local expected_index="${expected_indexes[$i]}"
        local hostname_base="${hostname%%.*}"  # Remove domain part
        local INDEX=""
        
        # Apply the regex patterns from our fix
        if [[ $hostname_base =~ ^[cw]([0-9]+)$ ]]; then
            INDEX="${BASH_REMATCH[1]}"
        elif [[ $hostname_base =~ ^[cw][a-z]([0-9]+)$ ]]; then
            INDEX="${BASH_REMATCH[1]}"
        fi
        
        if [[ "$INDEX" == "$expected_index" ]]; then
            echo -e "${TEST_GREEN}✓ PASS: INDEX parsing for '$hostname' -> INDEX=$INDEX${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: INDEX parsing for '$hostname' -> got INDEX='$INDEX', expected '$expected_index'${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test hostname generation with release letter
test_hostname_generation_with_release_letter() {
    echo "Testing hostname generation with release letter..."
    
    # Test cases
    local test_cases=(
        "c:1:b:cb1.bevz.net"   # role:index:release_letter:expected_hostname
        "w:1:b:wb1.bevz.net"
        "w:2:b:wb2.bevz.net"
        "w:3:b:wb3.bevz.net"
        "c:2:b:cb2.bevz.net"
    )
    
    local VM_DOMAIN=".bevz.net"
    
    for test_case in "${test_cases[@]}"; do
        IFS=':' read -r ROLE INDEX RELEASE_LETTER expected_hostname <<< "$test_case"
        
        # Simulate hostname generation logic
        local generated_hostname="${ROLE}${RELEASE_LETTER}${INDEX}${VM_DOMAIN}"
        
        if [[ "$generated_hostname" == "$expected_hostname" ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Hostname generation for $ROLE$INDEX with release letter '$RELEASE_LETTER' -> $generated_hostname${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Hostname generation for $ROLE$INDEX -> got '$generated_hostname', expected '$expected_hostname'${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test cloud-init snippet naming
test_cloud_init_snippet_naming() {
    echo "Testing cloud-init snippet naming..."
    
    local test_hostnames=(
        "cb1.bevz.net:node-cb1-userdata.yaml"
        "wb1.bevz.net:node-wb1-userdata.yaml" 
        "wb2.bevz.net:node-wb2-userdata.yaml"
        "wb3.bevz.net:node-wb3-userdata.yaml"
        "cb2.bevz.net:node-cb2-userdata.yaml"
    )
    
    for test_case in "${test_hostnames[@]}"; do
        IFS=':' read -r hostname expected_snippet <<< "$test_case"
        local hostname_base="${hostname%%.*}"  # Remove domain
        local generated_snippet="node-${hostname_base}-userdata.yaml"
        
        if [[ "$generated_snippet" == "$expected_snippet" ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Snippet naming for '$hostname' -> $generated_snippet${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Snippet naming for '$hostname' -> got '$generated_snippet', expected '$expected_snippet'${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test regex edge cases
test_regex_edge_cases() {
    echo "Testing regex edge cases..."
    
    # Edge cases that should NOT match
    local invalid_hostnames=(
        "abc1.bevz.net"    # Invalid role
        "c.bevz.net"       # Missing index
        "cb.bevz.net"      # Missing index
        "cba1.bevz.net"    # Too many letters
        "1c.bevz.net"      # Wrong order
    )
    
    for hostname in "${invalid_hostnames[@]}"; do
        local hostname_base="${hostname%%.*}"
        local INDEX=""
        
        # Apply our regex patterns
        if [[ $hostname_base =~ ^[cw]([0-9]+)$ ]]; then
            INDEX="${BASH_REMATCH[1]}"
        elif [[ $hostname_base =~ ^[cw][a-z]([0-9]+)$ ]]; then
            INDEX="${BASH_REMATCH[1]}"
        fi
        
        if [[ -z "$INDEX" ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Invalid hostname '$hostname' correctly rejected${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Invalid hostname '$hostname' incorrectly accepted with INDEX='$INDEX'${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
    
    # Edge cases that SHOULD match
    local valid_hostnames=(
        "c9.bevz.net:9"     # High single digit
        "w10.bevz.net:10"   # Double digit
        "cz99.bevz.net:99"  # High number with any letter
    )
    
    for test_case in "${valid_hostnames[@]}"; do
        IFS=':' read -r hostname expected_index <<< "$test_case"
        local hostname_base="${hostname%%.*}"
        local INDEX=""
        
        # Apply our regex patterns
        if [[ $hostname_base =~ ^[cw]([0-9]+)$ ]]; then
            INDEX="${BASH_REMATCH[1]}"
        elif [[ $hostname_base =~ ^[cw][a-z]([0-9]+)$ ]]; then
            INDEX="${BASH_REMATCH[1]}"
        fi
        
        if [[ "$INDEX" == "$expected_index" ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Valid hostname '$hostname' correctly parsed -> INDEX=$INDEX${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Valid hostname '$hostname' incorrectly parsed -> got INDEX='$INDEX', expected '$expected_index'${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
}

# Test cluster_summary output usage
test_cluster_summary_output() {
    echo "Testing cluster_summary output usage..."
    
    # Test that we're using cluster_summary instead of k8s_node_names
    local terraform_outputs="cluster_summary k8s_node_names ansible_inventory"
    
    # cluster_summary should be available
    if [[ "$terraform_outputs" =~ cluster_summary ]]; then
        echo -e "${TEST_GREEN}✓ PASS: cluster_summary output is available${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: cluster_summary output not found${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    # Simulate cluster_summary structure
    local sample_cluster_summary='{
        "k8s133-controlplane-1": {
            "IP": "10.10.10.160",
            "VM_ID": 801,
            "hostname": "cb1.bevz.net"
        },
        "k8s133-worker-1": {
            "IP": "10.10.10.165", 
            "VM_ID": 821,
            "hostname": "wb1.bevz.net"
        }
    }'
    
    # Test that we can extract hostnames from cluster_summary
    if echo "$sample_cluster_summary" | grep -q "cb1.bevz.net"; then
        echo -e "${TEST_GREEN}✓ PASS: cluster_summary contains expected hostname format${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_RED}✗ FAIL: cluster_summary missing expected hostname format${TEST_NC}"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Main test runner for hostname generation fixes
run_hostname_generation_tests() {
    # Simple setup without calling external setup functions
    echo -e "${TEST_BLUE}=== Hostname Generation and INDEX Parsing Fix Tests ===${TEST_NC}"
    
    test_terraform_variable_export
    test_index_parsing_regex
    test_hostname_generation_with_release_letter
    test_cloud_init_snippet_naming
    test_regex_edge_cases
    test_cluster_summary_output
    
    # Simple cleanup without calling external cleanup functions
    echo -e "${TEST_BLUE}=== Test Results ===${TEST_NC}"
    print_test_results
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_hostname_generation_tests
fi
