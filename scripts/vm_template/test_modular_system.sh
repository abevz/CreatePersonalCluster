#!/bin/bash

# Test script for VM Template Creation Dispatcher
# This script tests the OS detection logic without actually creating VMs

echo "=== VM Template Dispatcher Test Suite ==="
echo ""

# Test cases for OS detection
test_cases=(
    "ubuntu-22.04-server-cloudimg-amd64.img:ubuntu"
    "Ubuntu-20.04-server-cloudimg-amd64.img:ubuntu"
    "debian-12-genericcloud-amd64.qcow2:debian"
    "debian-11-genericcloud-amd64.qcow2:debian"
    "Rocky-9-GenericCloud-Base.latest.x86_64.qcow2:rocky"
    "rocky-8-genericcloud-x86_64.qcow2:rocky"
    "openSUSE-Leap-15.5-JeOS.x86_64.qcow2:suse"
    "SUSE-15-SP4-JeOS.x86_64.qcow2:suse"
    "unknown-os-image.qcow2:unknown"
)

echo "Testing OS detection logic..."
echo ""

for test_case in "${test_cases[@]}"; do
    IFS=':' read -r image_name expected_os <<< "$test_case"
    
    # Simulate the OS detection logic from dispatcher
    detected_os=""
    if [[ "$image_name" == *"ubuntu"* || "$image_name" == *"Ubuntu"* ]]; then
        detected_os="ubuntu"
    elif [[ "$image_name" == *"debian"* || "$image_name" == *"Debian"* ]]; then
        detected_os="debian"
    elif [[ "$image_name" == *"Rocky"* || "$image_name" == *"rocky"* ]]; then
        detected_os="rocky"
    elif [[ "$image_name" == *"suse"* || "$image_name" == *"SUSE"* || "$image_name" == *"openSUSE"* ]]; then
        detected_os="suse"
    else
        detected_os="unknown"
    fi
    
    # Check result
    if [[ "$detected_os" == "$expected_os" ]]; then
        echo "✅ PASS: $image_name → $detected_os"
    else
        echo "❌ FAIL: $image_name → Expected: $expected_os, Got: $detected_os"
    fi
done

echo ""
echo "Testing script existence..."
echo ""

# Test if OS-specific scripts exist
os_types=("ubuntu" "debian" "rocky" "suse")
for os in "${os_types[@]}"; do
    script_path="${os}/create_${os}_template.sh"
    if [[ -f "$script_path" && -x "$script_path" ]]; then
        echo "✅ PASS: $script_path exists and is executable"
    else
        echo "❌ FAIL: $script_path missing or not executable"
    fi
done

echo ""
echo "Testing shared functions..."
echo ""

# Test shared functions
if [[ -f "shared/common_functions.sh" ]]; then
    echo "✅ PASS: shared/common_functions.sh exists"
    
    # Test if we can source it
    if source shared/common_functions.sh 2>/dev/null; then
        echo "✅ PASS: shared/common_functions.sh can be sourced"
        
        # Test if key functions exist
        functions_to_test=("install_required_tools" "load_environment" "validate_environment" "download_image")
        for func in "${functions_to_test[@]}"; do
            if declare -f "$func" >/dev/null; then
                echo "✅ PASS: Function $func is defined"
            else
                echo "❌ FAIL: Function $func not found"
            fi
        done
    else
        echo "❌ FAIL: Cannot source shared/common_functions.sh"
    fi
else
    echo "❌ FAIL: shared/common_functions.sh not found"
fi

echo ""
echo "Testing cloud-init files..."
echo ""

# Test cloud-init files
for os in "${os_types[@]}"; do
    cloud_init_file="${os}/${os}-cloud-init-userdata.yaml"
    if [[ -f "$cloud_init_file" ]]; then
        echo "✅ PASS: $cloud_init_file exists"
    else
        echo "❌ FAIL: $cloud_init_file not found"
    fi
done

echo ""
echo "=== Test Summary ==="
echo "If all tests passed, the modular VM template system is ready for use!"
echo "If any tests failed, please check the file structure and permissions."
echo ""
echo "Next steps:"
echo "1. Set required environment variables (cpc.env + SOPS secrets)"
echo "2. Test with actual VM creation: ./create_template_dispatcher.sh"
echo "3. Or use via main script: ../template.sh"
