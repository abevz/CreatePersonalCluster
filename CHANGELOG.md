# Changelog - CPC Project

All notable changes to the CPC (Cluster Provisioning Control) project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-09-02 - Performance Optimization Release ⚡

### Added
- **cluster-info --quick mode**: Ultra-fast cluster status (0.1s execution time)
- **Two-tier terraform caching**: Short-term (30s) and long-term (5min) cache layers
- **Smart workspace detection**: Avoids unnecessary terraform workspace switches
- **Context-aware cache management**: Separate cache files per workspace

### Changed
- **cluster-info performance**: Improved from 22s to 0.44s (50x faster)
- **First run optimization**: Reduced from 22s to 7.2s (3x faster)
- **Cache strategy**: Enhanced multi-level caching with intelligent invalidation
- **Help text**: Updated cluster-info usage to include --quick option

### Performance Improvements
- **cluster-info (cached)**: 0.44s vs 22s (50x improvement)
- **cluster-info --quick**: 0.1s vs 22s (220x improvement)
- **cluster-info (first run)**: 7.2s vs 22s (3x improvement)
- **Workspace operations**: Smart state management reduces unnecessary switches

### Technical
- **Optimized terraform operations**: Efficient workspace state handling
- **Reduced I/O operations**: Better cache file management
- **Memory optimization**: Improved resource utilization
- **Network efficiency**: Fewer remote state API calls

## [1.0.0] - 2025-09-02 - Production Ready Release 🎉

### Added
- **Complete Kubernetes cluster automation** with Proxmox VE, Terraform/OpenTofu, and Ansible
- **Multi-OS support**: Ubuntu 24.04/22.04/20.04, Debian 12/11, Rocky Linux 9/8, SUSE openSUSE Leap 15.x
- **Intelligent workspace management** with environment isolation and automatic switching
- **Performance caching system**: 30x speed improvement (25s → 0.84s for status commands)
- **Comprehensive test suite**: 59 tests with 100% pass rate using pytest framework
- **Enterprise-grade error handling**: Retry mechanisms, timeout handling, graceful degradation
- **Rich addon ecosystem**: Calico CNI, MetalLB, cert-manager, ArgoCD, Prometheus, Grafana
- **DNS/SSL automation**: Automatic certificate generation with DNS hostname support
- **Debug mode**: Detailed troubleshooting with `--debug` flag
- **Recovery system**: Automatic recovery log generation for troubleshooting

### Performance
- **Multi-tier caching**: Secrets (5min TTL), Terraform (30s TTL), SSH (10s TTL)
- **Automatic cache invalidation**: Smart cache management on workspace changes
- **Parallel operations**: Optimized concurrent task execution
- **Smart retries**: Automatic failure recovery with exponential backoff

### Security
- **SOPS integration**: Secure secrets management with encryption
- **SSH key authentication**: Key-based access control
- **Network policies**: Kubernetes security best practices
- **Certificate automation**: SSL/TLS certificate generation and management

### User Experience
- **Interactive addon menu**: Menu-driven addon installation and management
- **Comprehensive documentation**: User guides, references, and troubleshooting
- **Workspace system**: Easy environment switching and management
- **Status commands**: Fast cluster health monitoring
- **Template automation**: Automatic VM template creation for all supported OS

### Testing & Quality
- **Functional testing**: Real-world scenario validation
- **Performance benchmarking**: Speed and efficiency monitoring
- **Integration tests**: End-to-end workflow validation
- **Unit tests**: Comprehensive code coverage
- **Test automation**: CI/CD ready test framework

## [2025-06-10] - Interactive upgrade-addons

### Added
- **Interactive menu interface** for `./cpc upgrade-addons` command
- Menu displays 9 options for addon selection (all, calico, metallb, etc.)
- Input validation for menu choices
- Enhanced help documentation with examples

### Changed
- **BREAKING:** `./cpc upgrade-addons` now shows interactive menu instead of auto-installing all addons
- Updated help text to reflect new behavior and usage patterns
- Modified documentation throughout the project to reflect new workflow

### Fixed
- Eliminated unexpected automatic installation of all addons when running base command
- Improved user control over addon installation process

### Documentation
- Updated `complete_cluster_creation_guide.md` with new workflow
- Updated `cpc_upgrade_addons_reference.md` with interactive examples
- Updated `README.md` quick start guide
- Added recent updates section to `documentation_index.md`

### Technical Details
- Changed default `addon_name` from `"all"` to empty string
- Added interactive menu logic with numbered choices
- Preserved backward compatibility with `--addon` parameter
- Enhanced command description in usage display

### Migration Guide
```bash
# Old behavior (installed all addons automatically):
./cpc upgrade-addons

# New behavior (shows menu):
./cpc upgrade-addons
# User selects from menu

# To get old behavior (install all addons directly):
./cpc upgrade-addons --addon all
```

## [2025-06-10] - Cluster Creation Workflow Fixes

### Fixed
- **Worker node joining**: Fixed recursive template variable issue in `pb_add_nodes.yml`
- **Containerd CRI**: Removed `creates` parameter to allow proper configuration regeneration
- **Dynamic IP resolution**: Control plane endpoint now resolved dynamically

### Added
- Comprehensive troubleshooting documentation
- Working 3-node cluster deployment verified

### Technical Details
- Modified `pb_add_nodes.yml` to gather facts from control plane dynamically
- Updated `install_kubernetes_cluster.yml` containerd configuration task
- Verified cluster creation with Kubernetes v1.31.9 and Calico CNI

---

## Format Guidelines

This changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format:

- **Added** for new features
- **Changed** for changes in existing functionality  
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** for vulnerability fixes
