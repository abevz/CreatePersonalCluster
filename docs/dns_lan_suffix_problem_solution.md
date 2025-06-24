# 🔧 DNS Suffix Problem Solution (cu1.bevz.net.lan)

## 🎯 **Problem Identified:**

Your DHCP server (router/UniFi) is sending in DHCP response:
```
Option 15 (Domain Name): "lan"
```

This overrides the DNS search domain set via cloud-init in Terraform, so instead of `cu1.bevz.net` the DNS resolver tries to resolve `cu1.bevz.net.lan`.

**Confirmation:**
```bash
$ ssh abevz@cu1.bevz.net "resolvectl status | grep 'DNS Domain'"
DNS Domain: lan  # ← Here's the source of the problem!
```

## 🛠️ **Recommended Solutions:**

### **Solution 1: Switch to Static IPs (Best Option)**

Modify `terraform/nodes.tf` to use static IPs instead of DHCP:

```terraform
ip_config {
  ipv4 {
    address = "${each.value.ipv4.static_ip}/24"
    gateway = "${each.value.ipv4.gateway}"
  }
}
```

**Advantages:**
- ✅ Full control over DNS settings
- ✅ Stable IP addresses (don't change on reboot)
- ✅ No conflicts with DHCP settings

**Disadvantages:**
- ⚠️ Requires redefining IP addresses for existing VMs

### **Solution 2: Configure DHCP Server in Pi-hole (RECOMMENDED!)**

Add Pi-hole DHCP options for proper domain-search configuration:

> **Note:** Depending on your Pi-hole version, use the appropriate configuration method:
> - **Pi-hole v5.x and earlier:** Web UI or dnsmasq files
> - **Pi-hole v6.x and later:** TOML configuration (`/etc/pihole/pihole.toml`)

```bash
# In Pi-hole admin interface -> Settings -> DHCP -> Advanced DHCP settings
# Or in file /etc/dnsmasq.d/02-pihole-dhcp.conf:
dhcp-option=option:domain-search,bevz.net,bevz.dev,bevz.pl
dhcp-option=option:domain-name,bevz.net
```

**How to apply:**
1. **Via Web UI:**
   - Open Pi-hole Admin Interface
   - Go to Settings → DHCP
   - In "Advanced DHCP settings" field add:
     ```
     dhcp-option=option:domain-search,bevz.net,bevz.dev,bevz.pl
     dhcp-option=option:domain-name,bevz.net
     ```

2. **Via configuration file:**
   ```bash
   # Add to /etc/dnsmasq.d/02-pihole-dhcp.conf
   sudo nano /etc/dnsmasq.d/02-pihole-dhcp.conf
   
   # Add lines:
   dhcp-option=option:domain-search,bevz.net,bevz.dev,bevz.pl
   dhcp-option=option:domain-name,bevz.net
   
   # Restart Pi-hole
   sudo systemctl restart pihole-FTL
   ```

3. **For Pi-hole v6+ (TOML configuration):**
   ```bash
   # Edit /etc/pihole/pihole.toml
   sudo nano /etc/pihole/pihole.toml
   
   # Add/modify sections:
   [dns]
   domain = ""
   
   [misc]
   dnsmasq_lines = [
       "dhcp-option=option:domain-search,bevz.net,bevz.dev,bevz.pl"
   ] ### CHANGED, default = []
   
   # Restart Pi-hole
   sudo systemctl restart pihole-FTL
   ```
   
   **TOML Configuration Explanation:**
   - `[dns] domain = ""` - disables automatic domain suffix addition
   - `dnsmasq_lines` - passes options directly to dnsmasq for precise DHCP control
   - `option:domain-search` - defines list of domains for DNS search

**Advantages:**
- ✅ Fixes the problem for all devices on the network
- ✅ No changes required in Terraform
- ✅ Centralized DNS domain management
- ✅ Support for multiple domains (bevz.net, bevz.dev, bevz.pl)

**Disadvantages:**
- ⚠️ Requires access to Pi-hole configuration
- ⚠️ Affects all devices on the network (but this is usually desired behavior)

### **Solution 3: Force DNS Reconfiguration on VMs**

Add forced DNS reconfiguration to cloud-init script:

```yaml
runcmd:
  - resolvectl domain eth0 bevz.net
  - resolvectl flush-caches
```

**Advantages:**
- ✅ Quickly fixes existing VMs
- ✅ Minimal changes to Terraform

**Disadvantages:**
- ⚠️ Requires manual addition to cloud-init
- ⚠️ May be overridden by DHCP renewal

## 🎯 **Recommendation:**

**Use Solution 2 (Pi-hole DHCP configuration)** - this is the most simple and effective approach that solves the problem centrally for all devices.

**Why this is the best option:**
- 🎯 Fixes the problem at the source (DHCP server)
- 🌐 Works for all devices on the network
- 🔧 No changes required in Terraform/cloud-init
- 📊 Supports multiple domains for different projects

## 📋 **Implementation Plan (Recommended - Pi-hole DHCP):**

### **Step 1: Configure Pi-hole DHCP Options**
```bash
# Method 1: Via Web UI
# 1. Open http://pi-hole-ip/admin
# 2. Settings → DHCP → Advanced DHCP settings
# 3. Add:
dhcp-option=option:domain-search,bevz.net,bevz.dev,bevz.pl
dhcp-option=option:domain-name,bevz.net

# Method 2: Via configuration file
sudo nano /etc/dnsmasq.d/02-pihole-dhcp.conf
# Add the lines above and restart:
sudo systemctl restart pihole-FTL
```

### **Step 2: Update Existing Clients**
```bash
# Force DHCP lease renewal on VMs:
ssh abevz@cu1.bevz.net "sudo dhclient -r && sudo dhclient"
ssh abevz@wu1.bevz.net "sudo dhclient -r && sudo dhclient" 
ssh abevz@wu2.bevz.net "sudo dhclient -r && sudo dhclient"
```

### **Step 3: Verify Results**
```bash
# Check DNS configuration:
ssh abevz@cu1.bevz.net "resolvectl status | grep 'DNS Domain'"
# Expected: DNS Domain: bevz.net

# Check Pi-hole logs:
tail -f /var/log/pihole.log | grep cu1.bevz.net
# Should not see .lan or double domains
```

### **Alternative Plan (Static IPs):**

If you prefer to have full control over networking and avoid DHCP dependencies:

1. **Update Terraform configuration** in `terraform/nodes.tf`:
   ```terraform
   # Replace DHCP configuration with static IPs
   ip_config {
     ipv4 {
       address = "${each.value.ipv4.static_ip}/24"
       gateway = "${each.value.ipv4.gateway}"
     }
   }
   ```

2. **Define static IP mappings** in `terraform/locals.tf`:
   ```terraform
   locals {
     nodes = {
       cu1 = {
         ipv4 = {
           static_ip = "192.168.1.10"
           gateway   = "192.168.1.1"
         }
       }
       wu1 = {
         ipv4 = {
           static_ip = "192.168.1.11"
           gateway   = "192.168.1.1"
         }
       }
       wu2 = {
         ipv4 = {
           static_ip = "192.168.1.12"
           gateway   = "192.168.1.1"
         }
       }
     }
   }
   ```

3. **Apply changes**:
   ```bash
   terraform plan
   terraform apply
   ```

## 🎯 **Summary**

The DNS suffix problem (`.lan`, `.bevz.net.bevz.net`) is caused by DHCP server configuration that overrides VM DNS settings. The recommended solution is to configure Pi-hole DHCP options properly using the appropriate method for your Pi-hole version:

- **Pi-hole v5.x**: Web UI or dnsmasq configuration files
- **Pi-hole v6.x**: TOML configuration in `/etc/pihole/pihole.toml`

This approach provides centralized DNS management and resolves the issue for all network devices without requiring changes to individual VMs or Terraform configurations.
