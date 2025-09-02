# 🧪 Testing Documentation

## Overview

This document provides comprehensive guidance on the CPC testing framework, including how to run tests, add new tests, and maintain test quality.

## 🏗️ Test Structure

```
tests/
├── __init__.py              # Test framework utilities
├── unit/                    # Unit tests
│   ├── test_core.py        # Core functionality tests
│   ├── test_ansible.py     # Ansible integration tests
│   └── test_shell.py       # Shell script validation tests
└── integration/            # Integration tests
    └── test_integration.py # Cross-component integration tests
```

## 🚀 Running Tests

### Quick Commands

```bash
# Run all tests
make test

# Run only unit tests
make test-unit

# Run only integration tests
make test-integration

# Run linting tools
make lint
```

### Manual Test Execution

```bash
# Run specific test file
python -m pytest tests/unit/test_core.py -v

# Run specific test class
python -m pytest tests/unit/test_core.py::TestCoreFunctions -v

# Run specific test method
python -m pytest tests/unit/test_core.py::TestCoreFunctions::test_project_structure -v

# Run with coverage
python -m pytest tests/unit/ --cov=tests --cov-report=html
```

## 📝 Adding New Tests

### 1. Unit Tests

#### Basic Test Structure

```python
#!/usr/bin/env python3
"""
Unit tests for [module_name]
"""

import pytest
from tests import test_framework


class TestModuleName:
    """Test class for module functionality"""

    def test_basic_functionality(self):
        """Test basic functionality"""
        # Arrange
        expected = "expected_result"

        # Act
        result = some_function()

        # Assert
        assert result == expected

    def test_error_handling(self):
        """Test error handling scenarios"""
        # Test error conditions
        with pytest.raises(ValueError):
            function_that_raises_error("invalid_input")
```

#### File Structure Validation Test

```python
def test_file_exists_and_executable(self):
    """Test that required files exist and are executable"""
    # Check main script
    assert test_framework.check_file_exists("cpc")
    assert test_framework.run_command("test -x cpc").returncode == 0

    # Check modules
    for module in ["00_core.sh", "20_ansible.sh", "30_k8s_cluster.sh"]:
        module_path = f"modules/{module}"
        assert test_framework.check_file_exists(module_path)
        assert test_framework.run_command(f"test -x {module_path}").returncode == 0
```

#### Command Execution Test

```python
def test_command_execution(self):
    """Test command execution and output"""
    result = test_framework.run_command("./cpc --help")

    # Check return code
    assert result.returncode == 0

    # Check output contains expected content
    assert "Usage:" in result.stdout
    assert "Available commands:" in result.stdout
```

### 2. Integration Tests

#### Basic Integration Test

```python
class TestIntegration:
    """Integration tests for component interactions"""

    def test_module_loading(self):
        """Test that modules can be loaded without errors"""
        result = test_framework.run_command('bash -c "source modules/00_core.sh && echo 'Module loaded'"')

        assert result.returncode == 0
        assert "Module loaded" in result.stdout

    def test_configuration_parsing(self):
        """Test configuration file parsing"""
        # Create temporary config
        import tempfile
        import os

        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write("TEST_VAR=test_value\n")
            temp_config = f.name

        try:
            # Test parsing
            result = test_framework.run_command(f'bash -c "source {temp_config} && echo $TEST_VAR"')
            assert result.returncode == 0
            assert "test_value" in result.stdout.strip()
        finally:
            os.unlink(temp_config)
```

### 3. Shell Script Linting Tests

#### ShellCheck Validation Test

```python
def test_shellcheck_validation(self):
    """Test that shell scripts pass shellcheck validation"""
    import subprocess

    # Test main script
    result = subprocess.run(['shellcheck', 'cpc'],
                          capture_output=True, text=True)

    # ShellCheck returns 0 for clean scripts, non-zero for issues
    assert result.returncode == 0, f"ShellCheck failed: {result.stderr}"

    # Test modules
    for module in ["00_core.sh", "20_ansible.sh"]:
        result = subprocess.run(['shellcheck', f'modules/{module}'],
                              capture_output=True, text=True)
        assert result.returncode == 0, f"ShellCheck failed for {module}: {result.stderr}"
```

#### Bashate Style Test

```python
def test_bashate_validation(self):
    """Test that shell scripts follow bashate style guidelines"""
    import subprocess

    # Test main script
    result = subprocess.run(['bashate', 'cpc'],
                          capture_output=True, text=True)

    # Bashate returns 0 for compliant scripts
    assert result.returncode == 0, f"Bashate failed: {result.stderr}"
```

### 4. Ansible Playbook Tests

#### Playbook Structure Test

```python
def test_ansible_playbook_structure(self):
    """Test Ansible playbook structure and syntax"""
    import yaml
    import os

    playbook_dir = "ansible/playbooks"

    for filename in os.listdir(playbook_dir):
        if filename.endswith(('.yml', '.yaml')):
            filepath = os.path.join(playbook_dir, filename)

            # Test YAML syntax
            with open(filepath, 'r') as f:
                try:
                    data = yaml.safe_load(f)
                    assert isinstance(data, list), f"{filename} should contain a list of plays"
                except yaml.YAMLError as e:
                    pytest.fail(f"YAML syntax error in {filename}: {e}")
```

## 🛠️ Test Framework Utilities

### Available Helper Functions

```python
from tests import test_framework

# Run shell commands
result = test_framework.run_command("ls -la")
assert result.returncode == 0
assert "README.md" in result.stdout

# Check file existence
assert test_framework.check_file_exists("cpc")

# Read file content
content = test_framework.read_file("README.md")
assert "CPC" in content

# Check file permissions
assert test_framework.run_command("test -x cpc").returncode == 0
```

### Custom Assertions

```python
def assert_command_success(cmd):
    """Assert that command executes successfully"""
    result = test_framework.run_command(cmd)
    assert result.returncode == 0, f"Command failed: {cmd}\n{result.stderr}"

def assert_file_contains(filename, text):
    """Assert that file contains specific text"""
    content = test_framework.read_file(filename)
    assert text in content, f"File {filename} doesn't contain: {text}"

def assert_module_structure(module_name):
    """Assert that module has correct structure"""
    module_path = f"modules/{module_name}"

    # Check shebang
    with open(module_path, 'r') as f:
        first_line = f.readline().strip()
        assert first_line == "#!/bin/bash", f"Module {module_name} missing shebang"

    # Check executable
    assert test_framework.run_command(f"test -x {module_path}").returncode == 0
```

## 📊 Test Coverage

### Running Coverage Reports

```bash
# Generate HTML coverage report
python -m pytest tests/ --cov=tests --cov-report=html

# View coverage in browser
open htmlcov/index.html

# Generate coverage for specific modules
python -m pytest tests/unit/test_core.py --cov=modules --cov-report=term-missing
```

### Coverage Goals

- **Unit Tests**: >90% coverage of test framework
- **Integration Tests**: Cover all major component interactions
- **Linting Tests**: Validate all shell scripts and Ansible playbooks

## 🔧 Maintenance

### Updating Test Dependencies

```bash
# Update virtual environment
pip install -r requirements.txt

# Update specific packages
pip install --upgrade pytest pytest-cov pytest-mock
```

### Adding New Test Categories

1. Create new test file in appropriate directory
2. Add test class with descriptive name
3. Implement test methods following naming convention
4. Update this documentation
5. Add to CI/CD pipeline if applicable

### Test Naming Conventions

```python
# Test files
test_[module_name].py

# Test classes
Test[ModuleName]

# Test methods
test_[functionality]_[scenario]

# Examples
test_core_functionality
test_ansible_playbook_validation
test_shell_script_linting
```

## 🚨 Troubleshooting

### Common Issues

1. **Import Errors**: Ensure virtual environment is activated
2. **Permission Errors**: Make sure test files are executable
3. **Path Issues**: Use absolute paths or proper relative paths
4. **Dependency Issues**: Update requirements.txt

### Debug Mode

```bash
# Run tests with debug output
python -m pytest tests/ -v -s --tb=long

# Run specific test with debugging
python -m pytest tests/unit/test_core.py::TestCoreFunctions::test_project_structure -v -s
```

## 📈 Best Practices

1. **Write Tests First**: Follow TDD principles
2. **Keep Tests Simple**: One assertion per test
3. **Use Descriptive Names**: Test names should explain what they test
4. **Test Edge Cases**: Don't forget error conditions
5. **Maintain Test Independence**: Tests should not depend on each other
6. **Regular Maintenance**: Update tests when code changes

## 🔗 Related Documentation

- [Project README](../README.md)
- [Development Setup](../docs/project_setup_guide.md)
- [Code Quality Standards](../docs/code_quality_guide.md)
