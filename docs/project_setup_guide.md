# CPC Project Setup Guide

## Initial Setup for Any Directory

The CPC (Cluster Provision & Configure) tool is designed to work from any directory name. When you clone or move the repository, follow these steps:

### 1. Clone the Repository
```bash
git clone <repository-url> MyCustomDirectoryName
cd MyCustomDirectoryName
```

### 2. Initialize CPC
```bash
./cpc setup-cpc
```

This command automatically:
- Detects the current directory path
- Saves it to `~/.config/cpc/repo_path`
- Configures the tool to work from this location

### 3. Verify Setup
```bash
./cpc ctx
```

This should show your current workspace and available Tofu workspaces.

## How It Works

The CPC tool uses a dynamic path detection system:

1. **Automatic Path Detection**: The `cpc setup-cpc` command uses `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` to detect the script's directory
2. **Path Storage**: The detected path is saved in `~/.config/cpc/repo_path`
3. **Dynamic Loading**: All CPC commands read the path from this file using `get_repo_path()` function

## Configuration Files

### cpc.env
- Does NOT contain hardcoded `REPO_PATH` 
- Uses dynamic path detection
- Safe to copy between different directory names

### cpc.env.example
- Template file with example configurations
- No hardcoded paths
- Safe to use as reference for new setups

## Important Notes

### ✅ DO (Recommended Workflow)
1. Clone repository to any directory name
2. Run `./cpc setup-cpc` 
3. Configure your `cpc.env` file with your settings
4. Use CPC commands normally

### ❌ DON'T (Avoid These)
- Don't manually edit `~/.config/cpc/repo_path`
- Don't hardcode paths in `cpc.env`
- Don't copy config files between different repository locations without running `setup-cpc`

## Moving or Renaming the Repository

If you need to move or rename the repository directory:

1. Move/rename the directory:
   ```bash
   mv CreatePersonalCluster MyNewProjectName
   cd MyNewProjectName
   ```

2. Re-initialize CPC:
   ```bash
   ./cpc setup-cpc
   ```

3. Verify it works:
   ```bash
   ./cpc ctx
   ```

## Multiple Installations

You can have multiple installations of the CPC tool in different directories. Each installation maintains its own configuration in `~/.config/cpc/`. The last directory where you ran `setup-cpc` will be the active one.

To switch between installations:
```bash
cd /path/to/first/installation
./cpc setup-cpc

# Now CPC commands will use this installation

cd /path/to/second/installation  
./cpc setup-cpc

# Now CPC commands will use this installation
```

## Troubleshooting

### "Repository path not set" Error
If you see this error:
```
Repository path not set. Run 'cpc setup-cpc' to set this value.
```

Solution:
```bash
./cpc setup-cpc
```

### Wrong Directory Being Used
If CPC is using the wrong directory:
```bash
# Check current path
cat ~/.config/cpc/repo_path

# Re-initialize from correct directory
cd /correct/path/to/project
./cpc setup-cpc
```

## Benefits of Dynamic Path Detection

1. **Portability**: Works in any directory name
2. **Team Collaboration**: No merge conflicts from hardcoded paths
3. **Multiple Environments**: Support for multiple installations
4. **Maintenance**: No need to update paths after repository moves
5. **Flexibility**: Easy to test different versions or configurations
