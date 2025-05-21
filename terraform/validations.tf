check "valid_workspace" {
  assert {
    condition     = contains(["debian", "ubuntu", "rocky"], terraform.workspace)
    error_message = "Invalid workspace selected: \"${terraform.workspace}\". Please choose from 'debian', 'ubuntu', or 'rocky' using 'tofu workspace select <name>'."
  }
}
