# Pull Request

## 📋 Summary
<!-- Brief description of the changes -->

## 🔧 Type of Change
<!-- Mark the relevant option with an "x" -->
- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] ✨ New feature (non-breaking change which adds functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📖 Documentation update
- [ ] 🧪 Test improvements
- [ ] 🔧 Code refactoring
- [ ] ⚡ Performance improvement
- [ ] 🔒 Security improvement

## 🎯 Changes Made
<!-- Detailed description of what was changed -->

### Modified Components
<!-- List the components/modules that were changed -->
- [ ] Core CPC commands
- [ ] Proxmox module (10)
- [ ] K8s cluster module (30)
- [ ] K8s nodes module (40)
- [ ] Cluster operations module (50)
- [ ] DNS/SSL module (70)
- [ ] Testing framework
- [ ] Documentation
- [ ] Other: ___________

### Files Changed
<!-- List the main files that were modified -->
- `path/to/file1.sh` - Description of changes
- `path/to/file2.py` - Description of changes

## 🧪 Testing
<!-- Describe the testing that was performed -->

### Test Results
- [ ] Unit tests pass (`python tests/run_tests.py unit`)
- [ ] Functional tests pass (`python tests/run_tests.py functional`)
- [ ] Integration tests pass (`python tests/run_tests.py integration`)
- [ ] Manual testing completed
- [ ] Performance testing completed (if applicable)

### Test Environment
<!-- Describe your test environment -->
- **OS**: 
- **Proxmox VE**: 
- **OpenTofu**: 
- **Ansible**: 

### Manual Testing Details
<!-- Describe manual testing performed -->
```bash
# Commands tested:
./cpc command1
./cpc command2

# Expected results:
# - Result 1
# - Result 2
```

## 📖 Documentation
<!-- Documentation changes and updates -->

- [ ] Code comments updated
- [ ] User documentation updated
- [ ] API documentation updated (if applicable)
- [ ] Examples provided
- [ ] CHANGELOG.md updated

### Documentation Changes
<!-- List documentation changes made -->
- Updated `docs/file.md` - Description
- Added examples in `examples/` - Description

## 🔗 Related Issues
<!-- Link related issues -->
- Fixes #123
- Closes #456
- Related to #789

## 📸 Screenshots
<!-- If applicable, add screenshots to help explain your changes -->

## ⚠️ Breaking Changes
<!-- If this is a breaking change, describe what breaks and how to migrate -->

### What breaks:
- Description of breaking changes

### Migration guide:
```bash
# Old way:
./cpc old-command

# New way:
./cpc new-command
```

## 🔍 Code Review Checklist

### Code Quality
- [ ] Code follows project style guidelines
- [ ] Code is self-documenting with clear variable/function names
- [ ] Complex logic is commented
- [ ] Error handling is appropriate
- [ ] No hardcoded values (use configuration)
- [ ] Security best practices followed

### Functionality
- [ ] Feature works as intended
- [ ] Edge cases are handled
- [ ] Input validation is present
- [ ] Output is consistent with existing patterns
- [ ] Backward compatibility maintained (unless breaking change)

### Testing
- [ ] Sufficient test coverage
- [ ] Tests are meaningful and test actual functionality
- [ ] Tests are maintainable
- [ ] Test data is cleaned up
- [ ] Performance impact is acceptable

## 🎉 Additional Notes
<!-- Any additional information for reviewers -->

## 📋 Pre-merge Checklist
- [ ] All CI/CD checks pass
- [ ] Code review completed
- [ ] Tests verified in test environment
- [ ] Documentation reviewed
- [ ] Ready for merge
