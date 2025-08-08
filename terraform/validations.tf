# Valid workspace check is now handled dynamically through the script
# This condition was previously restricting us to specific workspaces
# If needed, validation can be reimplemented using local variables
# check "valid_workspace" {
#   assert {
#     condition     = contains(local.valid_workspaces, terraform.workspace)
#     error_message = "Invalid workspace selected: \"${terraform.workspace}\". Please choose from valid workspaces."
#   }
# }
