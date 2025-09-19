# Release Notes - v1.1.2 (Hotfix Release)

**Release Date:** September 3, 2025  
**Type:** Hotfix Release  
**Priority:** High - Critical Bug Fixes

## 🚨 Critical Issues Resolved

This hotfix release addresses all critical bugs discovered after v1.1.0 and v1.1.1 releases that were preventing core functionality from working correctly.

## 🔧 Bug Fixes

### Core Module Fixes
- **modules/00_core.sh**: Fixed cluster_summary data source and jq escaping issues
  - Corrected inventory generation for Ansible operations
  - Fixed data sourcing from terraform output
  - Resolved jq syntax errors in inventory creation

### Ansible Module Fixes  
- **modules/20_ansible.sh**: Fixed SSH argument formatting and array handling
  - Corrected ansible-playbook SSH arguments
  - Fixed argument array processing
  - Resolved connection issues during playbook execution

### Function Call Fixes
- **modules/50_cluster_ops.sh**: Fixed load_secrets function call
- **modules/60_tofu.sh**: Fixed load_secrets function call

## 🔄 Restored Functionality

### Ansible Playbook Restoration
- **ansible/playbooks/pb_upgrade_addons_extended.yml**: Restored 114 lines of functionality accidentally removed in commit e1544da
  - ✅ **CoreDNS**: Upgrade functionality restored
  - ✅ **ingress-nginx**: Installation functionality restored  
  - ✅ **Traefik Gateway**: Gateway API support restored
  - ✅ **cert-manager**: Cloudflare ClusterIssuer integration restored

## ✅ Verified Fixes

### Commands Working
- `./cpc status` - Now works correctly without errors
- `./cpc upgrade-addons` - Now works correctly with proper inventory generation
- All addon installations work successfully

### Tested Addons
- ✅ Traefik Gateway Controller with Gateway API
- ✅ cert-manager with Cloudflare DNS integration
- ✅ ingress-nginx controller
- ✅ CoreDNS upgrade functionality

## 📊 Impact Summary

| Component | Status | Issue | Resolution |
|-----------|--------|-------|------------|
| `./cpc status` | ✅ Fixed | Function call errors | Corrected function names |
| `./cpc upgrade-addons` | ✅ Fixed | Inventory generation failure | Fixed data sourcing |
| Ansible SSH | ✅ Fixed | Connection failures | Fixed argument formatting |
| Traefik Gateway | ✅ Restored | Missing functionality | Restored from commit 01c1ba2 |
| cert-manager | ✅ Restored | Missing Cloudflare support | Restored ClusterIssuer config |
| ingress-nginx | ✅ Restored | Missing installation | Restored installation tasks |
| CoreDNS | ✅ Restored | Missing upgrade support | Restored upgrade functionality |

## 🏗️ Technical Details

### Files Modified
- `modules/00_core.sh` (+78/-17 lines)
- `modules/20_ansible.sh` (+18/-5 lines) 
- `modules/50_cluster_ops.sh` (function call fix)
- `modules/60_tofu.sh` (function call fix)
- `ansible/playbooks/pb_upgrade_addons_extended.yml` (+114 lines)

### Root Cause Analysis
The issues were caused by:
1. **Function naming inconsistencies** introduced in module refactoring
2. **Accidental deletion** of addon functionality during automated ansible-lint cleanup
3. **Data sourcing changes** that broke inventory generation
4. **SSH argument formatting** changes that broke Ansible connectivity

## 🚀 Upgrade Instructions

If you're running v1.1.0 or v1.1.1:

```bash
git pull origin main
git checkout v1.1.2
```

All functionality should work immediately after upgrade.

## 🔍 Testing Validation

Confirmed working:
- ✅ Status command execution
- ✅ Addon upgrade/installation  
- ✅ Traefik Gateway with Gateway API
- ✅ cert-manager with Cloudflare DNS challenges
- ✅ ingress-nginx installation
- ✅ CoreDNS upgrades
- ✅ Ansible inventory generation
- ✅ SSH connectivity for all operations

---

**Previous Releases:**
- [v1.1.1 Release Notes](release_notes_v1.1.1.md)
- [v1.1.0 Release Notes](RELEASE_NOTES.md)
