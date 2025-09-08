# Secrets Management Guide

## Overview

CPC uses [Mozilla SOPS](https://github.com/mozilla/sops) for secure management of sensitive configuration data. This guide explains how to work with encrypted secrets in the `terraform/secrets.sops.yaml` file.

## 🔐 Security Architecture

### Encryption Method
- **Algorithm**: AES256-GCM (Authenticated Encryption)
- **Key Management**: Age encryption keys
- **Storage**: Encrypted YAML format
- **Access**: On-demand decryption during runtime

### Key Benefits
- ✅ **Zero Plaintext Exposure**: Secrets never stored in plaintext
- ✅ **Version Control Safe**: Encrypted files can be safely committed
- ✅ **Audit Trail**: Track who modified secrets and when
- ✅ **Key Rotation**: Support for encryption key rotation
- ✅ **Multi-Key Support**: Use different keys for different environments

## 📁 Secrets Structure

### Global Section
Contains credentials and settings used across all workspaces:

```yaml
global:
  vm_ssh_keys:
    - "ssh-rsa AAAAB3NzaC1yc2EAAAA..."  # SSH public key for VM access
  vm_username: "ubuntu"                    # Default VM username
  vm_password: "secure-password"           # Default VM password
  
  # Cloudflare DNS API for automated DNS management
  cloudflare_dns_api_token: "your-api-token"
  cloudflare_email: "your-email@domain.com"
  
  # Docker Hub credentials for container registry access
  docker_hub_username: "your-username"
  docker_hub_password: "your-password"
```

### Default Section
Contains infrastructure-specific configurations:

```yaml
default:
  # Proxmox VE connection settings
  proxmox:
    endpoint: "https://192.168.1.100:8006/api2/json"
    username: "root@pam"
    password: "proxmox-password"
    ssh_username: "root"
  
  # S3/MinIO backend for Terraform state storage
  s3_backend:
    bucket: "mykthw-tfstate"
    key: "proxmox/minio-vm.tfstate"
    region: "us-east-1"
    endpoint: "https://s3.minio.bevz.net"
    access_key: "minioadmin"
    secret_key: "minioadmin123"
    skip_credentials_validation: true
    skip_region_validation: true
    skip_metadata_api_check: true
    use_path_style: true
  
  # Pi-hole DNS server configuration
  pihole:
    web_password: "pihole-admin-password"
    ip_address: "192.168.1.10"
  
  # Harbor container registry settings
  harbor:
    hostname: "harbor.yourdomain.com"
    robot_username: "robot$account"
    robot_token: "robot-token-here"
```

## 🛠️ Working with Secrets

### Prerequisites

1. **Install SOPS**:
   ```bash
   # Using package manager
   sudo apt install sops
   
   # Or download binary
   curl -LO https://github.com/mozilla/sops/releases/latest/download/sops
   chmod +x sops
   sudo mv sops /usr/local/bin/
   ```

2. **Set up Age keys** (recommended):
   ```bash
   # Generate Age key pair
   age-keygen -o ~/.age/key.txt
   
   # Export public key for sharing
   age-keygen -y ~/.age/key.txt
   ```

### Basic Operations

#### View Encrypted Secrets
```bash
# Show encrypted file structure
cat terraform/secrets.sops.yaml

# Decrypt and view (requires decryption key)
sops -d terraform/secrets.sops.yaml
```

#### Edit Secrets
```bash
# Open in editor (requires decryption key)
sops terraform/secrets.sops.yaml

# Edit specific value
sops --set '["global"]["vm_username"] "newuser"' terraform/secrets.sops.yaml
```

#### Add New Secrets
```bash
# Add new section
sops --set '["newsection"]["newkey"] "newvalue"' terraform/secrets.sops.yaml
```

### Advanced Operations

#### Key Rotation
```bash
# Rotate encryption keys
sops --rotate terraform/secrets.sops.yaml
```

#### Change Encryption Keys
```bash
# Update with new Age public key
sops --add-age <new-public-key> terraform/secrets.sops.yaml
```

#### Extract Specific Values
```bash
# Get specific secret (decrypted)
sops -d terraform/secrets.sops.yaml | yq '.global.vm_username'

# Get Proxmox endpoint
sops -d terraform/secrets.sops.yaml | yq '.default.proxmox.endpoint'
```

## 🔒 Security Best Practices

### Key Management
- ✅ **Store encryption keys separately** from secrets
- ✅ **Use different keys** for different environments
- ✅ **Regular key rotation** (quarterly recommended)
- ✅ **Backup keys securely** (encrypted, offline storage)
- ✅ **Limit key access** to authorized personnel only

### Operational Security
- ✅ **Never commit decrypted secrets** to version control
- ✅ **Use strong, unique passwords** for all services
- ✅ **Regular secret rotation** for production systems
- ✅ **Audit secret access** and modifications
- ✅ **Test decryption** in staging before production

### Access Control
- ✅ **Restrict file permissions**: `chmod 600 terraform/secrets.sops.yaml`
- ✅ **Use SSH agent forwarding** for key access
- ✅ **Implement least privilege** for secret access
- ✅ **Log all decryption operations** for audit trails

## 🚨 Troubleshooting

### Common Issues

#### "Failed to decrypt secrets.sops.yaml"
```
Error: Failed to decrypt secrets.sops.yaml. Check your SOPS configuration and GPG keys.
```

**Solutions**:
1. Verify Age key is available: `age-keygen -y ~/.age/key.txt`
2. Check key permissions: `ls -la ~/.age/`
3. Ensure correct public key in SOPS config

#### "No valid credential sources found" (AWS/MinIO)
```
Error: No valid credential sources found for AWS/MinIO backend
```

**Solutions**:
1. Verify S3 credentials in secrets: `sops -d terraform/secrets.sops.yaml | yq '.default.s3_backend'`
2. Check MinIO endpoint accessibility
3. Ensure bucket exists and is accessible

#### Permission Denied
```
Error: Permission denied accessing secrets file
```

**Solutions**:
1. Fix file permissions: `chmod 600 terraform/secrets.sops.yaml`
2. Check directory permissions: `ls -ld terraform/`
3. Verify user ownership: `ls -l terraform/secrets.sops.yaml`

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Run CPC with debug output
./cpc --debug ctx

# This will show:
# - Secret loading process
# - Decryption operations
# - Key validation steps
# - Detailed error messages
```

## 📚 Related Documentation

- [Mozilla SOPS Documentation](https://github.com/mozilla/sops)
- [Age Encryption](https://github.com/FiloSottile/age)
- [CPC Configuration Guide](../README.md#🔧-configuration)
- [Project Setup Guide](project_setup_guide.md)