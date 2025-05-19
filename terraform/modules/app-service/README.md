# App Service Module

This module is responsible for creating application services.

## Usage

```hcl
module "app_service" {
  source = "./modules/app-service"

  environment    = var.environment
  # instance_count = 2
  # ami_id         = "ami-xxxxxxxxxxxxxxxxx"
  # instance_type  = "t3.micro"
  # ... other variables
}
```

## Inputs

| Name             | Description                               | Type   | Default | Required |
|------------------|-------------------------------------------|--------|---------|:--------:|
| environment      | Deployment environment                    | string |         | yes      |
| `instance_count` | Number of application instances           | number | `1`     | no       |
| `ami_id`         | AMI ID for the application instances      | string | `""`    | no       |
| `instance_type`  | Instance type for application instances | string | `""`    | no       |


## Outputs

| Name           | Description                        |
|----------------|------------------------------------|
| `instance_ids` | List of application instance IDs |
```
