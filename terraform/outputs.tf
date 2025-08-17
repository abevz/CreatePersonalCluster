# terraform/outputs.tf

output "cluster_summary" {
  description = "A summary of the cluster nodes with their VM_ID, hostname, and IP address."
  value = {
    # Итерируемся по local.final_nodes_map, а не по ресурсу
    for key, node_data in local.final_nodes_map : key => {
      VM_ID    = node_data.vm_id
      hostname = node_data.hostname
      IP       = node_data.static_ip_address # Теперь это поле доступно
    }
  }
}

output "ansible_inventory" {
  description = "A JSON formatted string for Ansible dynamic inventory."
  value = jsonencode({
    all = {
      hosts = [for key, node_data in local.final_nodes_map : node_data.hostname]
    },
    _meta = {
      hostvars = {
        for key, node_data in local.final_nodes_map : node_data.hostname => {
          ansible_host = node_data.static_ip_address
          ansible_user = var.vm_user
        }
      }
    },
    control_plane = {
      hosts = [for key, node_data in local.final_nodes_map : node_data.hostname if node_data.role == "c"]
    },
    workers = {
      hosts = [for key, node_data in local.final_nodes_map : node_data.hostname if node_data.role == "w"]
    }
  })
}
