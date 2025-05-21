# Example backend configuration (e.g., S3)
# Replace with your actual backend configuration.
# Ensure the 'environment' variable is defined in your .tfvars files or passed via CLI.

terraform {
  backend "s3" { # Example: Using S3 backend
    bucket         = "mykthw-tfstate" # Replace with your S3 bucket name
    key            = "proxmox/minio-vm.tfstate" # Dynamically set path based on environment
    region         = "us-east-1"                        # Replace with your S3 bucket region
    endpoint       = "https://s3.minio.bevz.net"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    use_path_style            = true # Changed from force_path_style

    # dynamodb_table = "my-terraform-lock-table" # Optional: for state locking
  }
}

# If using Terraform Cloud / Enterprise:
# terraform {
#   backend "remote" {
#     hostname     = "app.terraform.io"
#     organization = "your-organization"
#
#     workspaces {
#       # The prefix will be combined with var.environment to form the workspace name
#       # e.g., if var.environment is "dev", workspace will be "my-project-dev"
#       # Ensure workspaces like "my-project-dev", "my-project-staging" exist in Terraform Cloud.
#       prefix = "my-project-"
#     }
#   }
# }
