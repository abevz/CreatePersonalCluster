locals {
  # effective_os_type will be equal to the name of the current Tofu workspace
  effective_os_type = terraform.workspace

  # Define a map for VM template names based on the OS type (derived from workspace name)
  # This allows selecting the correct template dynamically.
  template_vm_ids = {
    "k8s133" = var.pm_template_ubuntu_id  # Auto-added by clone-workspace
    "k8s129" = var.pm_template_ubuntu_id  # Auto-added by clone-workspace
    "debian"        = var.pm_template_debian_id
    "ubuntu"        = var.pm_template_ubuntu_id
    "rocky"         = var.pm_template_rocky_id
    "suse"          = var.pm_template_suse_id
    "test-workspace" = var.pm_template_ubuntu_id  # Use Ubuntu template for test-workspace
    # Add other OS types and their corresponding template IDs as needed
  }

  # Define a map for release letters based on the OS type (derived from workspace name)
  # This helps in naming conventions, e.g., 'd' for Debian, 'u' for Ubuntu.
  release_letters_map = {
    "k8s133" = "j"  # Auto-added by clone-workspace
    "k8s129" = "k"  # Auto-added by clone-workspace
    "debian"        = "d"
    "ubuntu"        = "u"
    "rocky"         = "r"
    "suse"          = "s"
    "test-workspace" = "t"   # Use 't' for test-workspace
    # Ensure there are entries here for all your expected workspace names
  }

  # Get the release letter for the current workspace
  # 1. Use var.release_letter if it's set (from environment RELEASE_LETTER)
  # 2. Otherwise, fall back to the map with the workspace name
  # 3. If that fails too, use "x" as a fallback
  release_letter = var.release_letter != "" ? var.release_letter : lookup(local.release_letters_map, local.effective_os_type, "x")

  environment = terraform.workspace # Changed from var.environment

  # VM ID ranges per OS type
  vm_id_ranges = {
    "k8s133" = 610  # Auto-added by clone-workspace
    "k8s129" = 700  # Auto-added by clone-workspace
    "debian"        = 200
    "ubuntu"        = 300
    "rocky"         = 400
    "suse"          = 500
    "test-workspace" = 600  # Fixed: Use 600 range instead of full VM ID
  }

  # Base configuration for node types, replacing old local.k8s_nodes
  node_definitions = {
    controlplane = { role = "c", id_offset = 0, original_index = 1 }
    worker0      = { role = "w", id_offset = 1, original_index = 1 }
    worker1      = { role = "w", id_offset = 2, original_index = 2 }
  }

  # Map of nodes for the current OS type, to be used by nodes.tf for_each
  final_nodes_map = {
    for node_key, definition in local.node_definitions :
    # Constructing a key like "debian-controlplane-1"
    "${local.effective_os_type}-${node_key}-${definition.original_index}" => {
      cluster_name      = local.effective_os_type # Used in nodes.tf example key pattern
      node_class        = node_key                # Used in nodes.tf example key pattern
      index             = definition.original_index # Used in nodes.tf example key pattern & cloud-init

      vm_id             = local.vm_id_ranges[local.effective_os_type] + definition.id_offset
      role              = definition.role # For cloud-init fqdn

      pve_nodes         = [var.pm_node]
      machine           = null # Set to null to use Proxmox default
      cores             = var.vm_cpu_cores
      sockets           = 1
      cpu_type          = "kvm64"
      memory            = var.vm_memory_dedicated
      disks = [
        {
          size         = var.vm_disk_size
          datastore_id = "MyStorage"
          file_format  = "raw"
          backup       = true
          iothread     = true
          cache_mode   = "none"
          aio_mode     = "io_uring"
          discard      = "ignore"
          ssd          = false
          # interface is handled by nodes.tf dynamic disk block
        }
      ]
      devices           = []
      # ipv4 and ipv6 structures are for nodes.tf's initialization block if it were to handle static IPs.
      # Since we're aiming for DHCP via cloud-init's user_data, these are mostly for reference by nodes.tf's dns block.
      ipv4 = {
        # address = "dhcp" will be set in initialization.ip_config directly
        dns1    = var.dns_servers[0]
        dns2    = length(var.dns_servers) > 1 ? var.dns_servers[1] : null
      }
      ipv6 = {
        enabled = false
      }
      dns_search_domain = trimprefix(var.vm_domain, ".") # For nodes.tf's initialization.dns block
      vlan_id           = null                            # For nodes.tf's network_device block
      bridge            = var.network_bridge              # For nodes.tf's network_device block
      on_boot           = false                           # For nodes.tf direct attribute
      reboot_after_update = false                       # For nodes.tf direct attribute
    }
  }

  # Template ID for the current OS, used in nodes.tf clone block
  current_template_vm_id = local.template_vm_ids[local.effective_os_type]

  # Proxmox node for cloning, used in nodes.tf clone block
  clone_proxmox_node = var.pm_node

  # SOPS Data Extraction and Debugging
  sops_data = data.sops_file.secrets.data

  # Safely retrieve SSH keys.
  # 1. Lookup vm_ssh_keys, default to null if not found or if type mismatch with a specific default.
  actual_sops_ssh_keys_from_lookup = lookup(local.sops_data, "vm_ssh_keys", null)

  # 2. Process the retrieved value to ensure it's a list.
  # If null (missing/actually null), default to [].
  # If it's a list, use as is. If it's a scalar (e.g. string), wrap it in a list.
  processed_sops_ssh_keys = local.actual_sops_ssh_keys_from_lookup == null ? [] : (
    try(tolist(local.actual_sops_ssh_keys_from_lookup), [local.actual_sops_ssh_keys_from_lookup])
  )
  sops_vm_ssh_keys = sensitive(local.processed_sops_ssh_keys)

  # Safely retrieve VM password.
  actual_sops_password_from_lookup = lookup(local.sops_data, "vm_password", null) # Default to null
  # Ensure it's a string, default to empty string if null
  processed_sops_password = local.actual_sops_password_from_lookup == null ? "" : tostring(local.actual_sops_password_from_lookup)
  sops_vm_password = sensitive(local.processed_sops_password)

  # Debugging information
  debug_sops_info = {
    # Check if the key "vm_ssh_keys" exists AND its value is null
    ssh_key_was_present_and_explicitly_null = contains(keys(local.sops_data), "vm_ssh_keys") && (lookup(local.sops_data, "vm_ssh_keys", "sentinel_if_missing") == null)
    
    # Check if the key "vm_password" exists AND its value is null
    password_was_present_and_explicitly_null  = contains(keys(local.sops_data), "vm_password") && (lookup(local.sops_data, "vm_password", "sentinel_if_missing") == null)
    
    all_keys_in_sops_data  = keys(local.sops_data)
    
    # For diagnostics: show the processed keys before marking sensitive (will appear in plan if not sensitive)
    # This is for temporary debugging, normally you wouldn't output raw secret material.
    # For real debugging, you might temporarily output this without 'sensitive()' wrapper if plan keeps failing.
    # type_of_actual_ssh_keys = type(local.actual_sops_ssh_keys_from_lookup) 
    # type_of_processed_ssh_keys = type(local.processed_sops_ssh_keys)
  }
}
