# SSH Key Authentication Troubleshooting Guide

This document provides guidance on fixing SSH key authentication issues in VM templates and instances.

## Common Issues

### 1. Permission denied (publickey) errors

This error typically indicates that SSH key authentication failed. This could be due to:

- Missing or invalid public key in `authorized_keys` file
- Incorrect permissions on SSH files and directories
- SSH configuration not allowing key authentication
- SSH service misconfiguration
- Conflicting SSH configuration (multiple settings for the same option)
- IP address parsing issues in verification scripts
- **User account doesn't exist** despite having a home directory and .ssh folder
- **Character encoding issues** causing "invalid user: â" or similar errors

## Diagnostic Steps

### 1. Run the SSH key verification script

```bash
# For a local VM
/usr/local/bin/verify_ssh_keys.sh [username]

# Using QEMU guest agent for a VM template
qm guest cmd <vmid> exec -- /usr/local/bin/verify_ssh_keys.sh <username>
```

### 2. Check file permissions

SSH requires strict permissions on key files and directories:

```bash
# Directory permissions
chmod 700 ~/.ssh
chown <user>:<user> ~/.ssh

# Key file permissions
chmod 600 ~/.ssh/authorized_keys
chown <user>:<user> ~/.ssh/authorized_keys
```

### 3. Verify SSH configuration

```bash
# Check SSH config for proper settings
grep -E "^(PubkeyAuthentication|PasswordAuthentication|AuthorizedKeysFile)" /etc/ssh/sshd_config

# Ensure these are properly set
# PubkeyAuthentication yes
# PasswordAuthentication yes (for fallback)
# AuthorizedKeysFile .ssh/authorized_keys
```

### 4. Verify authorized_keys content

```bash
# Check if public key is properly formatted in authorized_keys
cat ~/.ssh/authorized_keys
```

## Comprehensive Fix

### User Account Issues

One important issue we discovered is that sometimes the cloud-init process creates SSH directories but fails to create the actual user account. In this case, you'll see:

- SSH service is running
- Home directory and `.ssh` folder exist 
- SSH key is present in `authorized_keys` file
- But SSH fails with "Invalid user" messages in logs

To fix this issue, we've created several scripts:

### 1. User Verification Script

```bash
# Verify and fix user accounts
/usr/local/bin/verify_user.sh <username>
```

This script:
1. Checks if the user actually exists in `/etc/passwd`
2. Creates the user if it exists in the filesystem but not in the user database
3. Properly sets ownership of home directory and SSH files
4. Adds the user to the sudo group
5. Sets a temporary password for fallback access

### 2. Encoding Issues Fix Script

```bash
# Fix character encoding issues in SSH
/home/abevz/Projects/kubernetes/my-kthw/scripts/vm_template/fix_encoding_ssh_issue.sh <vmid> <username>
```

This script:
1. Detects and fixes corruption in character encoding that causes "invalid user" errors
2. Creates a properly encoded user account if it doesn't exist
3. Fixes all permissions and SSH configurations
4. Adds authorized keys with proper encoding
5. Validates SSH access

### 3. SSH Fix Script

```bash
# Run the SSH fix script
/usr/local/bin/fix_ssh_access.sh
```

This script:
1. Ensures SSH server is installed
2. Enables and starts SSH service
3. Generates SSH host keys if missing
4. Fixes common SSH configuration issues
5. Verifies SSH is listening on port 22
6. Fixes permissions on SSH directories and keys
7. Logs everything to `/var/log/fix_ssh_access.log`

## Cloud-init Configuration

Our improved cloud-init configuration:

1. Creates user with proper SSH key setup
2. Ensures home directory exists with proper permissions
3. Sets proper permissions on SSH files
4. Executes verification scripts after setup
5. Provides fallback password authentication

## Manual Debugging from Proxmox Host

```bash
# Access VM shell via console
qm terminal <vmid>

# Check SSH service status
systemctl status sshd

# View SSH logs 
journalctl -u sshd

# Test SSH configuration
sshd -T

# Check if public key matches your client
cat ~/.ssh/authorized_keys

# Check if user actually exists in the system
grep "<username>" /etc/passwd

# Create user if it doesn't exist
useradd -m -s /bin/bash <username>

# Verify SSH logs for authentication failures
tail -f /var/log/auth.log
```

## Emergency SSH Key Injection

If all else fails, you can use our emergency SSH key injection script:

```bash
# Run the script directly from Proxmox host
./fix_ssh_key_injection.sh <vmid> <username>
```

This script:

1. Verifies the VM is running with responsive QEMU guest agent
2. Checks if the specified user exists in the VM
3. **Creates the user if it doesn't exist** (new feature)
4. Creates SSH directory with proper permissions if needed
5. Injects your SSH public key into the user's authorized_keys file
6. Fixes any conflicting SSH configuration settings
7. Tests the SSH connection
8. Runs comprehensive diagnostics if connection fails

### Handling Conflicting SSH Configurations

If you see both `PasswordAuthentication yes` and `PasswordAuthentication no` in your SSH configuration:

```bash
# Remove all conflicting lines and set desired values
sudo sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config
sudo sed -i '/^PubkeyAuthentication/d' /etc/ssh/sshd_config
echo "PasswordAuthentication yes" | sudo tee -a /etc/ssh/sshd_config
echo "PubkeyAuthentication yes" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart ssh
```

## References

- [OpenSSH Documentation](https://www.openssh.com/manual.html)
- [SSH Key Authentication Guide](https://www.ssh.com/academy/ssh/public-key-authentication)
