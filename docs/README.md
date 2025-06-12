# Project: Proxmox VM and Kubernetes Cluster Automation

## 📚 Documentation Index

### 🚀 Quick Start Guides
- **[Complete Cluster Creation Guide](complete_cluster_creation_guide.md)** - ⭐ **NEW** Complete cluster creation guide (RECOMMENDED)
- **[Complete Workflow Guide](complete_workflow_guide.md)** - End-to-end cluster deployment walkthrough
- **[Bootstrap Command Guide](bootstrap_command_guide.md)** - Detailed guide for the `cpc bootstrap` command
- **[Cluster Deployment Guide](cluster_deployment_guide.md)** - Comprehensive deployment documentation

### 🔧 Core Documentation
- **[Architecture Overview](architecture.md)** - System architecture and design principles
- **[CPC Template Variables Guide](cpc_template_variables_guide.md)** - Configuration reference
- **[Project Status Summary](project_status_summary.md)** - Current development status

### 🛠️ Troubleshooting Guides
- **[SSH Management Commands](ssh_management_commands.md)** - SSH connection and known_hosts management
- **[SSH Key Troubleshooting](ssh_key_troubleshooting.md)** - SSH authentication issues
- **[Template SSH Troubleshooting](template_ssh_troubleshooting.md)** - VM template SSH problems
- **[Cloud-Init User Issues](cloud_init_user_issues.md)** - User account creation problems
- **[Proxmox VM Helper](proxmox_vm_helper.md)** - VM management utilities

### 📊 Status Reports
- **[SSH Bootstrap Fix Summary](ssh_bootstrap_fix_summary.md)** - SSH host key verification automation
- **[Project Status Report](project_status_report.md)** - Development progress tracking
- **[Addon Installation Report](addon_installation_completion_report.md)** - Recent addon improvements
- **[Template Status Updates](template_status_update.md)** - VM template development status

---

## 1. Overview

This project automates the provisioning of Virtual Machines (VMs) in a Proxmox VE environment using Terraform, and subsequently bootstraps a Kubernetes cluster on these VMs using Ansible. It includes features for managing DNS records in Pi-hole based on VM deployments and utilizes SOPS for encrypting sensitive data. The primary interface for managing these operations is the `cpc` (Cluster Provisioning Control) shell script.

## 2. Core Technologies

*   **Proxmox VE**: Virtualization platform.
*   **Terraform**: Infrastructure as Code tool for provisioning Proxmox VMs.
    *   **OpenTofu**: Open source fork of Terraform used in this project.
*   **Ansible**: Configuration management and automation tool for setting up Kubernetes and other software.
*   **Kubernetes**: Container orchestration platform.
*   **SOPS (Secrets OPerationS)**: For encrypting and decrypting secret files (e.g., `secrets.sops.yaml`).
*   **Pi-hole**: Network-level ad and tracker blocking application, used here for managing local DNS records for VMs.
*   **Shell Scripting (Bash)**: For the `cpc` wrapper script.
*   **Python**: For the Pi-hole DNS management script.
*   **Cloud-init**: For initial VM configuration upon first boot.

## 3. Project Structure

```
my-kthw/
├── ansible/                # Ansible playbooks, roles, inventory, and configuration
│   ├── ansible.cfg         # Ansible configuration file
│   ├── inventory/          # Dynamic inventory scripts (e.g., tofu_inventory.py)
│   ├── playbooks/          # Main Ansible playbooks
│   └── roles/              # Ansible roles for modular configuration
├── cpc                     # Main control script for managing the project workflow
├── cpc.env.example         # Example environment file for cpc
├── docs/                   # Detailed documentation (original Kubernetes The Hard Way steps)
├── scripts/                # Helper scripts (e.g., add_pihole_dns.py)
├── terraform/              # Terraform configurations for Proxmox infrastructure
│   ├── main.tf             # Main Terraform configuration defining resources
│   ├── variables.tf        # Input variables for Terraform
│   ├── outputs.tf          # Outputs from Terraform (e.g., VM IPs, FQDNs)
│   ├── locals.tf           # Local values for Terraform configurations
│   ├── providers.tf        # Terraform provider configurations
│   ├── backend.tf          # Terraform backend configuration (e.g., for S3 state)
│   ├── secrets.sops.yaml   # Encrypted secrets file (e.g., API keys, passwords)
│   ├── environments/       # Environment-specific .tfvars files (debian.tfvars, etc.)
│   └── modules/            # Terraform modules (if any)
└── README.md               # This file
```

## 4. Prerequisites

*   **Proxmox VE**: A running Proxmox VE instance with necessary templates pre-configured.
*   **OpenTofu (or Terraform)**: Installed locally.
*   **Ansible**: Installed locally.
*   **SOPS**: Installed locally and configured with a PGP key or other KMS.
*   **Python 3**: With `requests` and `PyYAML` libraries (for `add_pihole_dns.py`).
*   **`curl`**: Command-line tool for transferring data with URLs.
*   **`jq`**: Command-line JSON processor.
*   **Git**: For cloning the repository.
*   **SSH Key Pair**: For accessing VMs. The public key should be in `terraform/id_rsa.pub`.

## 5. Setup

1.  **Clone the Repository**:
    ```bash
    git clone <repository_url>
    cd my-kthw
    ```

2.  **Configure `cpc` Script**:
    Run the setup command to store the repository path:
    ```bash
    ./cpc setup-cpc
    ```
    Consider adding `cpc` to your system's PATH for easier access:
    ```bash
    sudo ln -s "$(pwd)/cpc" /usr/local/bin/cpc
    ```

3.  **SOPS Configuration**:
    *   Ensure SOPS is installed and you have a PGP key configured for encryption/decryption.
    *   The `terraform/secrets.sops.yaml` file contains sensitive information. You will need to decrypt it to view/edit and encrypt it back.
        *   To edit: `sops terraform/secrets.sops.yaml`
        *   This will decrypt the file for editing and re-encrypt on save.
    *   Populate `secrets.sops.yaml` with your Proxmox API token, Pi-hole credentials, etc.

4.  **Environment Variables (`cpc.env`)**:
    *   Copy `cpc.env.example` to `cpc.env` in the repository root:
        ```bash
        cp cpc.env.example cpc.env
        ```
    *   Edit `cpc.env` to set versions for Kubernetes, and other software if needed. These variables are sourced by the `cpc` script.

5.  **SSH Public Key**:
    *   Place your SSH public key in `terraform/id_rsa.pub`. This key will be added to the authorized keys on the provisioned VMs.

6.  **Terraform Variables and Backend**:
    *   Review `terraform/variables.tf` and adjust default values if necessary.
    *   Configure `terraform/backend.tf` if you plan to use a remote backend for Terraform state (e.g., S3).
    *   Create environment-specific variable files in `terraform/environments/` (e.g., `debian.tfvars`, `ubuntu.tfvars`, `rocky.tfvars`). These files define parameters like Proxmox node, VM template IDs, and DNS servers for each target OS environment/workspace.

## 6. Usage / Workflow

The `cpc` script is the central point for managing the project.

1.  **Set Current Context (Tofu Workspace)**:
    The context determines which Tofu workspace is active and, by extension, which OS environment (e.g., Debian, Ubuntu, Rocky) and corresponding `.tfvars` file will be used.
    ```bash
    cpc ctx <workspace_name>
    # Example: cpc ctx debian
    ```
    If the workspace doesn't exist, `cpc` will create it. To see the current context or list available workspaces:
    ```bash
    cpc ctx
    ```

2.  **Deploy Infrastructure (Terraform)**:
    Use the `deploy` command to run Tofu commands within the selected context.
    *   **Plan changes**:
        ```bash
        cpc deploy plan
        ```
    *   **Apply changes**:
        ```bash
        cpc deploy apply
        # For auto-approval:
        # cpc deploy apply -auto-approve
        ```
    *   **View outputs**:
        ```bash
        cpc deploy output
        cpc deploy output vm_fqdns
        ```
    *   **Destroy infrastructure**:
        ```bash
        cpc deploy destroy
        ```
    The `deploy` command automatically uses the appropriate `.tfvars` file from the `terraform/environments/` directory based on the current context.

3.  **Manage VMs**:
    *   **Start VMs**:
        ```bash
        cpc start-vms
        ```
        (This runs `tofu apply -var="vm_started=true" -auto-approve`)
    *   **Stop VMs**:
        ```bash
        cpc stop-vms
        ```
        (This runs `tofu apply -var="vm_started=false" -auto-approve`)

4.  **Update Pi-hole DNS Records**:
    After VMs are provisioned and have IP addresses, update Pi-hole DNS records.
    *   **Add/Update DNS records**:
        ```bash
        cpc update-pihole add
        ```
    *   **Remove DNS records**:
        ```bash
        cpc update-pihole unregister-dns
        ```
    This command uses `scripts/add_pihole_dns.py` which reads Tofu outputs for FQDNs and IPs.

5.  **Run Commands on VMs (Ansible)**:
    Execute arbitrary shell commands on target VMs or groups defined in the Ansible inventory.
    ```bash
    cpc run-command <target_hosts_or_group> "<shell_command>"
    # Example: cpc run-command all "hostname -f"
    # Example: cpc run-command controlplane_nodes "sudo apt update"
    ```

6.  **Bootstrap Kubernetes Cluster (Ansible)**:
    (Assuming playbooks like `install_kubernetes_cluster.yml` are defined)
    The `cpc` script can be extended or used to call Ansible playbooks directly. For example, to run a main playbook:
    ```bash
    # This is a generic example; specific playbooks might be invoked differently
    # or through dedicated cpc commands if implemented.
    cd ansible/
    ansible-playbook -i inventory/tofu_inventory.py playbooks/main.yml 
    cd ..
    ```
    The `tofu_inventory.py` script dynamically generates an Ansible inventory from the Tofu state.

## 7. Key Components

*   **`cpc` Script**:
    *   A Bash script that acts as a wrapper around Tofu, Ansible, and custom scripts.
    *   Manages context (Tofu workspaces).
    *   Simplifies common operations like deployment, VM state changes, and DNS updates.
    *   Sources environment variables from `cpc.env`.

*   **Terraform (`terraform/`)**:
    *   `main.tf`: Defines Proxmox VM resources (`proxmox_virtual_environment_vm`), cloud-init configurations (`proxmox_virtual_environment_file`, `terraform_data`), and other necessary infrastructure components.
    *   `variables.tf`: Declares input variables (e.g., Proxmox connection details, VM specifications, domain names). Many of these are intended to be overridden by `.tfvars` files or SOPS secrets.
    *   `outputs.tf`: Defines outputs like VM IP addresses and FQDNs, which are consumed by other scripts (e.g., `add_pihole_dns.py`, `tofu_inventory.py`).
    *   `locals.tf`: Defines local values to simplify expressions and improve readability, such as mapping workspace names to OS types or template IDs.
    *   `environments/*.tfvars`: Contains variable definitions specific to each deployment environment/context (e.g., `debian.tfvars` for the `debian` workspace). These typically define `pm_node`, `dns_servers`, and OS-specific template IDs.
    *   `data.tf`: Defines data sources, such as reading the SSH public key.

*   **Ansible (`ansible/`)**:
    *   `inventory/tofu_inventory.py`: A dynamic inventory script that queries the Tofu state file to get information about provisioned VMs (IPs, hostnames, groups based on roles).
    *   `ansible.cfg`: Configures Ansible behavior (e.g., inventory path, remote user).
    *   `playbooks/`: Contains Ansible playbooks for tasks like installing Kubernetes, configuring nodes, etc.
    *   `roles/`: Contains reusable Ansible roles for modularizing configuration tasks.

*   **Pi-hole Integration (`scripts/add_pihole_dns.py`)**:
    *   A Python script that interacts with the Pi-hole API.
    *   Reads VM FQDNs and IP addresses from Tofu outputs.
    *   Adds or deletes DNS records in Pi-hole to make VMs resolvable by their hostnames.
    *   Handles authentication with Pi-hole using credentials from `secrets.sops.yaml`.

*   **Secrets Management (SOPS)**:
    *   `terraform/secrets.sops.yaml` stores sensitive data like API tokens, passwords, etc.
    *   This file is encrypted using SOPS and can be safely committed to version control.
    *   The `cpc` script and `add_pihole_dns.py` script (via SOPS CLI) decrypt these secrets at runtime when needed.

## 8. Troubleshooting

*   **Permissions for `tofu_inventory.py`**: Ensure `ansible/inventory/tofu_inventory.py` is executable (`chmod +x ansible/inventory/tofu_inventory.py`).
*   **SOPS Decryption Issues**: Verify that SOPS is correctly configured with your PGP key or KMS and that you have the necessary permissions.
*   **Terraform State Lock**: If `cpc deploy` commands fail with state lock errors, ensure no other Tofu processes are running. You might need to manually unlock the state if a previous command crashed (`tofu force-unlock`).
*   **Pi-hole API Errors**: Check Pi-hole logs and ensure the API token and password in `secrets.sops.yaml` are correct and the Pi-hole instance is reachable.
*   **Cloud-init Issues**: Check `/var/log/cloud-init.log` and `/var/log/cloud-init-output.log` on the VMs if they don't configure as expected.
