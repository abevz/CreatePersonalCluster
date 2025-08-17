# terraform/outputs.tf

# Output для команды cpc cluster-info
output "cluster_summary" {
  description = "A summary of the cluster nodes with their VM_ID, hostname, and IP address."
  value = {
    for key, node in proxmox_virtual_environment_vm.node : key => {
      VM_ID    = node.vm_id
      hostname = node.name
      # --- ИСПРАВЛЕНО ЗДЕСЬ ---
      # Берём первый IP из первого сетевого интерфейса
      IP       = length(node.ipv4_addresses) > 0 ? node.ipv4_addresses[0][0] : "N/A"
    }
  }
}

# Output, который напрямую генерирует JSON для Ansible Inventory
output "ansible_inventory" {
  description = "A JSON formatted string for Ansible dynamic inventory."
  value = jsonencode({
    all = {
      hosts = [for node in proxmox_virtual_environment_vm.node : node.name]
    },
    _meta = {
      hostvars = {
        for node in proxmox_virtual_environment_vm.node : node.name => {
          # --- И ИСПРАВЛЕНО ЗДЕСЬ ---
          ansible_host = length(node.ipv4_addresses) > 0 ? node.ipv4_addresses[0][0] : null
          ansible_user = var.vm_user
        }
      }
    },
    control_plane = {
      hosts = [for key, node in proxmox_virtual_environment_vm.node : node.name if contains(node.tags, "controlplane-1")]
    },
    workers = {
      hosts = [for key, node in proxmox_virtual_environment_vm.node : node.name if substr(key, length("${terraform.workspace}-"), 6) == "worker"]
    }
  })
}
