# SSH Commands Workspace Context Fix

## Issue

When using `cpc clear-ssh-hosts --all` or `cpc clear-ssh-maps --all`, the commands would change the active Tofu workspace context and not restore it, causing the current context to "drift" to the last workspace checked.

## Example of the Problem

```bash
# Current context: ubuntu
./cpc ctx
# Current cluster context: ubuntu
# Available Tofu workspaces:
#   * ubuntu

./cpc clear-ssh-maps --all --dry-run
# Command checks: debian, rocky, suse (in that order)

./cpc ctx
# Current cluster context: ubuntu  (from CPC context file)
# Available Tofu workspaces:
#   * suse    ← Context drifted to 'suse'!
#   ubuntu
```

## Root Cause

The `get_vm_ips_from_context()` function in both commands was switching Tofu workspaces but only restoring the directory with `popd`, not the workspace context:

```bash
# Before fix:
pushd "$terraform_dir" > /dev/null || return 1
tofu workspace select "$context" &>/dev/null
# ... get VM IPs ...
popd > /dev/null  # Only restores directory, not workspace!
```

## Solution

Modified the `get_vm_ips_from_context()` function in both commands to save and restore the original workspace:

```bash
# After fix:
pushd "$terraform_dir" > /dev/null || return 1

# Save current workspace before switching
local original_workspace
original_workspace=$(tofu workspace show 2>/dev/null)

tofu workspace select "$context" &>/dev/null
# ... get VM IPs ...

# Restore original workspace
if [ -n "$original_workspace" ] && [ "$original_workspace" != "$context" ]; then
  tofu workspace select "$original_workspace" &>/dev/null
fi

popd > /dev/null
```

## Files Modified

- `/home/abevz/Projects/kubernetes/my-kthw/cpc` - Fixed `get_vm_ips_from_context()` in both `clear-ssh-hosts` and `clear-ssh-maps` commands

## Testing

### Before Fix
```bash
./cpc ctx                                 # Shows: ubuntu
./cpc clear-ssh-maps --all --dry-run      # Checks all workspaces
./cpc ctx                                 # Shows: suse (last checked)
```

### After Fix
```bash
./cpc ctx                                 # Shows: ubuntu
./cpc clear-ssh-maps --all --dry-run      # Checks all workspaces
./cpc ctx                                 # Shows: ubuntu (preserved!)
```

## Impact

### ✅ **Fixed**
- Workspace context preservation when using `--all` option
- Consistent behavior across all CPC commands
- No more "context drift" issues

### ✅ **Maintained**
- All existing functionality works unchanged
- Single-context operations unaffected
- No breaking changes to command interface

### ✅ **Commands Affected**
- `cpc clear-ssh-hosts --all`
- `cpc clear-ssh-maps --all`

## Related Commands

This fix ensures consistency with other CPC commands that switch workspaces temporarily, such as:
- `cpc deploy` commands
- `cpc get-kubeconfig`
- Other workspace-aware operations

All CPC commands should now properly preserve the user's current workspace context.
