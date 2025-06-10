# Instructions to Complete SUSE Template Creation

The SUSE VM (ID: 941) has been successfully created and configured, but needs to be:
1. Migrated from 'local-lvm' storage to 'MyStorage' storage
2. Converted from VM to Template

## Commands to run on Proxmox server (as root or admin user):

### 1. Stop the VM (if running)
```bash
qm stop 941
```

### 2. Move disk from local-lvm to MyStorage
```bash
qm move-disk 941 virtio0 MyStorage --format qcow2
```

### 3. Convert VM to Template
```bash
qm template 941
```

### 4. Verify the template
```bash
qm config 941
```

## Current Status:
- ✅ VM 941 created with SUSE openSUSE Leap 15.6
- ✅ All packages installed and configured
- ✅ SUSE-specific package management working
- ✅ Multi-OS udev rules handling implemented
- ✅ Template VM configured with proper settings
- ⏳ **PENDING: Disk migration to MyStorage**
- ⏳ **PENDING: Conversion to template**

## After completion:
The SUSE template will be ready for use in Terraform deployments with the updated storage configuration pointing to MyStorage.

## Files Updated for MyStorage:
- cpc.env: PROXMOX_DISK_DATASTORE="MyStorage"
- cpc.env.example: PROXMOX_DISK_DATASTORE="MyStorage"  
- terraform/variables.tf: storage default = "MyStorage"
