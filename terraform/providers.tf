provider "sops" {
  # Configuration for SOPS provider, if any specific settings are needed.
}

provider "proxmox" {
  endpoint = data.sops_file.secrets.data["virtual_environment_endpoint"]
  password = data.sops_file.secrets.data["virtual_environment_password"]
  username = data.sops_file.secrets.data["virtual_environment_username"]
  insecure = true # Consider setting to false in production with a valid certificate

  ssh {
    agent    = true      # Assumes SSH agent forwarding is configured and an agent is running
    username = "terraform" # Ensure this user exists on Proxmox with necessary permissions
  }
}
