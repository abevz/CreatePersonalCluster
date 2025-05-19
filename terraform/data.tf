data "sops_file" "secrets" {
  source_file = "secrets.sops.yaml" # Ensure this file is in the root of your terraform project
}

data "local_file" "ssh_public_key" {
  filename = "kubekey.pub" # Ensure this file is in the root of your terraform project
}
