# Network Module

This module is responsible for creating network infrastructure.

## Usage

```hcl
module "network" {
  source = "./modules/network"

  environment = var.environment
  # vpc_cidr    = "10.0.0.0/16"
  # ... other variables
}
```

## Inputs

| Name        | Description                      | Type   | Default | Required |
|-------------|----------------------------------|--------|---------|:--------:|
| environment | Deployment environment           | string |         | yes      |
| `vpc_cidr`  | CIDR block for the VPC           | string | `""`    | no       |

## Outputs

| Name       | Description      |
|------------|------------------|
| `vpc_id`   | The ID of the VPC |
```
