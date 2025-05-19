output "proxmox_endpoint_console_output" {
  description = "The endpoint for the Proxmox Virtual Environment."
  value       = data.sops_file.secrets.data["virtual_environment_endpoint"]
  sensitive   = true
}

output "vm_ipv4_addresses" {
  description = "IPv4 addresses of the K8s VMs, mapped by their keys (controlplane, worker0, etc.)."
  value = {
    for k, vm in proxmox_virtual_environment_vm.k8s : k => vm.ipv4_addresses[0][0] if length(vm.ipv4_addresses) > 0 && length(vm.ipv4_addresses[0]) > 0
  }
  sensitive = false # IPs are often needed, adjust if sensitive in your context
}

output "controlplane_id" {
  description = "ID виртуальной машины controlplane"
  value       = proxmox_virtual_environment_vm.k8s["controlplane"].id
}

output "worker0_id" {
  description = "ID виртуальной машины worker0"
  value       = proxmox_virtual_environment_vm.k8s["worker0"].id
}

output "worker1_id" {
  description = "ID виртуальной машины worker1"
  value       = proxmox_virtual_environment_vm.k8s["worker1"].id
}

output "all_vm_ids" {
  description = "IDs of all created K8s VMs, mapped by their keys."
  value = {
    for k, vm in proxmox_virtual_environment_vm.k8s : k => vm.id
  }
}

output "cloud_init_file_id" {
  description = "The ID of the generated cloud-init user data file in Proxmox."
  value       = proxmox_virtual_environment_file.user_data_cloud_config.id
}
