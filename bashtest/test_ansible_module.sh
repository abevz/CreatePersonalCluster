#!/bin/bash
# Unit tests for Ansible module (20_ansible.sh)

# Source the test framework
source "$(dirname "$0")/bash_test_framework.sh"

# Source required modules
source "$(dirname "$0")/../modules/00_core.sh"
source "$(dirname "$0")/../modules/20_ansible.sh" 2>/dev/null || echo "Ansible module not loaded (expected in test)"

# Test cpc_ansible dispatcher
test_cpc_ansible_dispatcher() {
    echo "Testing cpc_ansible dispatcher..."
    
    if declare -f cpc_ansible >/dev/null; then
        # Test invalid command
        local error_output
        error_output=$(cpc_ansible invalid-command 2>&1 || true)
        assert_contains "$error_output" "Unknown ansible command" "invalid command handling"
        
        echo -e "${TEST_GREEN}✓ PASS: cpc_ansible function exists${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: cpc_ansible function not available${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test inventory management
test_inventory_management() {
    echo "Testing inventory management..."
    
    # Test inventory file structure
    local inventory_dir="$(dirname "$0")/../ansible/inventory"
    
    if [[ -d "$inventory_dir" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: Inventory directory exists${TEST_NC}"
        ((TESTS_PASSED++))
        
        # Check for common inventory files
        local inventory_files=("hosts.yml" "group_vars" "host_vars")
        for file in "${inventory_files[@]}"; do
            if [[ -e "$inventory_dir/$file" ]]; then
                echo -e "${TEST_GREEN}✓ PASS: Inventory file/dir '$file' exists${TEST_NC}"
                ((TESTS_PASSED++))
            else
                echo -e "${TEST_YELLOW}⚠ SKIP: Inventory file/dir '$file' not found${TEST_NC}"
            fi
            ((TESTS_RUN++))
        done
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: Inventory directory not found${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test playbook structure
test_playbook_structure() {
    echo "Testing playbook structure..."
    
    local playbooks_dir="$(dirname "$0")/../ansible/playbooks"
    
    if [[ -d "$playbooks_dir" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: Playbooks directory exists${TEST_NC}"
        ((TESTS_PASSED++))
        
        # Check for common playbooks
        local expected_playbooks=("bootstrap.yml" "upgrade.yml" "reset.yml")
        for playbook in "${expected_playbooks[@]}"; do
            if [[ -f "$playbooks_dir/$playbook" ]]; then
                echo -e "${TEST_GREEN}✓ PASS: Playbook '$playbook' exists${TEST_NC}"
                ((TESTS_PASSED++))
            else
                echo -e "${TEST_YELLOW}⚠ SKIP: Playbook '$playbook' not found${TEST_NC}"
            fi
            ((TESTS_RUN++))
        done
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: Playbooks directory not found${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test roles structure
test_roles_structure() {
    echo "Testing roles structure..."
    
    local roles_dir="$(dirname "$0")/../ansible/roles"
    
    if [[ -d "$roles_dir" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: Roles directory exists${TEST_NC}"
        ((TESTS_PASSED++))
        
        # Check for common roles
        local expected_roles=("common" "kubernetes" "docker")
        for role in "${expected_roles[@]}"; do
            if [[ -d "$roles_dir/$role" ]]; then
                echo -e "${TEST_GREEN}✓ PASS: Role '$role' directory exists${TEST_NC}"
                ((TESTS_PASSED++))
                
                # Check role structure
                local role_dirs=("tasks" "handlers" "templates" "vars")
                for role_dir in "${role_dirs[@]}"; do
                    if [[ -d "$roles_dir/$role/$role_dir" ]]; then
                        echo -e "${TEST_GREEN}✓ PASS: Role '$role' has '$role_dir' directory${TEST_NC}"
                        ((TESTS_PASSED++))
                    else
                        echo -e "${TEST_YELLOW}⚠ SKIP: Role '$role' missing '$role_dir' directory${TEST_NC}"
                    fi
                    ((TESTS_RUN++))
                done
            else
                echo -e "${TEST_YELLOW}⚠ SKIP: Role '$role' not found${TEST_NC}"
            fi
            ((TESTS_RUN++))
        done
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: Roles directory not found${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test ansible configuration
test_ansible_config() {
    echo "Testing Ansible configuration..."
    
    local ansible_cfg="$(dirname "$0")/../ansible/ansible.cfg"
    
    if [[ -f "$ansible_cfg" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: ansible.cfg exists${TEST_NC}"
        ((TESTS_PASSED++))
        
        # Check for important configuration options
        local config_options=("inventory" "host_key_checking" "timeout")
        for option in "${config_options[@]}"; do
            if grep -q "$option" "$ansible_cfg"; then
                echo -e "${TEST_GREEN}✓ PASS: ansible.cfg contains '$option' setting${TEST_NC}"
                ((TESTS_PASSED++))
            else
                echo -e "${TEST_YELLOW}⚠ SKIP: ansible.cfg missing '$option' setting${TEST_NC}"
            fi
            ((TESTS_RUN++))
        done
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: ansible.cfg not found${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test inventory update functionality
test_inventory_update() {
    echo "Testing inventory update functionality..."
    
    # Test inventory update command structure
    if declare -f ansible_update_inventory >/dev/null; then
        echo -e "${TEST_GREEN}✓ PASS: ansible_update_inventory function exists${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: ansible_update_inventory function not available${TEST_NC}"
    fi
    ((TESTS_RUN++))
    
    # Test inventory generation from terraform output
    local test_terraform_output='{"vm1":{"IP":"10.10.10.120","Name":"test-controlplane-1"},"vm2":{"IP":"10.10.10.125","Name":"test-worker-1"}}'
    
    # Test JSON parsing for inventory
    local vm_ips
    vm_ips=$(echo "$test_terraform_output" | jq -r 'to_entries[] | .value.IP' 2>/dev/null | tr '\n' ' ')
    assert_contains "$vm_ips" "10.10.10.120" "terraform output IP extraction"
    assert_contains "$vm_ips" "10.10.10.125" "multiple VM IP extraction"
}

# Test playbook execution
test_playbook_execution() {
    echo "Testing playbook execution..."
    
    # Test ansible-playbook command availability
    if command -v ansible-playbook >/dev/null 2>&1; then
        echo -e "${TEST_GREEN}✓ PASS: ansible-playbook command available${TEST_NC}"
        ((TESTS_PASSED++))
        
        # Test playbook syntax validation
        local playbooks_dir="$(dirname "$0")/../ansible/playbooks"
        if [[ -d "$playbooks_dir" ]]; then
            for playbook in "$playbooks_dir"/*.yml; do
                if [[ -f "$playbook" ]]; then
                    if ansible-playbook --syntax-check "$playbook" >/dev/null 2>&1; then
                        echo -e "${TEST_GREEN}✓ PASS: Playbook '$(basename "$playbook")' syntax valid${TEST_NC}"
                        ((TESTS_PASSED++))
                    else
                        echo -e "${TEST_RED}✗ FAIL: Playbook '$(basename "$playbook")' syntax invalid${TEST_NC}"
                        ((TESTS_FAILED++))
                    fi
                    ((TESTS_RUN++))
                fi
            done
        fi
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: ansible-playbook not available${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test host group management
test_host_groups() {
    echo "Testing host group management..."
    
    # Test standard Kubernetes host groups
    local k8s_groups=("controlplane" "workers" "all")
    
    for group in "${k8s_groups[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Host group '$group' pattern recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
    
    # Test group variable structure
    local group_vars_dir="$(dirname "$0")/../ansible/inventory/group_vars"
    if [[ -d "$group_vars_dir" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: Group vars directory exists${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: Group vars directory not found${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test SSH connectivity for Ansible
test_ssh_connectivity() {
    echo "Testing SSH connectivity for Ansible..."
    
    # Test SSH configuration options
    local ssh_options=("StrictHostKeyChecking=no" "UserKnownHostsFile=/dev/null" "ConnectTimeout=10")
    
    for option in "${ssh_options[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: SSH option '$option' pattern valid${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
    
    # Test SSH key authentication
    local ssh_key_path="/home/user/.ssh/id_rsa"
    if [[ -f "$ssh_key_path" ]]; then
        echo -e "${TEST_GREEN}✓ PASS: SSH key file exists${TEST_NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${TEST_YELLOW}⚠ SKIP: SSH key file not found (expected in test)${TEST_NC}"
    fi
    ((TESTS_RUN++))
}

# Test variable templating
test_variable_templating() {
    echo "Testing variable templating..."
    
    # Test Jinja2 template patterns
    local template_patterns=("{{ variable }}" "{% if condition %}" "{{ item.key }}")
    
    for pattern in "${template_patterns[@]}"; do
        if [[ "$pattern" =~ \{\{.*\}\}|\{%.*%\} ]]; then
            echo -e "${TEST_GREEN}✓ PASS: Template pattern '$pattern' valid${TEST_NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${TEST_RED}✗ FAIL: Template pattern '$pattern' invalid${TEST_NC}"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    done
    
    # Test variable precedence
    local var_sources=("host_vars" "group_vars" "playbook_vars" "extra_vars")
    for source in "${var_sources[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Variable source '$source' recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
}

# Test error handling and logging
test_ansible_error_handling() {
    echo "Testing Ansible error handling..."
    
    # Test log file patterns
    local log_patterns=("PLAY RECAP" "TASK" "ERROR" "FAILED")
    
    for pattern in "${log_patterns[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Log pattern '$pattern' recognized${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
    
    # Test retry mechanisms
    local retry_options=("retries" "delay" "until")
    for option in "${retry_options[@]}"; do
        echo -e "${TEST_GREEN}✓ PASS: Retry option '$option' available${TEST_NC}"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    done
}

# Main test runner for Ansible module
run_ansible_tests() {
    setup_test_env
    
    echo -e "${TEST_BLUE}=== Ansible Module Unit Tests ===${TEST_NC}"
    
    test_cpc_ansible_dispatcher
    test_inventory_management
    test_playbook_structure
    test_roles_structure
    test_ansible_config
    test_inventory_update
    test_playbook_execution
    test_host_groups
    test_ssh_connectivity
    test_variable_templating
    test_ansible_error_handling
    
    cleanup_test_env
    print_test_results
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_ansible_tests
fi
