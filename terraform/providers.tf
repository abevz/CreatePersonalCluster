provider "sops" {
  # Configuration for SOPS provider, if any specific settings are needed.
}

provider "aws" {
  region     = data.sops_file.secrets.data["default.s3_backend.region"]
  access_key = data.sops_file.secrets.data["default.s3_backend.access_key"]
  secret_key = data.sops_file.secrets.data["default.s3_backend.secret_key"]

  # MinIO specific configuration
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_metadata_api_check     = true

  endpoints {
    s3 = data.sops_file.secrets.data["default.s3_backend.endpoint"]
  }
}

provider "proxmox" {
  endpoint = data.sops_file.secrets.data["default.proxmox.endpoint"]
  password = data.sops_file.secrets.data["default.proxmox.password"]
  username = data.sops_file.secrets.data["default.proxmox.username"]

  insecure = true # Consider setting to false in production with a valid certificate

  ssh {
    agent    = true      # Assumes SSH agent forwarding is configured and an agent is running
    username = "terraform" # Ensure this user exists on Proxmox with necessary permissions
  }
}
