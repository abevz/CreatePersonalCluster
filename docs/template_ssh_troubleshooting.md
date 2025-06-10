# VM Template SSH and QEMU Guest Agent Troubleshooting Guide

This document provides guidance on fixing common issues related to SSH access and QEMU guest agent in VM templates.

## Common Issues and Solutions

### Issue 1: SSH Service Not Starting Properly

**Symptoms:**
- Cannot SSH into the VM even though it has an IP address
- QEMU guest agent is working, but SSH connections time out

**Solutions:**

1. **Check SSH service status through the VM console or QEMU guest agent:**
   ```bash
   # Using QEMU guest agent to check SSH status
   qm guest cmd <vmid> exec -- systemctl status ssh
   
   # Check if SSH is listening on port 22
   qm guest cmd <vmid> exec -- netstat -tuln | grep ":22"
   ```

2. **Fix SSH service:**
   ```bash
   # Start SSH service
   qm guest cmd <vmid> exec -- systemctl restart ssh
   
   # Generate SSH host keys if missing
   qm guest cmd <vmid> exec -- ssh-keygen -A
   
   # Restart SSH after key generation
   qm guest cmd <vmid> exec -- systemctl restart ssh
   ```

3. **Fix SSH configuration:**
   ```bash
   # Enable password authentication
   qm guest cmd <vmid> exec -- bash -c 'echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config'
   
   # Allow root login if needed for debugging
   qm guest cmd <vmid> exec -- bash -c 'echo "PermitRootLogin yes" >> /etc/ssh/sshd_config'
   
   # Restart SSH to apply changes
   qm guest cmd <vmid> exec -- systemctl restart ssh
   ```

### Issue 2: QEMU Guest Agent Not Working

**Symptoms:**
- Cannot execute commands through `qm guest cmd`
- VM shows as running but no IP address is visible

**Solutions:**

1. **Check if QEMU guest agent is installed and running:**
   ```bash
   # Through VM console, check QEMU guest agent status
   systemctl status qemu-guest-agent
   
   # Ensure the package is installed
   dpkg -l | grep qemu-guest-agent
   ```

2. **Fix QEMU guest agent:**
   ```bash
   # Install the package if missing
   apt update && apt install -y qemu-guest-agent
   
   # Create systemd override configuration
   mkdir -p /etc/systemd/system/qemu-guest-agent.service.d/
   
   # Create override file
   cat > /etc/systemd/system/qemu-guest-agent.service.d/override.conf << EOF
   [Unit]
   After=network-online.target
   Wants=network-online.target
   
   [Service]
   Restart=always
   RestartSec=10
   TimeoutStartSec=60
   EOF
   
   # Reload systemd and restart agent
   systemctl daemon-reload
   systemctl restart qemu-guest-agent
   ```

### Issue 3: Networking Not Starting Correctly

**Symptoms:**
- VM has no IP address
- Cannot reach the network from within the VM

**Solutions:**

1. **Check network configuration:**
   ```bash
   # Check interfaces
   ip addr
   
   # Check routing
   ip route
   ```

2. **Fix networking using netplan (Ubuntu/Debian):**
   ```bash
   # Create simple netplan configuration
   cat > /etc/netplan/01-netcfg.yaml << EOF
   network:
     version: 2
     ethernets:
       ens18:
         dhcp4: true
   EOF
   
   # Apply configuration
   netplan apply
   ```

3. **Fix networking for ifupdown (Debian):**
   ```bash
   # Create network configuration
   cat > /etc/network/interfaces << EOF
   auto lo
   iface lo inet loopback
   
   auto ens18
   iface ens18 inet dhcp
   EOF
   
   # Restart networking
   ifdown -a && ifup -a
   ```

### Issue 4: User SSH Access Issues

**Symptoms:**
- Cannot SSH with specific user even though SSH service is running
- Authentication failures

**Solutions:**

1. **Check user account and home directory:**
   ```bash
   # Verify user exists
   id <username>
   
   # Check SSH directory permissions
   ls -la /home/<username>/.ssh/
   ```

2. **Fix user SSH directory permissions:**
   ```bash
   # Create .ssh directory if missing
   mkdir -p /home/<username>/.ssh
   
   # Set correct owner and permissions
   chown -R <username>:<username> /home/<username>/.ssh
   chmod 700 /home/<username>/.ssh
   ```

3. **Add SSH key for user:**
   ```bash
   # Add public key to authorized_keys
   echo "ssh-rsa AAAA..." > /home/<username>/.ssh/authorized_keys
   
   # Set correct permissions
   chmod 600 /home/<username>/.ssh/authorized_keys
   chown <username>:<username> /home/<username>/.ssh/authorized_keys
   ```

## Preventing Issues in Template Creation

To prevent these issues when creating new templates, make the following changes to your template creation process:

1. **Ensure proper service ordering in cloud-init:**
   - Add `network-online.target` as a dependency for QEMU guest agent
   - Start SSH service explicitly in cloud-init

2. **Include network verification script:**
   - Add a script that checks network connectivity
   - Verify that critical services are running

3. **Add robust SSH configuration:**
   - Generate SSH host keys during template creation
   - Set appropriate SSH configuration options
   - Ensure SSH is enabled to start at boot

These changes have been implemented in the latest template creation process and fixed in the Debian VM template.

## Using the Template without Unnecessary Downloads

To avoid downloading the base image again when you already have a valid local copy, set the `FORCE_DOWNLOAD=0` environment variable:

```bash
# Create a template without forcing download
FORCE_DOWNLOAD=0 ./cpc create_template debian
```

If you want to force a fresh download of the base image:

```bash
# Force downloading a fresh copy of the base image
FORCE_DOWNLOAD=1 ./cpc create_template debian
```

## Verifying SSH Access on New VMs

After creating a VM from the template, verify SSH access:

```bash
# Check VM's IP address
qm guest cmd <vmid> get-networks

# Try SSH access
ssh <username>@<vm-ip>

# If SSH access fails, check service status
qm guest cmd <vmid> exec -- systemctl status ssh
```

## Template Testing Checklist

Before finalizing a template, verify:

1. ☐ QEMU guest agent starts properly and reports VM IP address
2. ☐ SSH service starts properly and accepts connections
3. ☐ User accounts have correct SSH keys and permissions
4. ☐ Template imports without repeated image downloads 
5. ☐ Cloud-init runs successfully with custom user-data
