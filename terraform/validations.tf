check "valid_workspace" {
  assert {
    condition     = contains(["debian", "ubuntu", "rocky", "suse"], terraform.workspace)
    error_message = "Invalid workspace selected: \"${terraform.workspace}\". Please choose from 'debian', 'ubuntu', 'rocky' or 'suse' using 'tofu workspace select <name>'."
  }
}
