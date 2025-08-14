output "controlplane_vm_id" {
  description = "ID of the control plane VM"
  value       = proxmox_virtual_environment_vm.node["${terraform.workspace}-controlplane-1"].vm_id
}

output "worker1_vm_id" {
  description = "ID of the worker1 VM"
  value       = proxmox_virtual_environment_vm.node["${terraform.workspace}-worker1-1"].vm_id
}

output "worker2_vm_id" {
  description = "ID of the worker2 VM"
  value       = proxmox_virtual_environment_vm.node["${terraform.workspace}-worker2-2"].vm_id
}

output "k8s_node_ips" {
  description = "IP addresses of the Kubernetes nodes"
  value = {
    for k, v in proxmox_virtual_environment_vm.node : k => (
      # Flatten the list of lists of IPs, then remove 127.0.0.1
      # Convert the resulting set to a list to allow indexing
      # If the list is not empty, take the first IP, otherwise null
      length(tolist(setsubtract(flatten(v.ipv4_addresses), ["127.0.0.1"]))) > 0 ?
      tolist(setsubtract(flatten(v.ipv4_addresses), ["127.0.0.1"]))[0] :
      null
    )
  }
}

output "k8s_node_names" {
  description = "Hostnames of the Kubernetes nodes"
  value = {
    for k, v in proxmox_virtual_environment_vm.node : k => v.name
  }
}

output "sops_data_keys_check" {
  description = "Check if specific keys exist in SOPS data (sensitive)"
  value       = sensitive({
    has_vm_ssh_keys = can(data.sops_file.secrets.data["vm_ssh_keys"])
    has_vm_password = can(data.sops_file.secrets.data["vm_password"])
    all_sops_data_keys = keys(data.sops_file.secrets.data)
  })
  sensitive = true
}

output "debug_sops_processing_info" {
  description = "Detailed debugging information for SOPS data processing in locals.tf"
  value       = local.debug_sops_info
  sensitive   = true # Mark sensitive as it might reveal structure or presence of keys
}

output "final_nodes_machine_types" {
  description = "Machine types configured for each node in final_nodes_map"
  value = {
    for k, v in local.final_nodes_map : k => v.machine
  }
}

output "debug_node_configs" {
  description = "Debug configuration for all nodes"
  value = {
    for k, v in local.final_nodes_map : k => {
      vm_id = v.vm_id
      machine_type = v.machine
      role = v.role
      clone_source = local.current_template_vm_id
      clone_node = local.clone_proxmox_node
      hostname = "${v.role}${local.release_letter}${v.index}${var.vm_domain}"
      core_count = v.cores
      socket_count = v.sockets
      memory = v.memory
    }
  }
}

output "debug_template_info" {
  description = "Debug information about templates"
  value = {
    current_workspace = terraform.workspace
    template_id = local.current_template_vm_id
    clone_node = local.clone_proxmox_node
    template_vm_ids_map = local.template_vm_ids
  }
}

output "debug_node_map_keys" {
  description = "All keys in the final_nodes_map"
  value = keys(local.final_nodes_map)
}

# Simple output with only VM_ID, node_name, and IP
output "cluster_summary" {
  description = "Simple cluster summary with VM_ID, hostname, and IP"
  value = {
    for k, v in proxmox_virtual_environment_vm.node : k => {
      VM_ID = v.vm_id
      hostname = v.name
      IP = length(tolist(setsubtract(flatten(v.ipv4_addresses), ["127.0.0.1"]))) > 0 ? tolist(setsubtract(flatten(v.ipv4_addresses), ["127.0.0.1"]))[0] : "N/A"
    }
  }
}
