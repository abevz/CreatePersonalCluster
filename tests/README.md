# CPC Test Suite

This directory contains comprehensive tests for the CPC (Create Personal Cluster) project.

## Test Structure

### Unit Tests
- `test_00_core.py` - Core module unit tests (32 tests, all passing)
- `test_cpc_comprehensive.py` - Comprehensive CPC functionality tests
- `test_cpc_modules.py` - Module structure and function tests
- `test_cpc_performance.py` - Performance and caching tests
- `test_shell.py` - Shell script linting and validation
- `test_ansible.py` - Ansible playbook validation
- `test_60_tofu_refactored.py` - Tofu/OpenTofu module tests

### Integration Tests
- `test_cpc_workflows.py` - End-to-end workflow tests
- `test_cpc_functional.py` - Functional testing

## Running Tests

### Python Test Runner (Recommended)
```bash
# Run only core module tests (32 tests, all passing)
python tests/run_tests.py core

# Run quick unit tests (includes core tests)
python tests/run_tests.py quick

# Run all test suites
python tests/run_tests.py all

# Run functional tests
python tests/run_tests.py functional

# Run performance tests
python tests/run_tests.py performance
```

### Direct Pytest (Alternative)
```bash
# Run core module tests directly
python -m pytest tests/unit/test_00_core.py -v

# Run all unit tests
python -m pytest tests/unit/ -v
```

### Bash Test Runner
```bash
# Run all tests (includes shellcheck, ansible-lint, etc.)
./run_tests.sh
```

## Core Module Tests (`test_00_core.py`)

Our comprehensive unit test suite for the core bash functions:

### Test Coverage
- ✅ `parse_core_command()` - Command parsing and validation
- ✅ `route_core_command()` - Command routing logic
- ✅ `handle_core_errors()` - Error handling
- ✅ `determine_script_directory()` - Path resolution
- ✅ `navigate_to_parent_directory()` - Directory navigation
- ✅ `validate_repo_path()` - Repository validation
- ✅ `get_repo_path()` - Repository path retrieval
- ✅ `check_cache_freshness()` - Cache validation
- ✅ `decrypt_secrets_file()` - SOPS decryption
- ✅ `locate_secrets_file()` - Secrets file location
- ✅ `validate_secrets_integrity()` - Secrets validation
- ✅ `locate_env_file()` - Environment file location
- ✅ `parse_env_file()` - Environment parsing
- ✅ `read_context_file()` - Context file reading
- ✅ `write_context_file()` - Context file writing
- ✅ `return_validation_result()` - Input validation
- ✅ `display_current_context()` - Context display
- ✅ `set_new_context()` - Context switching
- ✅ `validate_clone_parameters()` - Clone validation
- ✅ `confirm_deletion()` - Deletion confirmation
- ✅ `destroy_resources()` - Resource destruction
- ✅ `core_clear_cache()` - Cache clearing
- ✅ `core_auto_command()` - Auto environment setup

### Key Features
- **Isolated Testing**: Each test runs in a temporary directory
- **Proper Sourcing**: Correct bash script loading order (lib → config → modules)
- **Mock Dependencies**: Handles missing external tools gracefully
- **Comprehensive Coverage**: Tests both success and failure scenarios
- **Fast Execution**: All 32 tests complete in ~35 seconds

### Test Results
```
✅ PASSED: 32/32 tests (100% success rate)
⏱️  Duration: ~35 seconds
🎯 Coverage: Core bash functions fully tested
```

## Test Environment

### Dependencies
- Python 3.8+
- pytest
- subprocess (built-in)
- pathlib (built-in)
- shutil (built-in)

### External Tools (Optional)
- sops (for secrets decryption)
- tofu/opentofu (for infrastructure)
- kubectl (for Kubernetes operations)
- ansible (for configuration management)

## Contributing

When adding new tests:
1. Follow the existing naming convention: `test_<function_name>_<scenario>`
2. Use descriptive test names that explain what is being tested
3. Include both positive and negative test cases
4. Add proper docstrings explaining test purpose
5. Ensure tests are isolated and don't depend on external state

## CI/CD Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Run Core Tests
  run: python tests/run_tests.py core

- name: Run All Tests
  run: python tests/run_tests.py all
```
