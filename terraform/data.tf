data "sops_file" "secrets" {
  source_file = "secrets.sops.yaml" # Ensure this file is in the root of your terraform project
}


