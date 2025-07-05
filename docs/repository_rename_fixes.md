# Repository Rename Fixes

## Summary

This document describes the fixes applied after renaming the repository from `my-kthw-cpc` to `CreatePersonalCluster`.

## Issues Fixed

### 1. Config Directory Path Update
**Problem**: The CPC tool was looking for config files in `~/.config/my-kthw-cpc/`
**Solution**: Updated `CONFIG_DIR` in the `cpc` script to `~/.config/cpc`

### 2. Repository Path Update  
**Problem**: Environment variables pointed to old repository path
**Solution**: Updated `REPO_PATH` in both `cpc.env` and `cpc.env.example` to the new path

### 3. Kubeconfig Path Update
**Problem**: KUBECONFIG was pointing to workspace-specific location
**Solution**: Updated `KUBECONFIG` to `~/.kube/config` for consistency

### 4. Terraform/OpenTofu Backend Reconnection
**Problem**: After repo rename, Terraform couldn't connect to S3 backend
**Solution**: 
- Added MinIO credentials loading from `secrets.sops.yaml` to the `load_secrets()` function
- Removed hardcoded AWS credentials from `cpc.env` files
- Added proper AWS environment variable exports in `load_secrets()`
- Ran `tofu init -reconfigure` to reconnect to S3 backend

## Changes Made

### Modified Files

1. **`cpc`** (main script)
   - Updated `CONFIG_DIR` to `~/.config/cpc`
   - Enhanced `load_secrets()` function to load MinIO credentials from SOPS
   - Added AWS environment variable exports

2. **`cpc.env`**
   - Updated `REPO_PATH` to new repository location
   - Updated `KUBECONFIG` to `~/.kube/config`
   - Added MinIO/S3 section with documentation (credentials loaded from secrets)

3. **`cpc.env.example`**
   - Updated `REPO_PATH` to new repository location
   - Updated `KUBECONFIG` to `~/.kube/config`
   - Added MinIO/S3 section with documentation

### Commands Executed
```bash
# Reconnect to S3 backend
cd /home/abevz/Projects/kubernetes/CreatePersonalCluster/terraform
tofu init -reconfigure

# Reinitialize CPC configuration
./cpc setup-cpc

# Clean up old config directory
rm -rf ~/.config/my-kthw-cpc
```

## State Preservation

✅ **All Terraform workspaces preserved**: default, debian, rocky, suse, ubuntu
✅ **Ubuntu workspace cluster state intact**: All VMs (cu1, wu1, wu2) and infrastructure preserved
✅ **S3 backend connectivity restored**: MinIO credentials loaded from secrets.sops.yaml
✅ **Context switching works**: Can switch between workspaces without issues

## Verification

The following commands confirm everything is working:
```bash
# Check current context and workspaces
./cpc ctx

# Verify infrastructure state
./cpc deploy plan

# Test workspace switching
./cpc ctx rocky
./cpc ctx ubuntu

# Verify secrets loading
./cpc load_secrets
```

## Key Lessons

1. **Centralized Configuration**: All sensitive credentials should be stored in `secrets.sops.yaml` and loaded dynamically
2. **Dynamic Path Detection**: Use automatic path detection instead of hardcoded paths to support any directory name
3. **State Management**: Terraform state can be preserved during backend migrations with proper initialization
4. **Testing**: Always verify all workflows after major changes like repository renames

## Future Considerations

- ✅ **FIXED**: Dynamic path detection implemented - project now works in any directory name
- ✅ **FIXED**: Credentials loading from secrets.sops.yaml restored
- Consider using relative paths where possible to avoid hardcoded absolute paths
- Document all external dependencies (MinIO, SOPS, etc.) for easier troubleshooting  
- Add automated tests for critical workflows to catch issues early

## Additional Improvements Made

### Dynamic Path Detection
- Removed hardcoded `REPO_PATH` from `cpc.env` and `cpc.env.example`
- System now automatically detects repository location using `cpc setup-cpc`
- Project works in any directory name without modification
- Multiple installations supported with automatic path switching

### Benefits
- **Portability**: Clone to any directory name and it works
- **Team Collaboration**: No merge conflicts from hardcoded paths
- **Multiple Environments**: Support for dev/staging/prod installations
- **Maintenance**: No path updates needed after repository moves
