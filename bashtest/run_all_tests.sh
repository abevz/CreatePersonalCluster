#!/bin/bash
# Master Test Runner for CPC - Comprehensive Unit Test Suite
# Runs all unit tests for all modules and provides detailed reporting

# Source the test framework
source "$(dirname "$0")/bash_test_framework.sh"

# Test suite configuration
declare -A TEST_SUITES=(
    ["Core Module"]="$(dirname "$0")/test_core_module.sh"
    ["K8s Cluster Module"]="$(dirname "$0")/test_k8s_cluster_module.sh"
    ["Proxmox Module"]="$(dirname "$0")/test_proxmox_module.sh"
    ["Ansible Module"]="$(dirname "$0")/test_ansible_module.sh"
    ["Tofu Module"]="$(dirname "$0")/test_tofu_module.sh"
)

# Global test statistics
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
declare -a FAILED_SUITE_NAMES=()

# Colors for master output
readonly MASTER_CYAN='\033[0;36m'
readonly MASTER_MAGENTA='\033[0;35m'
readonly MASTER_BOLD='\033[1m'

# Print master test header
print_master_header() {
    echo
    echo -e "${MASTER_CYAN}╔════════════════════════════════════════════════════════════════╗${TEST_NC}"
    echo -e "${MASTER_CYAN}║                CPC Comprehensive Unit Test Suite              ║${TEST_NC}"
    echo -e "${MASTER_CYAN}║                     Full Functionality Coverage               ║${TEST_NC}"
    echo -e "${MASTER_CYAN}╚════════════════════════════════════════════════════════════════╝${TEST_NC}"
    echo
    echo -e "${TEST_BLUE}Running comprehensive tests for all CPC modules...${TEST_NC}"
    echo -e "${TEST_BLUE}Test suites: ${#TEST_SUITES[@]}${TEST_NC}"
    echo
}

# Run a single test suite
run_test_suite_with_reporting() {
    local suite_name="$1"
    local test_script="$2"
    
    echo -e "${MASTER_MAGENTA}${MASTER_BOLD}═══ Running: $suite_name ═══${TEST_NC}"
    echo
    
    ((TOTAL_SUITES++))
    
    # Make test script executable
    chmod +x "$test_script"
    
    # Run the test suite and capture its exit code
    if bash "$test_script"; then
        echo
        echo -e "${TEST_GREEN}✅ SUITE PASSED: $suite_name${TEST_NC}"
        ((PASSED_SUITES++))
    else
        echo
        echo -e "${TEST_RED}❌ SUITE FAILED: $suite_name${TEST_NC}"
        FAILED_SUITE_NAMES+=("$suite_name")
        ((FAILED_SUITES++))
    fi
    
    echo -e "${MASTER_MAGENTA}═══════════════════════════════════════════════════════════════${TEST_NC}"
    echo
}

# Print comprehensive test results
print_master_results() {
    echo
    echo -e "${MASTER_CYAN}╔════════════════════════════════════════════════════════════════╗${TEST_NC}"
    echo -e "${MASTER_CYAN}║                    COMPREHENSIVE TEST RESULTS                 ║${TEST_NC}"
    echo -e "${MASTER_CYAN}╚════════════════════════════════════════════════════════════════╝${TEST_NC}"
    echo
    
    echo -e "${TEST_BLUE}Test Suite Summary:${TEST_NC}"
    echo "  Total suites run: $TOTAL_SUITES"
    echo -e "  ${TEST_GREEN}Passed: $PASSED_SUITES${TEST_NC}"
    echo -e "  ${TEST_RED}Failed: $FAILED_SUITES${TEST_NC}"
    
    if [[ $FAILED_SUITES -gt 0 ]]; then
        echo
        echo -e "${TEST_RED}Failed test suites:${TEST_NC}"
        for suite in "${FAILED_SUITE_NAMES[@]}"; do
            echo -e "${TEST_RED}  ❌ $suite${TEST_NC}"
        done
        echo
        echo -e "${TEST_RED}Some test suites failed. Please check the output above for details.${TEST_NC}"
        return 1
    else
        echo
        echo -e "${TEST_GREEN}🎉 ALL TEST SUITES PASSED! 🎉${TEST_NC}"
        echo -e "${TEST_GREEN}CPC functionality is fully validated.${TEST_NC}"
        return 0
    fi
}

# Run specific test suite
run_specific_suite() {
    local target_suite="$1"
    
    for suite_name in "${!TEST_SUITES[@]}"; do
        if [[ "$suite_name" == *"$target_suite"* ]]; then
            echo -e "${TEST_BLUE}Running specific test suite: $suite_name${TEST_NC}"
            run_test_suite_with_reporting "$suite_name" "${TEST_SUITES[$suite_name]}"
            return $?
        fi
    done
    
    echo -e "${TEST_RED}Test suite '$target_suite' not found.${TEST_NC}"
    echo -e "${TEST_BLUE}Available suites:${TEST_NC}"
    for suite_name in "${!TEST_SUITES[@]}"; do
        echo "  - $suite_name"
    done
    return 1
}

# List all available test suites
list_test_suites() {
    echo -e "${TEST_BLUE}Available CPC Test Suites:${TEST_NC}"
    echo
    
    local i=1
    for suite_name in "${!TEST_SUITES[@]}"; do
        echo -e "${TEST_GREEN}$i.${TEST_NC} $suite_name"
        echo "   Script: ${TEST_SUITES[$suite_name]}"
        echo
        ((i++))
    done
}

# Run quick validation tests
run_quick_validation() {
    echo -e "${TEST_BLUE}Running quick validation tests...${TEST_NC}"
    echo
    
    # Check required commands
    local required_commands=("jq" "tofu" "ansible" "kubectl")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${TEST_GREEN}✓ $cmd available${TEST_NC}"
        else
            echo -e "${TEST_YELLOW}⚠ $cmd not available${TEST_NC}"
            missing_commands+=("$cmd")
        fi
    done
    
    echo
    
    # Check project structure
    local required_files=("cpc" "cpc.env.example" "modules/00_core.sh")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ -f "$(dirname "$0")/../$file" ]]; then
            echo -e "${TEST_GREEN}✓ $file exists${TEST_NC}"
        else
            echo -e "${TEST_RED}✗ $file missing${TEST_NC}"
            missing_files+=("$file")
        fi
    done
    
    echo
    
    if [[ ${#missing_commands[@]} -gt 0 || ${#missing_files[@]} -gt 0 ]]; then
        echo -e "${TEST_YELLOW}Quick validation found issues:${TEST_NC}"
        [[ ${#missing_commands[@]} -gt 0 ]] && echo -e "${TEST_YELLOW}  Missing commands: ${missing_commands[*]}${TEST_NC}"
        [[ ${#missing_files[@]} -gt 0 ]] && echo -e "${TEST_RED}  Missing files: ${missing_files[*]}${TEST_NC}"
        return 1
    else
        echo -e "${TEST_GREEN}Quick validation passed!${TEST_NC}"
        return 0
    fi
}

# Show usage information
show_usage() {
    echo "CPC Master Test Runner"
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  (no args)     Run all test suites"
    echo "  --suite NAME  Run specific test suite"
    echo "  --list        List all available test suites"
    echo "  --quick       Run quick validation only"
    echo "  --help        Show this help message"
    echo
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 --suite Core       # Run only Core module tests"
    echo "  $0 --quick            # Quick validation"
    echo
}

# Main execution logic
main() {
    case "${1:-}" in
        --suite)
            if [[ -z "$2" ]]; then
                echo -e "${TEST_RED}Error: --suite requires a suite name${TEST_NC}"
                show_usage
                exit 1
            fi
            setup_test_env
            run_specific_suite "$2"
            local exit_code=$?
            cleanup_test_env
            exit $exit_code
            ;;
        --list)
            list_test_suites
            exit 0
            ;;
        --quick)
            run_quick_validation
            exit $?
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        "")
            # Run all tests
            print_master_header
            setup_test_env
            
            # Run all test suites
            for suite_name in "${!TEST_SUITES[@]}"; do
                run_test_suite_with_reporting "$suite_name" "${TEST_SUITES[$suite_name]}"
            done
            
            cleanup_test_env
            print_master_results
            exit $?
            ;;
        *)
            echo -e "${TEST_RED}Error: Unknown option '$1'${TEST_NC}"
            show_usage
            exit 1
            ;;
    esac
}

# Make all test scripts executable
chmod +x "$(dirname "$0")"/test_*.sh

# Run main function with all arguments
main "$@"
