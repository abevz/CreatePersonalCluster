# Contributing to CPC (Create Personal Cluster)

Thank you for your interest in contributing to CPC! This document provides guidelines and information for contributors.

## 🎯 Getting Started

### Prerequisites
- **Development Environment**: Linux/macOS with bash
- **Python**: 3.9+ for testing framework
- **Infrastructure Access**: Proxmox VE environment for testing
- **Tools**: Git, OpenTofu/Terraform, Ansible, SOPS

### Development Setup
```bash
# 1. Fork and clone the repository
git clone https://github.com/your-username/CreatePersonalCluster.git
cd CreatePersonalCluster

# 2. Install development dependencies
pip install -r requirements-test.txt

# 3. Set up pre-commit hooks (optional)
pre-commit install

# 4. Run tests to verify setup
python tests/run_tests.py quick
```

## 📋 How to Contribute

### Types of Contributions
- **🐛 Bug Reports**: Issues with existing functionality
- **✨ Feature Requests**: New capabilities and improvements
- **📖 Documentation**: Improvements to guides and references
- **🧪 Testing**: Additional tests and test improvements
- **🔧 Code Contributions**: Bug fixes and feature implementations

### Before You Start
1. **Check existing issues** to avoid duplicates
2. **Discuss major changes** in an issue first
3. **Follow project conventions** described below
4. **Ensure backward compatibility** unless breaking change is necessary

## 🔧 Development Guidelines

### Code Style
- **Shell Scripts**: Follow bash best practices
  - Use `set -euo pipefail` for error handling
  - Quote variables: `"$variable"`
  - Use meaningful function names
  - Add comments for complex logic

- **Python**: Follow PEP 8
  - Use type hints where appropriate
  - Maximum line length: 88 characters
  - Use meaningful variable names

### Function Documentation
```bash
# English comments only
# Example function documentation
# Args:
#   $1: workspace_name - Name of the workspace to process
#   $2: operation_type - Type of operation (create/delete/update)
# Returns:
#   0: Success
#   1: Error occurred
function workspace_operation() {
    local workspace_name="$1"
    local operation_type="$2"
    
    # Implementation here
}
```

### Error Handling
- Use the existing error handling framework in `lib/error_handling.sh`
- Provide meaningful error messages
- Include context in error reports
- Use appropriate error codes

```bash
# Example error handling
if ! validate_input "$workspace_name"; then
    error_handle "$ERROR_VALIDATION" "Invalid workspace name: $workspace_name" "$SEVERITY_HIGH" "return"
    return 1
fi
```

### Testing Requirements
- **Unit Tests**: All new functions must have unit tests
- **Functional Tests**: User-facing features need functional tests
- **Integration Tests**: Complex workflows need integration tests
- **Performance Tests**: Performance-critical code needs benchmarks

```bash
# Run all tests before submitting
python tests/run_tests.py all

# Run specific test categories
python tests/run_tests.py quick        # Fast unit tests
python tests/run_tests.py functional   # Real functionality tests
python tests/run_tests.py performance  # Performance benchmarks
```

## 📖 Documentation Standards

### Code Documentation
- **All functions**: Must have clear English comments
- **Complex logic**: Explain the "why", not just the "what"
- **Configuration**: Document all configuration options
- **Examples**: Provide usage examples for new features

### User Documentation
- **User guides**: Step-by-step instructions
- **Reference docs**: Complete parameter descriptions
- **Troubleshooting**: Common issues and solutions
- **Examples**: Real-world usage scenarios

### Documentation Format
- Use **Markdown** for all documentation
- Include **code examples** with proper syntax highlighting
- Use **emojis** consistently for visual organization
- Provide **cross-references** between related documents

## 🐛 Bug Reports

### Before Reporting
1. **Search existing issues** for duplicates
2. **Test with latest version** if possible
3. **Reproduce consistently** if possible
4. **Gather system information**

### Bug Report Template
```markdown
## Bug Description
Clear description of the issue

## Environment
- CPC Version: [version]
- OS: [distribution and version]
- Proxmox VE: [version]
- OpenTofu/Terraform: [version]
- Ansible: [version]

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Expected Behavior
What should happen

## Actual Behavior
What actually happens

## Logs and Output
```
[Include relevant logs]
```

## Additional Context
Any other relevant information
```

## ✨ Feature Requests

### Feature Request Template
```markdown
## Feature Description
Clear description of the proposed feature

## Use Case
Why is this feature needed? What problem does it solve?

## Proposed Solution
How should this feature work?

## Alternative Solutions
What other approaches have you considered?

## Additional Context
Any other relevant information
```

## 🔄 Pull Request Process

### Before Submitting
1. **Create feature branch**: `git checkout -b feature/your-feature-name`
2. **Write tests**: Ensure new code is tested
3. **Update documentation**: Include relevant documentation updates
4. **Test thoroughly**: Run full test suite
5. **Check style**: Follow coding conventions

### Pull Request Template
```markdown
## Summary
Brief description of changes

## Type of Change
- [ ] Bug fix (non-breaking change)
- [ ] New feature (non-breaking change)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] Functional tests pass
- [ ] Integration tests pass (if applicable)
- [ ] Manual testing completed

## Documentation
- [ ] Code comments updated
- [ ] User documentation updated
- [ ] Examples provided (if applicable)

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No breaking changes (or breaking changes documented)
```

### Review Process
1. **Automated checks**: All CI/CD checks must pass
2. **Code review**: At least one maintainer review required
3. **Testing**: Functionality verified in test environment
4. **Documentation**: Documentation completeness verified
5. **Merge**: Squash and merge for clean history

## 🧪 Testing Guidelines

### Test Categories
- **Unit Tests**: Fast, isolated function testing
- **Functional Tests**: Real command execution testing
- **Integration Tests**: End-to-end workflow testing
- **Performance Tests**: Speed and efficiency testing

### Test Writing
```python
# Example test structure
def test_workspace_creation_functional(self):
    """Test that workspace creation actually works"""
    # Arrange
    test_workspace = f"test-{int(time.time())}"
    
    # Act
    result = tf.run_command(f'./cpc ctx {test_workspace}')
    
    # Assert
    assert result.returncode == 0, "Workspace creation failed"
    assert test_workspace in result.stdout, "Workspace not created"
    
    # Cleanup
    tf.run_command(f'./cpc delete-workspace {test_workspace}', input_text='y\n')
```

### Test Data
- **Use temporary data**: Don't affect existing configurations
- **Clean up**: Always clean up test artifacts
- **Isolate tests**: Tests should not depend on each other
- **Mock external services**: When appropriate

## 🏗️ Architecture Guidelines

### Module Structure
- **Single responsibility**: Each module has one clear purpose
- **Clean interfaces**: Well-defined function APIs
- **Error handling**: Consistent error handling throughout
- **Documentation**: All public functions documented

### Dependencies
- **Minimize dependencies**: Only add necessary dependencies
- **Version pinning**: Pin versions for reproducibility
- **Compatibility**: Maintain compatibility with supported versions
- **Documentation**: Document all dependencies and requirements

## 📊 Performance Considerations

### Optimization Guidelines
- **Caching**: Use the caching system for expensive operations
- **Parallel execution**: Utilize parallelism where safe
- **Resource efficiency**: Minimize resource usage
- **Benchmarking**: Measure performance impact

### Caching Best Practices
```bash
# Use existing cache functions
load_secrets_cached  # Instead of load_secrets
get_terraform_output_cached  # Instead of direct terraform calls

# Cache expensive operations
cache_expensive_operation() {
    local cache_file="/tmp/operation_cache_${workspace}.tmp"
    local cache_max_age=300  # 5 minutes
    
    if cache_is_valid "$cache_file" "$cache_max_age"; then
        cat "$cache_file"
        return 0
    fi
    
    # Perform expensive operation
    expensive_operation > "$cache_file"
    cat "$cache_file"
}
```

## 🔒 Security Considerations

### Security Guidelines
- **Secrets management**: Use SOPS for all secrets
- **Input validation**: Validate all user inputs
- **Privilege escalation**: Minimize sudo usage
- **Logging**: Don't log sensitive information

### Secrets Handling
```bash
# Good: Use SOPS for secrets
sops_get_value() {
    sops -d "$SOPS_FILE" | yq eval ".$1" -
}

# Bad: Hardcoded secrets
PASSWORD="hardcoded_password"  # Never do this

# Good: Environment variables for non-secrets
DEFAULT_TIMEOUT="${CPC_TIMEOUT:-300}"
```

## 📝 License

By contributing to CPC, you agree that your contributions will be licensed under the MIT License.

## ❓ Questions?

- **General questions**: Create a GitHub Discussion
- **Bug reports**: Create a GitHub Issue
- **Feature requests**: Create a GitHub Issue
- **Security issues**: Email the maintainers directly

## 🙏 Recognition

Contributors will be recognized in:
- **CHANGELOG.md**: For significant contributions
- **README.md**: For major feature additions
- **Release notes**: For notable improvements

Thank you for contributing to CPC! 🚀
