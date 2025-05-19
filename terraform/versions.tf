terraform {
  required_version = ">= 1.0" # Specify your desired Terraform version

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78.0" # Using pessimistic operator for minor updates
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4" # Added for local_file data source
    }
  }
}
