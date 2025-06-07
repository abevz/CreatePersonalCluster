# Testing the VM Hostname Configuration

This guide outlines the steps to test the VM hostname configuration for Ubuntu VMs.

## Prerequisites

- Proxmox server is running and accessible
- Access to Terraform/OpenTofu configuration in the `my-kthw` project

## Step 1: Verify Generated Hostname Configuration Files

```bash
# Generate the hostname configuration files
cd ~/Projects/kubernetes/my-kthw
./cpc gen_hostnames

# Check the generated files
ls -la terraform/snippets/
cat terraform/snippets/node-c1-userdata.yaml
```

You should see files named like `node-c1-userdata.yaml`, `node-w1-userdata.yaml`, etc., containing the correct hostname configuration.

## Step 2: Apply the Terraform Configuration

```bash
# Apply the Terraform configuration
cd ~/Projects/kubernetes/my-kthw
./cpc apply
```

This will recreate the VMs with the new hostname configuration.

## Step 3: Verify VM Hostnames

After the VMs are created and have booted, verify the hostnames:

```bash
# Verify the hostnames
cd ~/Projects/kubernetes/my-kthw/scripts
./verify_vm_hostname.sh
```

The script will connect to each VM and verify that the hostname is set correctly.

## Troubleshooting

If a VM has an incorrect hostname, you can fix it using:

```bash
# Fix hostname on a specific VM
cd ~/Projects/kubernetes/my-kthw/scripts
./fix_vm_hostname.sh <vm_id> <hostname>
```

## Expected Results

- Ubuntu VMs should have hostnames like `cu1.bevz.net` rather than the generic `ubuntu`
- The hostnames should persist across reboots
- Both `/etc/hostname` and `hostnamectl` should show the correct hostname

## Advanced Testing

To verify that the hostname persists across reboots:

1. Connect to a VM:
   ```bash
   ssh <username>@<vm_ip>
   ```

2. Reboot the VM:
   ```bash
   sudo reboot
   ```

3. After the VM has rebooted, reconnect and check the hostname:
   ```bash
   ssh <username>@<vm_ip>
   hostname
   ```

The hostname should remain the same after reboot.
