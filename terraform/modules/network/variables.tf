# variables.tf for the network module

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
}

/*
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}
*/
