# Dynamic creation of control plane (cp) nodes based on the selected cluster configuration
# https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm
resource "proxmox_virtual_environment_vm" "node" {
  depends_on = [proxmox_virtual_environment_pool.workspace_pool] # Updated to depend on the new pool resource
  for_each = local.final_nodes_map # Changed to use the map from locals.tf

  description  = "Managed by Terraform"
  vm_id = each.value.vm_id
  name = "${each.value.role}${local.release_letter}${each.value.index}${var.vm_domain}"
  tags = [
    "k8s",
    each.value.cluster_name,
    each.value.node_class,
  ]
  # Dynamically set node_name based on cycling through the pve_nodes array
  node_name = each.value.pve_nodes[each.value.index % length(each.value.pve_nodes)] # Proxmox host node
  clone {
    vm_id     = local.current_template_vm_id # Changed to use current_template_vm_id from locals.tf
    full      = true
    retries   = 25     # Proxmox errors with timeout when creating multiple clones at once
    node_name = local.clone_proxmox_node   # Changed to use clone_proxmox_node from locals.tf
  }
  machine = each.value.machine # Reverted to use value from locals.tf
  cpu {
    cores    = each.value.cores
    sockets  = each.value.sockets
    numa = true
    type = each.value.cpu_type
    flags = []
  }
  memory {
    dedicated = each.value.memory
  }
  dynamic "disk" {
    for_each = each.value.disks
    content {
      interface     = "virtio${index(each.value.disks, disk.value)}"
      size          = disk.value.size
      datastore_id  = disk.value.datastore_id # Corrected from 'datastore' to 'datastore_id'
      file_format   = disk.value.file_format
      backup        = disk.value.backup
      iothread      = disk.value.iothread
      cache         = disk.value.cache_mode
      aio           = disk.value.aio_mode
      discard       = disk.value.discard
      ssd           = disk.value.ssd
    }
  }
  dynamic "hostpci" {
    for_each = { for device in each.value.devices : device.mapping => device if device.type == "pci" }
    content {
      device  = "hostpci${hostpci.key}"
      mapping = hostpci.value.mapping
      pcie    = true
      mdev    = try(hostpci.value.mdev, null) != "" ? hostpci.value.mdev : null
      rombar  = hostpci.value.rombar
    }
  }
  dynamic "usb" {
    for_each = { for device in each.value.devices : device.mapping => device if device.type == "usb" }
    content {
      mapping = usb.value.mapping
      usb3    = true
    }
  }
  agent {
    enabled = true
    timeout = "15m"
    trim = true
    type = "virtio"
  }
  vga {
    memory = 16
    type = "serial0" # Changed from "qxl" to "serial0" as per example, adjust if needed
  }
  initialization {
    interface = "ide2" # For cloud-init via CD-ROM
    user_account {
      username = var.vm_user
      keys     = local.sops_vm_ssh_keys
      password = local.sops_vm_password
    }
    datastore_id = each.value.disks[0].datastore_id # datastore for cloud-init ISO

    ip_config {
      ipv4 {
        address = "dhcp" # Set to DHCP
      }
      # IPv6 configuration omitted as ipv6.enabled is false
    }

    dns {
      domain  = each.value.dns_search_domain
      servers = compact(concat(
        [each.value.ipv4.dns1],
        each.value.ipv4.dns2 != null ? [each.value.ipv4.dns2] : [], # Handle potentially null dns2
        # IPv6 DNS servers omitted as IPv6 is disabled
      ))
    }
  }
  network_device {
    vlan_id = each.value.vlan_id
    bridge  = each.value.bridge
    firewall = true
  }
  reboot              = false
  stop_on_destroy     = true
  migrate             = true
  on_boot             = each.value.on_boot
  reboot_after_update = each.value.reboot_after_update # Corrected attribute name
  started             = var.vm_started # Using existing vm_started variable
  pool_id             = proxmox_virtual_environment_pool.workspace_pool.pool_id # Updated to use the new pool ID
  lifecycle {
    ignore_changes = [
      tags,
      description,
      clone,
      machine,
      operating_system,
      hostpci,
      initialization,
      disk,
    ]
  }
}
