# Terraform Project for Kubernetes Infrastructure

This project manages Kubernetes infrastructure using Terraform. It is structured to support multiple environments (e.g., dev, staging, prod) using a common codebase and environment-specific variable files.

## Project Structure

- `main.tf`: Root module definition, calling other modules.
- `variables.tf`: Common variables for the root module.
- `outputs.tf`: Outputs from the root module.
- `versions.tf`: Terraform and provider version requirements.
- `providers.tf`: Configuration for providers.
- `locals.tf`: Local values and computations.
- `data.tf`: Data source definitions.
- `backend.tf`: Configuration for Terraform's remote state backend.
- `environments/`: Contains environment-specific `.tfvars` files (e.g., `dev.tfvars`, `staging.tfvars`, `prod.tfvars`).
- `modules/`: Contains reusable Terraform modules (e.g., `network`, `app-service`).

## Prerequisites

- Terraform installed.
- Access credentials configured for your Proxmox environment and any other providers.
- SOPS configured for decrypting `secrets.sops.yaml`.
- SSH key `kubekey.pub` present in the `terraform` directory.

# Proxmox VM and Pool Management with Terraform

This Terraform configuration is designed to create and manage Virtual Machines (VMs) in a Proxmox VE environment. It leverages Terraform workspaces to deploy different operating systems (Debian, Ubuntu, Rocky Linux) from predefined templates.

## Prerequisites

1.  **Proxmox VE Environment**: A running Proxmox VE server.
2.  **VM Templates**: Pre-configured VM templates for each supported OS (Debian, Ubuntu, Rocky) must exist in Proxmox. Their IDs need to be specified in `variables.tf` or a `.tfvars` file.
3.  **Proxmox API Token**: A Proxmox API token with appropriate permissions. This should be configured via environment variables (`PM_API_TOKEN_ID` and `PM_API_TOKEN_SECRET`) or directly in `providers.tf` (not recommended for production).
4.  **SOPS for Secrets**: Secrets like SSH keys and VM passwords are managed using SOPS. Ensure SOPS is configured and the `secrets.sops.yaml` file is encrypted with your PGP key or other SOPS backend.
5.  **Terraform and OpenTofu**: Terraform (or OpenTofu) installed.
6.  **Proxmox Pools**: This configuration will automatically create a Proxmox resource pool for each Terraform workspace (e.g., a pool named "UBUNTU" for the "ubuntu" workspace, "DEBIAN" for "debian", etc.). If you prefer to manage pools manually, you can remove the `proxmox_virtual_environment_pool` resource from `main.tf` and ensure the pools exist in Proxmox before applying the configuration.

## Configuration Overview

*   **`main.tf`**: Defines the Proxmox provider, SOPS provider, and the resource for creating Proxmox pools.
*   **`variables.tf`**: Declares input variables (e.g., Proxmox node, template IDs, VM specs).
*   **`locals.tf`**: Defines local variables for dynamic configuration, including VM naming, SOPS data extraction, and the main `final_nodes_map` which constructs the desired state for each VM.
*   **`nodes.tf`**: Contains the `proxmox_virtual_environment_vm` resource definition, which iterates over `local.final_nodes_map` to create VMs. It handles cloning, CPU, memory, disk, network, and cloud-init configuration.
*   **`outputs.tf`**: Defines outputs, such as VM IP addresses.
*   **`data.tf`**: Defines data sources, primarily for reading the SOPS encrypted secrets file.
*   **`secrets.sops.yaml`**: Encrypted file holding sensitive data (VM password, SSH keys).
*   **`environments/`**: Directory containing `.tfvars` files for different environments/OS deployments (e.g., `ubuntu.tfvars`).
*   **`versions.tf`**: Specifies required provider versions.
*   **`backend.tf`**: Configures the Terraform backend (currently local).

## Usage

1.  **Initialize Terraform**:
    ```bash
    tofu init
    ```

2.  **Select/Create Workspace**:
    For example, to deploy Ubuntu VMs:
    ```bash
    tofu workspace select ubuntu || tofu workspace new ubuntu
    ```
    This will also determine the name of the Proxmox pool to be used/created (e.g., "UBUNTU").

3.  **Prepare Variables**:
    *   Ensure your VM templates exist and their IDs are correctly set in `variables.tf` or an environment-specific `.tfvars` file (e.g., `environments/ubuntu.tfvars`).
    *   Update `secrets.sops.yaml` with your desired VM password and SSH public keys using SOPS:
        ```bash
        sops environments/secrets.sops.yaml
        ```
        (Or your configured SOPS editing command)

4.  **Plan**:
    ```bash
    tofu plan -var-file=environments/ubuntu.tfvars
    ```
    (Replace `ubuntu.tfvars` with the appropriate file for your selected workspace). Review the plan carefully.

5.  **Apply**:
    ```bash
    tofu apply -var-file=environments/ubuntu.tfvars
    ```

## VM Naming Convention

VMs are named according to the pattern: `<role_letter><os_release_letter><index_number><vm_domain>`
*   `role_letter`: "c" for controlplane, "w" for worker.
*   `os_release_letter`: "d" for Debian, "u" for Ubuntu, "r" for Rocky.
*   `index_number`: A sequential number for VMs of the same role.
*   `vm_domain`: Configurable domain suffix (e.g., `.bevz.net`).

Example: `cu1.bevz.net` (Controlplane, Ubuntu, index 1, domain .bevz.net)

## Cloud-Init

VMs are configured using cloud-init. User data includes:
*   Setting the hostname.
*   Adding the specified user (`var.vm_user`).
*   Injecting SSH public keys (`local.sops_vm_ssh_keys`).
*   Setting the user's password (`local.sops_vm_password`).
*   Network configuration is set to DHCP.

## Important Notes

*   **Proxmox Node**: Ensure `var.pm_node` in your `.tfvars` or `variables.tf` points to a valid Proxmox host node where cloning and VM creation will occur.
*   **Storage**: Disk images are created on the datastore specified in `locals.tf` (currently hardcoded as "MyStorage" within `final_nodes_map.disks.datastore_id`). Ensure this datastore exists and has sufficient space.
*   **Resource Pools**: As mentioned, pools are now created automatically based on the workspace name. If a pool with the target name already exists, Terraform will attempt to manage it.
