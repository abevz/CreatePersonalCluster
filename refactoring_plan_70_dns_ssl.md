# Refactoring Plan for modules/70_dns_ssl.sh

This document outlines a refactoring plan for the `modules/70_dns_ssl.sh` script. The goal is to break down large, complex functions into smaller, more manageable functions with single responsibilities.

## Public API

An analysis of the workspace revealed that no functions within this script are called by other scripts in the `modules/` or `lib/` directories. This means there is no public API to maintain, which simplifies refactoring.

## Refactoring Candidates

### 1. Function: `dns_ssl_regenerate_certificates`

This function handles user interaction for node selection, confirmation, and executing the Ansible playbook for certificate regeneration.

#### Proposed New Functions

*   `_regenerate_get_target_node()`: Handles the interactive menu for target node selection.
*   `_regenerate_confirm_operation(target_node)`: Displays a warning and asks the user for confirmation.
*   `_regenerate_run_ansible(target_node)`: Constructs the `extra_vars` and runs the Ansible playbook.
*   `_regenerate_handle_success()`: Displays next steps and performs post-regeneration verification.
*   `_regenerate_handle_failure()`: Manages logging and error handling for a failed Ansible run.

#### Refactoring Steps

1.  **Implement New Functions:** Create all the new `_regenerate_*` helper functions listed above.
2.  **Recompose Original Function:** Rewrite the body of `dns_ssl_regenerate_certificates` to be a simple sequence of calls to the new helper functions.
3.  **Error Handling:** Ensure that the new composition correctly handles errors returned from the helper functions.

### 2. Function: `dns_ssl_test_resolution`

This function handles argument parsing, pre-flight checks, and running multiple `kubectl` commands to test DNS.

#### Proposed New Functions

*   `_test_dns_get_domain()`: Prompts the user for a domain if one is not provided.
*   `_test_dns_preflight_checks()`: Checks for `kubectl` and cluster connectivity.
*   `_test_dns_run_main_test(domain, dns_server)`: Runs the primary `nslookup` test in a temporary pod.
*   `_test_dns_run_internal_test()`: Runs the internal DNS test for `kubernetes.default.svc.cluster.local`.
*   `_test_dns_run_external_test()`: Runs the external DNS test against `8.8.8.8`.

#### Refactoring Steps

1.  **Implement New Functions:** Create all the new `_test_dns_*` helper functions.
2.  **Recompose Original Function:** Rewrite `dns_ssl_test_resolution` to call the new helper functions in order.

### 3. Function: `dns_ssl_verify_certificates`

This function has two large blocks of logic for local and remote certificate verification.

#### Proposed New Functions

*   `_verify_certs_locally()`: Contains all the logic for checking certificate files in `/etc/kubernetes/pki`.
*   `_verify_single_local_cert(cert_path, cert_name)`: A sub-function to check a single local certificate file for expiry and SANs.
*   `_verify_certs_remotely()`: Contains all the logic for checking cluster connectivity and node status via `kubectl`.

#### Refactoring Steps

1.  **Implement New Functions:** Create the new `_verify_certs_*` helper functions.
2.  **Recompose Original Function:** Rewrite `dns_ssl_verify_certificates` to have a main `if/else` block that calls either `_verify_certs_locally` or `_verify_certs_remotely`.

### 4. Function: `dns_ssl_check_cluster_dns`

This is a large function that performs many different checks related to the cluster's DNS health.

#### Proposed New Functions

*   `_check_dns_preflight()`: Checks for `kubectl` and cluster connectivity.
*   `_check_dns_get_pod_status()`: Gets and displays the status of CoreDNS pods.
*   `_check_dns_get_service_status()`: Gets and displays the status of the `kube-dns` service.
*   `_check_dns_get_configmap()`: Gets and displays the CoreDNS ConfigMap.
*   `_check_dns_run_resolution_tests()`: Calls the existing `dns_ssl_test_resolution` for internal and external domains.
*   `_check_dns_common_issues()`: Checks for common issues like pod readiness and `kube-proxy` status.

#### Refactoring Steps

1.  **Implement New Functions:** Create all the new `_check_dns_*` helper functions.
2.  **Recompose Original Function:** Rewrite `dns_ssl_check_cluster_dns` to be a sequence of calls to these new helper functions.

## Safe Order of Operations

The following order should be used to safely refactor the script:

1.  **Create New Functions:** Add all the new, smaller helper functions (e.g., `_regenerate_*`, `_test_dns_*`, etc.) to the bottom of the `70_dns_ssl.sh` script. At this stage, the original functions are not yet modified.
2.  **Test Helpers Independently (Optional but Recommended):** If possible, source the script in a test environment and test the new helper functions individually to ensure they perform their single responsibility correctly.
3.  **Replace Logic Incrementally:** One by one, modify the original large functions. Replace the logic inside them with calls to the new helper functions.
4.  **Test the Refactored Functions:** After a large function has been refactored into a sequence of calls to helpers, test its functionality thoroughly to ensure it behaves exactly as it did before the refactoring.
5.  **Cleanup:** Once all functions are refactored and tested, you can remove any old, commented-out code blocks. Since there is no external Public API, no other files need to be updated.
