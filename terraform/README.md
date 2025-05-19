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

## Deployment Instructions

1.  **Initialize Terraform**:
    Navigate to the `terraform` directory. For the first time or after backend changes:
    ```bash
    terraform init
    ```
    For subsequent initializations for a specific OS distribution (if backend key depends on `var.environment` and it's not set via CLI args for init):
    ```bash
    terraform init -backend-config="key=environments/<os_distribution_name>/terraform.tfstate"
    ```
    (Replace `<os_distribution_name>` with `debian`, `ubuntu`, or `rocky`)

2.  **Plan Changes**:
    To see what changes Terraform will make for a specific OS distribution:
    ```bash
    terraform plan -var-file="environments/<os_distribution_name>.tfvars"
    ```
    Example for `debian` environment:
    ```bash
    terraform plan -var-file="environments/debian.tfvars"
    ```

3.  **Apply Changes**:
    To apply the changes for a specific OS distribution:
    ```bash
    terraform apply -var-file="environments/<os_distribution_name>.tfvars"
    ```
    Example for `debian` environment:
    ```bash
    terraform apply -var-file="environments/debian.tfvars"
    ```

## Managing Secrets

Secrets are managed using SOPS. Ensure `secrets.sops.yaml` is present and SOPS is configured for decryption.

## Environment Variables

The `environments/*.tfvars` files are used to specify OS distribution-specific values for variables defined in `variables.tf`.
The `environment` variable itself (which now represents the OS distribution) and `os_type` should be defined in these files.
Example `debian.tfvars`:
```hcl
environment = "debian"
os_type     = "debian"
# other debian-specific variables like pm_node, dns_servers
```
