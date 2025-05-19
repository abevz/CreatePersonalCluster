# variables.tf for the app-service module

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
}

/*
variable "instance_count" {
  description = "Number of application instances"
  type        = number
  default     = 1
}

variable "ami_id" {
  description = "AMI ID for the application instances"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the application instances"
  type        = string
}
*/
