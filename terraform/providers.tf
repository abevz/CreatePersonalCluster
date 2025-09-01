provider "sops" {
  # Configuration for SOPS provider, if any specific settings are needed.
}

provider "aws" {
  region     = "us-east-1"
  access_key = data.sops_file.secrets.data["minio_access_key"]
  secret_key = data.sops_file.secrets.data["minio_secret_key"]

  # MinIO specific configuration
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_metadata_api_check     = true

  endpoints {
    s3 = "https://s3.minio.bevz.net"
  }
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
