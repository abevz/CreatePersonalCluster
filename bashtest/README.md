# Bash Test Suite for CPC

This directory contains all bash-based unit tests for the CPC (Create Personal Cluster) system.

## Test Files

- `bash_test_framework.sh` - Core testing framework and utilities
- `run_all_tests.sh` - Master test runner that executes all test suites
- `test_core_module.sh` - Tests for core functionality (modules/00_core.sh)
- `test_k8s_cluster_module.sh` - Tests for Kubernetes cluster module (modules/30_k8s_cluster.sh)
- `test_proxmox_module.sh` - Tests for Proxmox integration (modules/10_proxmox.sh)
- `test_ansible_module.sh` - Tests for Ansible module (modules/20_ansible.sh)
- `test_tofu_module.sh` - Tests for Terraform/OpenTofu module (modules/60_tofu.sh)
- `test_caching_integration.sh` - Tests for caching system integration

## Running Tests

### Run All Tests
```bash
./bashtest/run_all_tests.sh
```

### Run Individual Test Suite
```bash
./bashtest/test_core_module.sh
./bashtest/test_k8s_cluster_module.sh
# etc.
```

### Run from Repository Root
```bash
cd /path/to/CreatePersonalCluster
./bashtest/run_all_tests.sh
```

## Test Framework Features

- Comprehensive assertion functions
- Setup/teardown hooks
- Detailed test reporting
- Performance metrics
- Mocking capabilities for external dependencies
- Integration with CPC caching system

## Directory Structure

```
bashtest/
├── README.md                      # This file
├── bash_test_framework.sh         # Core testing framework
├── run_all_tests.sh              # Master test runner
├── test_core_module.sh           # Core module tests
├── test_k8s_cluster_module.sh    # K8s cluster tests
├── test_proxmox_module.sh        # Proxmox tests
├── test_ansible_module.sh        # Ansible tests
├── test_tofu_module.sh           # Tofu/Terraform tests
└── test_caching_integration.sh   # Caching system tests
```

The main `tests/` directory now contains only Python-based tests for integration and comprehensive testing scenarios.
