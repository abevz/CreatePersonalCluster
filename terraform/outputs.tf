output "vm_ipv4_addresses" {
  description = "Primary non-loopback IPv4 addresses of the K8s VMs, attempting direct indexing."
  value = {
    for k, vm in proxmox_virtual_environment_vm.k8s : k => (
      # Attempting to use the structure vm.ipv4_addresses[1][0]
      # This assumes the second interface list (index 1) is the primary NIC
      # and its first IP (index 0) is the one we want.
      # It also checks if the IP is not loopback or IPv6 link-local.
      can(vm.ipv4_addresses[1][0]) && vm.ipv4_addresses[1][0] != "127.0.0.1" && !startswith(vm.ipv4_addresses[1][0], "fe80:") ? vm.ipv4_addresses[1][0] : null
    )
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
  value       = {
    for k, file in proxmox_virtual_environment_file.user_data_cloud_config : k => file.id
  }
}
