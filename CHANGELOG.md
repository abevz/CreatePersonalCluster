# Changelog - CPC Project

All notable changes to the CPC (Cluster Provisioning Control) project will be documented in this file.

## [Unreleased]

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
