output "controlplane_vm_id" {
  value       = proxmox_vm_kvm.controlplane[0].id
  description = "Control plane VM ID"
}

output "worker0_vm_id" {
  value       = proxmox_vm_kvm.workers[0].id
  description = "Worker0 VM ID"
}

output "worker1_vm_id" {
  value       = proxmox_vm_kvm.workers[1].id
  description = "Worker1 VM ID"
}

output "vm_ipv4_addresses" {
  description = "A map of VM names to their primary IPv4 addresses."
  value = {
    for k, vm in proxmox_virtual_environment_vm.k8s : k => try(
      [
        for ip_addr in flatten(vm.ipv4_addresses) : ip_addr
        if ip_addr != null &&
           ip_addr != "127.0.0.1" && # Exclude localhost
           !startswith(ip_addr, "169.254.") && # Exclude link-local/APIPA
           !startswith(ip_addr, "fe80:") # Exclude IPv6 link-local (defensive)
      ][0], # Attempt to get the first valid IP
      null  # Return null if no valid IP is found or list is empty
    )
  }
  # If a VM is stopped, its IP addresses are not available.
  # The output should reflect this, e.g., by returning null or an empty string for that VM.
  # This helps prevent errors in consuming modules or scripts.
  # Ensure this output is resilient to VMs being in a stopped state.
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

output "vm_fqdns" {
  description = "FQDNs of the K8s VMs, mapped by their keys."
  value = {
    for k, vm_config in local.k8s_nodes : k => "${vm_config.role}${local.release_letter}${vm_config.index}${var.vm_domain}"
  }
}
