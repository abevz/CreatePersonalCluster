# Refactoring Plan for modules/50_cluster_ops.sh

This document outlines a refactoring plan for the `modules/50_cluster_ops.sh` script. The goal is to break down large, complex functions into smaller, more manageable functions with single responsibilities.

## Public API

An analysis of the workspace revealed that no functions within this script are called by other scripts in the `modules/` or `lib/` directories. This means there is no public API to maintain, which simplifies refactoring.

## Refactoring Candidates

### 1. Function: `cluster_ops_upgrade_addons`

This function is responsible for handling the entire addon upgrade process, from user interaction to running Ansible and validating the result. It can be broken down into the following smaller functions.

#### Proposed New Functions

*   `_upgrade_addons_get_user_selection()`: Handles the interactive menu for addon selection if no addon is provided as an argument.
*   `_upgrade_addons_validate_selection(addon_name)`: Validates if the selected addon exists and is a valid choice.
*   `_upgrade_addons_prepare_environment(addon_name)`: Loads secrets and validates the presence of required tokens (like Cloudflare).
*   `_upgrade_addons_build_ansible_vars(addon_name, addon_version)`: Constructs the `--extra-vars` string for the Ansible command.
*   `_upgrade_addons_determine_playbook(addon_name)`: Determines whether to use the legacy or modular Ansible playbook.
*   `_upgrade_addons_run_ansible(playbook, extra_vars)`: Executes the chosen Ansible playbook with the specified variables.
*   `_upgrade_addons_handle_failure(addon_name)`: Manages logging and error handling for a failed Ansible run.

#### Refactoring Steps

1.  **Implement New Functions:** Create all the new `_upgrade_addons_*` helper functions listed above.
2.  **Recompose Original Function:** Rewrite the body of `cluster_ops_upgrade_addons` to be a simple sequence of calls to the new helper functions.
3.  **Error Handling:** Ensure that the new composition correctly handles errors returned from the helper functions.

### 2. Function: `cluster_configure_coredns`

This function handles argument parsing, fetching configuration, user confirmation, and running the Ansible playbook for CoreDNS.

#### Proposed New Functions

*   `_coredns_parse_args("$@")`: Parses command-line arguments like `--dns-server` and `--domains`.
*   `_coredns_get_dns_server(current_dns_server)`: Fetches the DNS server from Terraform if it wasn't provided as an argument.
*   `_coredns_get_domains(current_domains)`: Sets the default domains if they weren't provided as an argument.
*   `_coredns_confirm_operation(dns_server, domains)`: Displays the configuration and asks the user for confirmation with a timeout.
*   `_coredns_run_ansible(dns_server, domains)`: Validates inputs and runs the `configure_coredns_local_domains.yml` playbook.

#### Refactoring Steps

1.  **Implement New Functions:** Create all the new `_coredns_*` helper functions.
2.  **Recompose Original Function:** Rewrite `cluster_configure_coredns` to call the new helper functions in order, passing data between them.
3.  **Integrate Recovery:** Ensure the `recovery_checkpoint` and `recovery_execute` calls are wrapped around the appropriate new helper functions.

### 3. Function: `validate_addon_installation`

This function is large and handles validation for multiple different addons within a single `case` statement. It also mixes pre-flight checks with the actual validation logic.

#### Proposed New Functions

*   `_validate_preflight_checks()`: Checks for `kubectl` availability, Kubeconfig existence, and cluster connectivity. Returns a status code.
*   `_validate_addon_metallb()`: Contains the specific logic to validate the `metallb` installation.
*   `_validate_addon_metrics_server()`: Contains the specific logic to validate the `metrics-server` installation.
*   `_validate_addon_default(addon_name)`: Handles the case for an unknown addon.

#### Refactoring Steps

1.  **Implement New Functions:** Create the `_validate_preflight_checks` and the specific `_validate_addon_*` functions.
2.  **Recompose Original Function:** Rewrite `validate_addon_installation` to first call `_validate_preflight_checks`. If that succeeds, use a `case` statement to call the appropriate `_validate_addon_*` function based on the addon name.
3.  **Timeout:** The `timeout` logic should be wrapped around the call to the specific `_validate_addon_*` function, not the entire `case` statement.

## Safe Order of Operations

The following order should be used to safely refactor the script:

1.  **Create New Functions:** Add all the new, smaller helper functions (e.g., `_upgrade_addons_*`, `_coredns_*`, `_validate_*`) to the bottom of the `50_cluster_ops.sh` script. At this stage, the original functions are not yet modified.
2.  **Test Helpers Independently (Optional but Recommended):** If possible, source the script in a test environment and test the new helper functions individually to ensure they perform their single responsibility correctly.
3.  **Replace Logic Incrementally:** One by one, modify the original large functions (`cluster_ops_upgrade_addons`, etc.). Replace the logic inside them with calls to the new helper functions.
4.  **Test the Refactored Functions:** After a large function has been refactored into a sequence of calls to helpers, test its functionality thoroughly to ensure it behaves exactly as it did before the refactoring.
5.  **Cleanup:** Once all functions are refactored and tested, you can remove any old, commented-out code blocks. Since there is no external Public API, no other files need to be updated.
