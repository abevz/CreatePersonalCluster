# Root module main.tf: Defines resources and calls other modules.

# Example module calls (uncomment and configure as needed)
/*
module "network" {
  source = "./modules/network"

  environment = var.environment
  # Pass other variables required by the network module
}

module "app_service" {
  source = "./modules/app-service"

  environment = var.environment
  # Pass other variables required by the app-service module
  # Example: app_service_instance_count = var.app_service_instance_count_per_env[var.environment]
}
*/

# Cloud-init configuration file resource
resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"    # Consider making this configurable via a variable
  node_name    = var.pm_node # Using pm_node, ensure this node has the 'local' datastore for snippets

  source_raw {
    data = <<-EOF
    #cloud-config
    users:
      - default
      - name: test # Consider making username configurable
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.ssh_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    runcmd:
        - apt update
        - apt install -y qemu-guest-agent net-tools
        - timedatectl set-timezone Europe/Warszawa # Consider making timezone configurable
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
        - echo "done" > /tmp/cloud-config.done
    EOF

    file_name = "cloud-config-${var.environment}.yaml" # Unique name per environment
  }
}

# Kubernetes VM resources
resource "proxmox_virtual_environment_vm" "k8s" {
  for_each = {
    controlplane = {
      role  = "c"
      index = 1
      # Add environment-specific configurations here if needed, or pass them via variables
      # cpu_cores = var.controlplane_cpu_cores
      # memory    = var.controlplane_memory
    }
    worker0 = {
      role  = "w"
      index = 1
      # cpu_cores = var.worker_cpu_cores
      # memory    = var.worker_memory
    }
    worker1 = {
      role  = "w"
      index = 2
      # cpu_cores = var.worker_cpu_cores
      # memory    = var.worker_memory
    }
  }

  name      = "${each.value.role}${local.release_letter}${each.value.index}-${var.environment}.bevz.net" # Added environment to name
  node_name = var.pm_node

  tags = ["k8s", var.os_type, var.environment] # Added environment tag

  clone {
    vm_id = local.template_vm_ids[var.os_type]
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
    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
  }

  # started = true # To start the VM after creation, common practice.
  # Consider making 'started' configurable per environment or VM role
}


