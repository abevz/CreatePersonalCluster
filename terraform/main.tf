# Root module main.tf: Defines resources and calls other modules.

# Example module calls (uncomment and configure as needed)
/*
module "network" {
  source = "./modules/network"

  # environment = var.environment # This var was removed, if modules are used, this needs update
  # Pass other variables required by the network module
}

module "app_service" {
  source = "./modules/app-service"

  # environment = var.environment # This var was removed, if modules are used, this needs update
  # Pass other variables required by the app-service module
  # Example: app_service_instance_count = var.app_service_instance_count_per_env[var.environment]
}
*/

# Using locals to define the node map to avoid duplication
locals {
  k8s_nodes = {
    controlplane = { role  = "c", index = 1 }
    worker0      = { role  = "w", index = 1 }
    worker1      = { role  = "w", index = 2 }
    # If you change the map for VMs, update it here
  }
}

# Resource to track changes in cloud-init content
resource "terraform_data" "cloud_init_content" {
  for_each = local.k8s_nodes

  input = <<-EOF
    #cloud-config
    # Set the fully qualified domain name
    fqdn: ${each.value.role}${local.release_letter}${each.value.index}${var.vm_domain}
    manage_etc_hosts: true
    users:
      - default
      - name: ${var.vm_user}
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.ssh_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    # Use cloud-init's built-in package management
    # This is more portable across different Linux distributions
    package_update: true
    packages:
      - qemu-guest-agent
      - net-tools # Useful for manual IP checks, not strictly required by the agent
    runcmd:
      # Ensure timezone is set
      - timedatectl set-timezone Europe/Warszawa
      # Enable and start the qemu-guest-agent using systemctl
      # The 'packages' directive should have installed it by this point.
      # '--now' enables and starts the service immediately.
      - systemctl enable --now qemu-guest-agent
      # Final marker to indicate runcmd completion
      - echo "cloud-init runcmd finished successfully" > /tmp/cloud-init-runcmd.done
  EOF
}

# Cloud-init configuration file resource
resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  for_each = local.k8s_nodes # Using the same map as for VMs

  content_type = "snippets"
  datastore_id = "local"    # Consider making this configurable via a variable
  node_name    = var.pm_node # Using pm_node, ensure this node has the 'local' datastore for snippets

  source_raw {
    # Taking data from terraform_data to ensure dependency
    data      = terraform_data.cloud_init_content[each.key].input
    # Filename now includes a content hash to ensure uniqueness upon changes
    file_name = "cloud-config-${terraform.workspace}-${each.key}-${substr(sha256(terraform_data.cloud_init_content[each.key].input), 0, 8)}.yaml"
  }
}

# Kubernetes VM resources
resource "proxmox_virtual_environment_vm" "k8s" {
  for_each = local.k8s_nodes # Using the map from locals

  name      = "${each.value.role}${local.release_letter}${each.value.index}${var.vm_domain}" # VM name now uses local.release_letter, which depends on the workspace
  node_name = var.pm_node

  tags = ["k8s", local.effective_os_type] # Removed terraform.workspace to avoid duplication

  clone {
    vm_id = local.template_vm_ids[local.effective_os_type] # Template ID now depends on the workspace
    full  = true // Ensures a full clone.
  }

  agent {
    enabled = true
  }

  cpu {
    cores   = var.vm_cpu_cores # Using variable
    sockets = 1
    type    = "kvm64"
  }

  memory {
    dedicated = var.vm_memory_dedicated # Using variable
  }

  disk {
    datastore_id = "MyStorage" # Consider making this configurable
    interface    = "scsi0"
    size         = var.vm_disk_size # Using variable
  }

  initialization {
    dns {
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config[each.key].id # Link to the specific cloud-init file
  }

  started = var.vm_started # Control VM state (running/stopped)
  timeout_start_vm = 600 # Example: 600 seconds (10 minutes)

  # Consider making \'started\' configurable per environment or VM role
}


