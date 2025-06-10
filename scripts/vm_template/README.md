# VM Template Creation System

This directory contains a modular VM template creation system for Proxmox VE, designed to replace the original monolithic approach with a scalable, maintainable architecture.

## Architecture Overview

```
vm_template/
├── create_template_dispatcher.sh    # Main entry point - detects OS and routes
├── shared/
│   └── common_functions.sh          # Shared functions for all OS types
├── ubuntu/
│   ├── create_ubuntu_template.sh    # Ubuntu-specific implementation
│   ├── ubuntu-cloud-init-userdata.yaml
│   └── README.md
├── debian/
│   ├── create_debian_template.sh    # Debian-specific implementation  
│   ├── debian-cloud-init-userdata.yaml
│   └── README.md
├── rocky/
│   ├── create_rocky_template.sh     # Rocky Linux-specific implementation
│   ├── rocky-cloud-init-userdata.yaml
│   └── README.md
├── suse/
│   ├── create_suse_template.sh      # SUSE-specific implementation
│   ├── suse-cloud-init-userdata.yaml
│   └── README.md
└── create_template_helper.sh        # Legacy monolithic script (fallback)
```

## Key Benefits

### 🔧 **Maintainability**
- **Before**: 522-line monolithic script with OS-specific logic scattered throughout
- **After**: Each OS script is ~150-200 lines with clear function boundaries

### 📈 **Scalability** 
- **Before**: Adding new OS support required modifying the large monolithic script
- **After**: New OS support = create new directory with standardized structure

### 📖 **Readability**
- **Before**: Complex nested conditionals for different OS types
- **After**: Clean separation of concerns with dispatcher pattern

### 🧪 **Testing**
- **Before**: Testing one OS could break others due to shared code paths
- **After**: Each OS implementation can be tested independently

## Usage

### Automatic OS Detection
The system automatically detects the OS type from the `IMAGE_NAME` variable:

| OS Type | Image Name Patterns | Script Called |
|---------|-------------------|---------------|
| Ubuntu | `*ubuntu*`, `*Ubuntu*` | `ubuntu/create_ubuntu_template.sh` |
| Debian | `*debian*`, `*Debian*` | `debian/create_debian_template.sh` |
| Rocky Linux | `*Rocky*`, `*rocky*` | `rocky/create_rocky_template.sh` |
| SUSE/openSUSE | `*suse*`, `*SUSE*`, `*openSUSE*` | `suse/create_suse_template.sh` |

### Entry Points

1. **Main Template Script** (Recommended)
   ```bash
   ./template.sh
   ```
   - Called by main `cpc` command
   - Handles environment setup and calls dispatcher

2. **Direct Dispatcher** (For debugging)
   ```bash
   cd vm_template
   ./create_template_dispatcher.sh
   ```
   - Requires environment variables to be set
   - All variables from `cpc.env` and secrets from SOPS

3. **OS-Specific Scripts** (For development/testing)
   ```bash
   cd vm_template/ubuntu
   ./create_ubuntu_template.sh
   ```
   - Requires shared functions and environment variables

## Environment Requirements

### Variables (from cpc.env)
- `IMAGE_NAME` - Determines OS type and routing
- `TEMPLATE_VM_ID`, `TEMPLATE_VM_NAME` - VM configuration
- `PROXMOX_*` - Proxmox host and storage settings
- `TEMPLATE_VM_*` - VM hardware and network settings
- `KUBERNETES_*` - Kubernetes version information

### Secrets (from SOPS via environment variables)
- `PROXMOX_HOST`, `PROXMOX_USERNAME`, `PROXMOX_PASSWORD`
- `VM_USERNAME`, `VM_PASSWORD`, `VM_SSH_KEY`

## Shared Functions

The `shared/common_functions.sh` provides reusable functionality:

- `install_required_tools()` - Install jq, libguestfs-tools
- `load_environment()` - Load cpc.env and validate secrets
- `download_image()` - Download OS images
- `create_base_vm()` - Create Proxmox VM
- `expand_disk()` - Resize VM storage
- `start_vm_and_wait()` - Start VM and wait for QEMU agent
- `convert_to_template()` - Convert VM to template
- `cleanup_old_template()` - Remove existing templates
- `print_elapsed_time()` - Time tracking utilities

## OS-Specific Implementations

Each OS implementation follows a standard pattern:

1. **Pre-setup** - OS-specific preparations
2. **Configure VM** - Set VM parameters and cloud-init
3. **Wait for completion** - Monitor installation progress  
4. **Handle shutdown** - Manage VM shutdown process
5. **Final cleanup** - OS-specific cleanup tasks

### Special Handling

- **Ubuntu/Debian**: Use custom cloud-init user-data files
- **Rocky/SUSE**: Skip virt-customize due to libguestfs compatibility
- **All**: Machine-ID cleanup for proper template cloning

## Migration Status

✅ **Completed**:
- Core infrastructure and dispatcher
- Ubuntu implementation with cloud-init
- Debian implementation with cloud-init  
- Rocky Linux implementation
- SUSE implementation
- Integration with main template.sh

🔄 **In Progress**:
- Testing and validation of all OS implementations
- Documentation updates

## Troubleshooting

### Common Issues

1. **OS Detection Fails**
   - Check `IMAGE_NAME` variable contains recognizable OS identifier
   - Fallback to legacy script will be attempted

2. **Script Not Found**
   - Ensure all scripts are executable: `chmod +x *.sh`
   - Check file paths and directory structure

3. **Environment Issues**
   - Verify `cpc.env` exists and contains required variables
   - Ensure SOPS secrets are loaded via environment variables

### Debug Mode
Set `DEBUG=1` environment variable for verbose output:
```bash
DEBUG=1 ./create_template_dispatcher.sh
```

## Contributing

When adding support for a new OS:

1. Create new directory: `mkdir newos/`
2. Copy template script: `cp ubuntu/create_ubuntu_template.sh newos/create_newos_template.sh`
3. Adapt OS-specific functions
4. Create cloud-init configuration: `newos/newos-cloud-init-userdata.yaml`
5. Add OS detection logic to dispatcher
6. Create README.md with OS-specific documentation
7. Test independently and with dispatcher

## Legacy Support

The original `create_template_helper.sh` is maintained for:
- Fallback when OS-specific script is missing
- Compatibility during transition period
- Reference for migrating remaining functionality

Eventually this will be removed once all functionality is migrated and tested.
