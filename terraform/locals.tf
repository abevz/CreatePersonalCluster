locals {
  # effective_os_type will be equal to the name of the current Tofu workspace
  effective_os_type = terraform.workspace

  # Define a map for VM template names based on the OS type (derived from workspace name)
  # This allows selecting the correct template dynamically.
  template_vm_ids = {
    "debian" = var.pm_template_debian_id
    "ubuntu" = var.pm_template_ubuntu_id
    "rocky"  = var.pm_template_rocky_id
    # Add other OS types and their corresponding template IDs as needed
  }

  # Define a map for release letters based on the OS type (derived from workspace name)
  # This helps in naming conventions, e.g., 'd' for Debian, 'u' for Ubuntu.
  release_letters_map = {
    "debian" = "d"
    "ubuntu" = "u"
    "rocky"  = "r"
    # Ensure there are entries here for all your expected workspace names
  }

  # Get the release letter for the current workspace, defaulting to "x" if not found.
  release_letter = lookup(local.release_letters_map, local.effective_os_type, "x") # "x" as a fallback

  environment = terraform.workspace # Changed from var.environment
}
