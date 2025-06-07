# Proxmox VM Helper Guide

This document provides commands and techniques to manage VMs in Proxmox when direct SSH access is unavailable.

## VM Management Commands

### Checking VM Status

```bash
# List all VMs with their status
qm list

# Show detailed information about a specific VM
qm status <vmid>

# Show VM configuration
qm config <vmid>

# View running processes in a VM (if qemu-guest-agent is installed)
qm guest cmd <vmid> exec status -- ps aux
```

### VM Console Access

```bash
# Access VM console via noVNC
# Open in browser: https://proxmox-host:8006/#v1:0:=qemu/<vmid>:vnc:1

# Command line console access
qm terminal <vmid>
```

### VM Operations

```bash
# Start a VM
qm start <vmid>

# Stop a VM (graceful shutdown)
qm shutdown <vmid>

# Force stop a VM
qm stop <vmid>

# Restart a VM
qm reboot <vmid>

# Reset a VM (hard reset)
qm reset <vmid>

# Create a snapshot
qm snapshot <vmid> <snapshot-name> --description "Description"

# Restore a snapshot
qm rollback <vmid> <snapshot-name>

# Delete a snapshot
qm delsnapshot <vmid> <snapshot-name>
```

### VM Troubleshooting

```bash
# Execute commands in a VM using qemu-guest-agent
qm guest cmd <vmid> exec -- /bin/ls -la /home

# Get network interfaces in VM
qm guest cmd <vmid> get-networks

# Check VM resource usage
qm monitor <vmid> info balloon
qm monitor <vmid> info status

# View cloud-init logs inside a VM
qm guest cmd <vmid> exec -- cat /var/log/cloud-init.log
qm guest cmd <vmid> exec -- cat /var/log/cloud-init-output.log
```

### Cloud-Init Management

```bash
# Check cloud-init status
qm guest cmd <vmid> exec -- cloud-init status

# View cloud-init configuration
qm guest cmd <vmid> exec -- cat /etc/cloud/cloud.cfg

# Manually trigger cloud-init
qm guest cmd <vmid> exec -- cloud-init clean
qm guest cmd <vmid> exec -- cloud-init init
```

## SSH Access Troubleshooting

When having SSH access issues:

1. Check if the SSH service is running:
   ```bash
   qm guest cmd <vmid> exec -- systemctl status ssh
   ```

2. Check SSH configuration:
   ```bash
   qm guest cmd <vmid> exec -- cat /etc/ssh/sshd_config
   ```

3. Check authorized keys:
   ```bash
   qm guest cmd <vmid> exec -- cat /home/username/.ssh/authorized_keys
   ```

4. Check user existence and permissions:
   ```bash
   # List users
   qm guest cmd <vmid> exec -- cat /etc/passwd | grep <username>
   
   # Check user groups
   qm guest cmd <vmid> exec -- groups <username>
   
   # Check home directory permissions
   qm guest cmd <vmid> exec -- ls -la /home/<username>/
   ```

5. Check SSH keys directory permissions:
   ```bash
   qm guest cmd <vmid> exec -- ls -la /home/<username>/.ssh/
   ```

## Cloud-Init User Data Troubleshooting

If cloud-init isn't properly creating users or setting up SSH keys:

```bash
# Check cloud-init data sources
qm guest cmd <vmid> exec -- cat /etc/cloud/cloud.cfg.d/99_pve.cfg

# Check if cloud-init has completed successfully
qm guest cmd <vmid> exec -- cat /run/cloud-init/result.json

# Check the actual user data applied
qm guest cmd <vmid> exec -- cat /var/lib/cloud/instance/user-data.txt
```

## Network Configuration

```bash
# Check network interfaces
qm guest cmd <vmid> exec -- ip addr

# Check routing
qm guest cmd <vmid> exec -- ip route

# Check DNS resolution
qm guest cmd <vmid> exec -- cat /etc/resolv.conf

# Test network connectivity
qm guest cmd <vmid> exec -- ping -c 4 8.8.8.8
```

## Template Management

```bash
# List templates
qm list | grep template

# Clone template to create new VM
qm clone <template-vmid> <new-vmid> --name <vm-name>

# Convert VM to template
qm template <vmid>
```

## Hostname Management

### Setting Up Hostnames for New VMs

Before creating VMs with Terraform, run the hostname generation script:

```bash
# Generate node-specific cloud-init snippets with proper hostnames
cd ~/Projects/kubernetes/my-kthw/scripts
./generate_node_hostnames.sh
```

This script will:
1. Generate cloud-init snippets for each node with the correct hostname
2. Copy these snippets to your Proxmox host
3. Update the Terraform configuration to use these snippets

### Fixing Hostname Issues on Existing VMs

If you encounter VMs with incorrect hostnames (e.g., generic "ubuntu" hostname instead of the expected name), you can fix it using these commands:

```bash
# Check current hostname
ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec <vmid> -- hostname"

# Set hostname using hostnamectl
ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec <vmid> -- hostnamectl set-hostname <new-hostname>"

# Update /etc/hosts file to include the new hostname
ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec <vmid> -- bash -c \"sed -i '/127.0.1.1/d' /etc/hosts && echo '127.0.1.1 <new-hostname>' >> /etc/hosts\""

# Make cloud-init preserve hostname on next boot
ssh $PROXMOX_USERNAME@$PROXMOX_HOST "sudo qm guest exec <vmid> -- bash -c 'echo \"preserve_hostname: true\" > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg'"
```

You can use one of the following methods to fix hostname issues:

1. **Using fix_vm_hostname.sh for individual VMs**:

```bash
# Usage: fix_vm_hostname.sh <vmid> [new_hostname]
# If new_hostname is not provided, it will use the VM name from Proxmox
~/Projects/kubernetes/my-kthw/scripts/fix_vm_hostname.sh 300 my-node-name
```

2. **Using generate_node_hostnames.sh to update all VM configurations**:

```bash
# This will generate cloud-init snippets with proper hostnames for all nodes
~/Projects/kubernetes/my-kthw/scripts/generate_node_hostnames.sh

# Or use the cpc command which is integrated with the deployment process
~/Projects/kubernetes/my-kthw/cpc gen_hostnames
```

3. **Automatically during Terraform deployment**:

```bash
# The hostname generation is automatically included when you deploy
~/Projects/kubernetes/my-kthw/cpc deploy apply

# This ensures all new VMs get the proper hostname configuration
```

## VM Hostname Management

### Overview of Hostname Configuration

The project now includes a complete system for managing VM hostnames in both Ubuntu and SUSE VMs:

1. Each VM gets a proper hostname based on its role (e.g., `c` for controlplane, `w` for worker), a release letter (e.g., `u` for Ubuntu, `s` for SUSE), and an index number.
2. Hostnames include the domain (e.g., `cu1.bevz.net`).
3. The hostname is properly persisted across reboots.

### Hostname Generation Process

The VM hostname configuration works as follows:

1. The `generate_node_hostnames.sh` script:
   - Gets node information from terraform output
   - Generates per-node cloud-init snippets with hostnames
   - Uploads snippets to Proxmox
   - Is automatically run when using the `cpc apply` or `cpc plan` commands

2. Terraform/OpenTofu:
   - Uses the node-specific snippets through the `user_data_file_id` parameter

3. Cloud-init:
   - Applies the hostname configuration using multiple methods for compatibility
   - Ensures hostname persists after reboots

### Managing VM Hostnames

#### Generating hostname configuration files

```bash
# Generate or update hostname configurations
cd ~/Projects/kubernetes/my-kthw
./cpc gen_hostnames
```

#### Verifying VM Hostnames

After VMs are deployed, you can verify that hostnames are correctly set using the verify script:

```bash
cd ~/Projects/kubernetes/my-kthw/scripts
./verify_vm_hostname.sh
```

#### Fixing Hostnames on Existing VMs

If a VM has an incorrect hostname, you can fix it using:

```bash
cd ~/Projects/kubernetes/my-kthw/scripts
./fix_vm_hostname.sh <vm_id> <hostname>

# Example:
./fix_vm_hostname.sh 300 cu1.bevz.net
```

### VM Template Considerations

When creating VM templates:

1. For Ubuntu templates, ensure cloud-init config preserves hostnames:
   - Set `preserve_hostname: false` in the base template
   - The node-specific snippets will set the hostname and add `preserve_hostname: true`

2. For SUSE/OpenSUSE templates, existing configuration works correctly

## VM Disk Diagnosis and Troubleshooting

When VM is not responsive via QEMU Guest Agent (e.g., guest agent not running, network issues), you can mount the VM disk directly to diagnose problems.

### Prerequisites for Disk Mounting

```bash
# Install required tools on Proxmox host
apt update && apt install -y fdisk mount util-linux
```

### Finding VM Disk Location

```bash
# Check VM configuration to find disk location
qm config <vmid>

# For VMs using storage "MyStorage", disks are typically in:
# /DataPool/MyStorage/images/<vmid>/vm-<vmid>-disk-0.raw

# List VM disk files
ls -la /DataPool/MyStorage/images/<vmid>/
```

### Mounting VM Disk for Analysis

#### Step 1: Stop the VM

```bash
# Graceful shutdown
qm shutdown <vmid>

# Force stop if needed
qm stop <vmid> --skiplock 1
```

#### Step 2: Examine Disk Structure

```bash
# Check partition table
fdisk -l /DataPool/MyStorage/images/<vmid>/vm-<vmid>-disk-0.raw

# Example output:
# Device                                                Start      End  Sectors  Size Type
# /DataPool/MyStorage/images/9410/vm-9410-disk-0.raw1  262144 41943006 41680863 19.9G Linux root (x86-64)
# /DataPool/MyStorage/images/9410/vm-9410-disk-0.raw14   2048     8191     6144    3M BIOS boot
# /DataPool/MyStorage/images/9410/vm-9410-disk-0.raw15   8192   262143   253952  124M EFI System
```

#### Step 3: Mount the Root Partition

```bash
# Create mount point
mkdir -p /mnt/vm<vmid>

# Setup loop device with partitions
losetup -P /dev/loop3 /DataPool/MyStorage/images/<vmid>/vm-<vmid>-disk-0.raw

# Mount the root partition (usually p1)
mount /dev/loop3p1 /mnt/vm<vmid>

# Verify mount
ls -la /mnt/vm<vmid>/
```

### Analyzing VM Logs and Configuration

#### System Logs Analysis

```bash
# View systemd journal logs
journalctl --directory=/mnt/vm<vmid>/var/log/journal | grep -i 'cloud\|init\|network\|dhcp' | tail -30

# Search for specific service logs
journalctl --directory=/mnt/vm<vmid>/var/log/journal | grep -i 'qemu-guest-agent'

# Check for boot errors
journalctl --directory=/mnt/vm<vmid>/var/log/journal | grep -i 'error\|failed'

# Check network service logs
journalctl --directory=/mnt/vm<vmid>/var/log/journal | grep -i 'systemd-networkd'
```

#### Cloud-Init Troubleshooting

```bash
# Check if cloud-init directory exists
ls -la /mnt/vm<vmid>/var/lib/cloud/

# Look for cloud-init logs
find /mnt/vm<vmid>/var/log -name '*cloud*'

# Check cloud-init configuration
cat /mnt/vm<vmid>/etc/cloud/cloud.cfg | head -20

# Check cloud-init data sources
ls -la /mnt/vm<vmid>/etc/cloud/cloud.cfg.d/
```

#### Network Configuration Analysis

```bash
# Check netplan configuration
ls -la /mnt/vm<vmid>/etc/netplan/
cat /mnt/vm<vmid>/etc/netplan/*.yaml

# Check systemd-networkd configuration
ls -la /mnt/vm<vmid>/etc/systemd/network/

# Check network interfaces
cat /mnt/vm<vmid>/etc/network/interfaces

# Check resolv.conf
cat /mnt/vm<vmid>/etc/resolv.conf
```

#### Package Installation Verification

```bash
# Check if QEMU Guest Agent is installed
chroot /mnt/vm<vmid> dpkg -l | grep qemu-guest-agent

# Check if cloud-init is installed
chroot /mnt/vm<vmid> dpkg -l | grep cloud-init

# For Debian/Ubuntu - check package installation logs
cat /mnt/vm<vmid>/var/log/dpkg.log | grep qemu-guest-agent

# For Rocky/RHEL systems
chroot /mnt/vm<vmid> rpm -qa | grep qemu-guest-agent
```

#### Service Status Analysis

```bash
# Check enabled services
chroot /mnt/vm<vmid> systemctl list-unit-files | grep enabled | grep -E 'cloud|qemu|network'

# Check service configurations
cat /mnt/vm<vmid>/etc/systemd/system/multi-user.target.wants/

# Check for failed services
chroot /mnt/vm<vmid> systemctl --failed
```

### Common Issues and Fixes

#### Issue 1: QEMU Guest Agent Not Installed

```bash
# Install QEMU Guest Agent
chroot /mnt/vm<vmid> apt update
chroot /mnt/vm<vmid> apt install -y qemu-guest-agent

# Enable the service
chroot /mnt/vm<vmid> systemctl enable qemu-guest-agent
```

#### Issue 2: Network Configuration Missing

```bash
# Create basic netplan configuration
cat > /mnt/vm<vmid>/etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: true
EOF

# Set proper permissions
chmod 600 /mnt/vm<vmid>/etc/netplan/01-netcfg.yaml
```

#### Issue 3: Cloud-Init Not Configured

```bash
# Check cloud-init datasource configuration
cat /mnt/vm<vmid>/etc/cloud/cloud.cfg.d/99_pve.cfg

# If missing, create basic Proxmox datasource config
cat > /mnt/vm<vmid>/etc/cloud/cloud.cfg.d/99_pve.cfg << EOF
datasource_list: [ConfigDrive, NoCloud]
EOF
```

#### Issue 4: Machine-ID Duplication

```bash
# Clear machine-id to force regeneration
truncate -s 0 /mnt/vm<vmid>/etc/machine-id
rm -f /mnt/vm<vmid>/var/lib/dbus/machine-id
```

### Advanced Debugging Techniques

#### Check VM Hardware Detection

```bash
# Check what hardware VM detected
cat /mnt/vm<vmid>/proc/cpuinfo
cat /mnt/vm<vmid>/proc/meminfo

# Check PCI devices
chroot /mnt/vm<vmid> lspci
```

#### Modify VM Configuration

```bash
# Edit configuration files directly
nano /mnt/vm<vmid>/etc/ssh/sshd_config
nano /mnt/vm<vmid>/etc/cloud/cloud.cfg

# Add debugging to cloud-init
echo "debug: True" >> /mnt/vm<vmid>/etc/cloud/cloud.cfg.d/05_logging.cfg
```

#### Copy Files to/from VM

```bash
# Copy files to VM
cp /path/to/local/file /mnt/vm<vmid>/path/to/destination/

# Copy SSH keys
mkdir -p /mnt/vm<vmid>/home/username/.ssh/
cp ~/.ssh/id_rsa.pub /mnt/vm<vmid>/home/username/.ssh/authorized_keys
chown 1000:1000 /mnt/vm<vmid>/home/username/.ssh/authorized_keys
chmod 600 /mnt/vm<vmid>/home/username/.ssh/authorized_keys
```

### Cleanup and Unmounting

```bash
# Unmount the filesystem
umount /mnt/vm<vmid>

# Detach loop device
losetup -d /dev/loop3

# Remove mount point
rmdir /mnt/vm<vmid>

# Start VM again
qm start <vmid>
```

### Example Troubleshooting Session

Here's a complete example of diagnosing a Debian VM (ID 9410) that failed to start properly:

```bash
# 1. Stop the VM
qm stop 9410 --skiplock 1

# 2. Check disk structure
fdisk -l /DataPool/MyStorage/images/9410/vm-9410-disk-0.raw

# 3. Mount the disk
mkdir -p /mnt/vm9410
losetup -P /dev/loop3 /DataPool/MyStorage/images/9410/vm-9410-disk-0.raw
mount /dev/loop3p1 /mnt/vm9410

# 4. Check what went wrong
journalctl --directory=/mnt/vm9410/var/log/journal | grep -i 'cloud\|init\|network\|dhcp' | tail -20

# 5. Check if cloud-init ran
ls -la /mnt/vm9410/var/lib/cloud/

# 6. Check if QEMU guest agent installed
chroot /mnt/vm9410 dpkg -l | grep qemu-guest-agent

# 7. Fix issues (install missing packages, fix config)
chroot /mnt/vm9410 apt update
chroot /mnt/vm9410 apt install -y qemu-guest-agent cloud-init

# 8. Enable services
chroot /mnt/vm9410 systemctl enable qemu-guest-agent

# 9. Clean up and restart
umount /mnt/vm9410
losetup -d /dev/loop3
rmdir /mnt/vm9410
qm start 9410
```

### Disk Mounting Safety Notes

⚠️ **Important Safety Guidelines:**

1. **Always stop the VM** before mounting its disk to avoid corruption
2. **Use loop devices** with `-P` flag to properly handle partitions
3. **Be careful with chroot** operations - they modify the VM's filesystem
4. **Backup important VMs** before making significant changes
5. **Test changes** on non-production VMs first
6. **Document changes** you make for future reference

