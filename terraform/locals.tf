locals {
  release_letter = lower(substr(var.os_type, 0, 1))

  # This map stores the *names* of your templates for reference
  # These should match the template names in your Proxmox environment
  clones = {
    debian = "tpl-debian-12"       # Example: Debian 12 template name
    ubuntu = "tpl-ubuntu-2404-lts" # Example: Ubuntu 24.04 LTS template name
    rocky  = "tpl-rocky-9"         # Example: Rocky 9 template name
  }

  # IMPORTANT: Replace placeholder IDs with actual VM IDs of your templates in Proxmox
  template_vm_ids = {
    debian = 902 # VM ID for template named "tpl-debian-12"
    ubuntu = 912 # Example: VM ID for template named "tpl-ubuntu-2404-lts"
    rocky  = 931 # Example: VM ID for template named "tpl-rocky-9"
  }

  # Common tags to apply to all resources, can be extended with environment-specific tags
  common_tags = {
    environment = var.environment
    managed-by  = "terraform"
  }
}
