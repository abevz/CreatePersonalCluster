# Refactoring Plan for modules/60_tofu.sh

## Cross-Module Analysis

### Functions Called by Other Modules
Based on analysis of the workspace, the following functions in `modules/60_tofu.sh` are called by other scripts in `modules/` or `lib/` directories:

1. **`cpc_tofu()`** - Main dispatcher function
   - Called by: `modules/05_workspace_ops.sh` (e.g., `cpc_tofu deploy destroy`)
   - This is the primary public API entry point for the module

2. **`tofu_deploy()`** - Deploy command handler
   - Called by: `modules/05_workspace_ops.sh` (indirectly through `cpc_tofu deploy`)
   - Also called internally by `tofu_start_vms()` and `tofu_stop_vms()`

3. **`tofu_load_workspace_env_vars()`** - Environment variable loader
   - Called by: `modules/30_k8s_cluster.sh` (for loading workspace variables before tofu operations)

4. **`tofu_update_node_info()`** - Node information parser
   - Called by: `modules/30_k8s_cluster.sh` and `modules/40_k8s_nodes.sh` (for parsing cluster summary JSON)

### Public API Considerations
- The main entry point `cpc_tofu()` must maintain its current signature and behavior
- Functions like `tofu_deploy()` are part of the internal API but are called by other modules
- Any refactoring must preserve these external interfaces to avoid breaking changes

## Refactoring Steps

### 1. Refactor `tofu_deploy()` Function

**Current Issues:**
- The function is ~200 lines long with multiple responsibilities
- Handles command validation, environment loading, directory changes, AWS credentials, workspace selection, hostname generation, and command execution

**Proposed New Functions:**

1. **`validate_tofu_subcommand()`**
   - Single responsibility: Validates that the provided tofu subcommand is supported and safe to execute

2. **`setup_tofu_environment()`**
   - Single responsibility: Loads workspace environment variables and sets up the terraform directory context

3. **`prepare_aws_credentials()`**
   - Single responsibility: Retrieves and validates AWS credentials required for tofu operations

4. **`select_tofu_workspace()`**
   - Single responsibility: Ensures the correct tofu workspace is selected based on current context

5. **`generate_hostname_configs()`**
   - Single responsibility: Generates hostname configurations for Proxmox VMs when needed

6. **`build_tofu_command_array()`**
   - Single responsibility: Constructs the final tofu command array with all necessary arguments and variables

7. **`execute_tofu_command_with_retry()`**
   - Single responsibility: Executes the tofu command with retry logic and timeout handling

### 2. Refactor `tofu_show_cluster_info()` Function

**Current Issues:**
- ~150 lines handling caching, format validation, and output processing
- Mixes cache management, JSON parsing, and display logic

**Proposed New Functions:**

1. **`validate_cluster_info_format()`**
   - Single responsibility: Validates the requested output format (table/json) and sets defaults

2. **`manage_cluster_cache()`**
   - Single responsibility: Handles cache file creation, freshness checking, and cache retrieval

3. **`fetch_cluster_data()`**
   - Single responsibility: Retrieves fresh cluster data from tofu output when cache is stale

4. **`parse_cluster_json()`**
   - Single responsibility: Parses the JSON cluster summary into structured data arrays

5. **`format_cluster_output()`**
   - Single responsibility: Formats the parsed cluster data into the requested output format (table or JSON)

### 3. Refactor `tofu_load_workspace_env_vars()` Function

**Current Issues:**
- ~50 lines parsing environment files and setting variables
- Handles file validation, parsing, and variable export

**Proposed New Functions:**

1. **`validate_env_file()`**
   - Single responsibility: Validates that the environment file exists and is readable

2. **`parse_env_variables()`**
   - Single responsibility: Parses key-value pairs from the environment file into a structured format

3. **`export_terraform_variables()`**
   - Single responsibility: Exports parsed variables as Terraform environment variables with proper naming

### 4. Refactor `tofu_update_node_info()` Function

**Current Issues:**
- ~40 lines parsing JSON and populating global arrays
- Handles JSON validation and array population

**Proposed New Functions:**

1. **`validate_cluster_json()`**
   - Single responsibility: Validates that the provided JSON is valid and contains expected structure

2. **`extract_node_names()`**
   - Single responsibility: Extracts node names from the cluster JSON into an array

3. **`extract_node_ips()`**
   - Single responsibility: Extracts node IP addresses from the cluster JSON into an array

4. **`extract_node_hostnames()`**
   - Single responsibility: Extracts node hostnames from the cluster JSON into an array

5. **`extract_node_vm_ids()`**
   - Single responsibility: Extracts VM IDs from the cluster JSON into an array

## Function Responsibilities

### For `tofu_deploy()` Refactoring:
- `validate_tofu_subcommand()`: Ensures the tofu subcommand is valid and supported
- `setup_tofu_environment()`: Prepares the environment by loading variables and changing to terraform directory
- `prepare_aws_credentials()`: Obtains and validates AWS credentials for tofu operations
- `select_tofu_workspace()`: Switches to the correct tofu workspace for the current context
- `generate_hostname_configs()`: Creates hostname configuration files for Proxmox VMs
- `build_tofu_command_array()`: Assembles the complete tofu command with all arguments
- `execute_tofu_command_with_retry()`: Runs the tofu command with error handling and retry logic

### For `tofu_show_cluster_info()` Refactoring:
- `validate_cluster_info_format()`: Checks and normalizes the output format parameter
- `manage_cluster_cache()`: Handles all cache-related operations including freshness checks
- `fetch_cluster_data()`: Retrieves current cluster data from tofu when needed
- `parse_cluster_json()`: Converts raw JSON into structured data arrays
- `format_cluster_output()`: Transforms parsed data into user-readable output format

### For `tofu_load_workspace_env_vars()` Refactoring:
- `validate_env_file()`: Confirms the environment file exists and is accessible
- `parse_env_variables()`: Reads and parses environment variables from the file
- `export_terraform_variables()`: Sets the parsed variables as Terraform environment variables

### For `tofu_update_node_info()` Refactoring:
- `validate_cluster_json()`: Ensures the cluster JSON is valid and properly structured
- `extract_node_names()`: Pulls node names from the JSON structure
- `extract_node_ips()`: Pulls IP addresses from the JSON structure
- `extract_node_hostnames()`: Pulls hostnames from the JSON structure
- `extract_node_vm_ids()`: Pulls VM IDs from the JSON structure

## Safe Order of Operations

1. **Create Helper Function Files**
   - Create new files for each group of helper functions (e.g., `lib/tofu_deploy_helpers.sh`, `lib/tofu_cluster_helpers.sh`)
   - Implement all new helper functions with comprehensive error handling
   - Add unit tests for each new helper function

2. **Update Module Dependencies**
   - Add source statements in `modules/60_tofu.sh` to include the new helper files
   - Ensure helper functions are loaded before the main functions that use them

3. **Refactor Functions One by One**
   - Start with `tofu_load_workspace_env_vars()` (simplest, no external dependencies)
   - Then refactor `tofu_update_node_info()` (used by other modules)
   - Next refactor `tofu_show_cluster_info()` (complex but self-contained)
   - Finally refactor `tofu_deploy()` (most complex, used by other modules)

4. **Replace Logic in Original Functions**
   - For each major function, replace the internal logic with calls to the new helper functions
   - Maintain the original function signature and public behavior
   - Add logging to track the refactoring process

5. **Update Internal Calls**
   - Update any internal calls within `modules/60_tofu.sh` to use the new helper functions
   - Ensure all function calls pass the correct parameters

6. **Test External Interfaces**
   - Verify that functions called by other modules (`cpc_tofu()`, `tofu_deploy()`, etc.) still work correctly
   - Run integration tests with `modules/05_workspace_ops.sh`, `modules/30_k8s_cluster.sh`, etc.

7. **Clean Up Original Code**
   - Once all refactoring is complete and tested, remove the old inline logic from the original functions
   - Update function documentation to reflect the new structure

8. **Final Validation**
   - Run full test suite including unit tests and integration tests
   - Verify that all tofu operations work as expected
   - Confirm that the module still integrates properly with the main cpc script

This refactoring approach ensures minimal risk by maintaining the public API and testing at each