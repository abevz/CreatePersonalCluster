# Example backend configuration (e.g., S3)
# Replace with your actual backend configuration.
# Ensure the 'environment' variable is defined in your .tfvars files or passed via CLI.

terraform {
  backend "s3" { # Example: Using S3 backend
    bucket         = "my-terraform-state-bucket-name" # Replace with your S3 bucket name
    key            = "environments/${var.environment}/terraform.tfstate" # Dynamically set path based on environment
    region         = "us-east-1"                        # Replace with your S3 bucket region
    encrypt        = true
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
