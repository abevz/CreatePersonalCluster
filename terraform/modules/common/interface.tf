# Multi-Cloud Provider Interface Specification

variable "provider_type" {
  description = "Cloud provider type"
  type        = string
  validation {
    condition = contains([
      "proxmox", "aws", "azure", "gcp", "digitalocean", "linode", "vultr"
    ], var.provider_type)
    error_message = "Provider must be one of: proxmox, aws, azure, gcp, digitalocean, linode, vultr."
  }
}

variable "provider_config" {
  description = "Provider-specific configuration"
  type = object({
    # Common across all providers
    region = string
    zone   = optional(string)
    
    # Provider-specific fields (optional based on provider)
    # AWS
    availability_zones = optional(list(string))
    vpc_cidr          = optional(string)
    
    # Azure  
    location          = optional(string)
    resource_group    = optional(string)
    
    # GCP
    project_id        = optional(string)
    
    # Proxmox
    node_name         = optional(string)
    storage           = optional(string)
    
    # DigitalOcean/Linode
    datacenter        = optional(string)
  })
}

variable "cluster_config" {
  description = "Kubernetes cluster configuration"
  type = object({
    name                = string
    version             = optional(string, "1.31.9")
    
    control_plane = object({
      count         = optional(number, 1)
      instance_type = string
      disk_size     = optional(number, 20)
      disk_type     = optional(string, "gp3")
    })
    
    workers = object({
      count         = optional(number, 2)
      instance_type = string  
      disk_size     = optional(number, 20)
      disk_type     = optional(string, "gp3")
    })
    
    networking = object({
      vpc_cidr      = optional(string, "10.0.0.0/16")
      pod_cidr      = optional(string, "192.168.0.0/16")
      service_cidr  = optional(string, "10.96.0.0/12")
      public_access = optional(bool, false)
    })
  })
}

variable "os_config" {
  description = "Operating system configuration"
  type = object({
    family      = string # ubuntu, debian, rhel, amazonlinux, cos
    version     = string # 24.04, 12, 9, 2023, etc.
    arch        = optional(string, "amd64")
    
    # Cloud-specific image IDs (provider will select appropriate one)
    custom_image_id = optional(string)
  })
  
  validation {
    condition = contains([
      "ubuntu", "debian", "rhel", "rocky", "suse", "amazonlinux", "cos"
    ], var.os_config.family)
    error_message = "OS family must be supported."
  }
}

# Standardized outputs that all providers must implement
output "cluster_info" {
  description = "Cluster connection information"
  value = {
    provider = var.provider_type
    region   = var.provider_config.region
    name     = var.cluster_config.name
  }
}

output "control_plane_nodes" {
  description = "Control plane node information"
  value = [
    for node in local.control_plane_nodes : {
      name        = node.name
      private_ip  = node.private_ip
      public_ip   = try(node.public_ip, null)
      hostname    = node.hostname
      instance_id = node.instance_id
    }
  ]
}

output "worker_nodes" {
  description = "Worker node information"  
  value = [
    for node in local.worker_nodes : {
      name        = node.name
      private_ip  = node.private_ip
      public_ip   = try(node.public_ip, null)
      hostname    = node.hostname
      instance_id = node.instance_id
    }
  ]
}

output "ansible_inventory" {
  description = "Ansible inventory data"
  value = {
    control_plane = {
      hosts = {
        for node in local.control_plane_nodes : node.name => {
          ansible_host = node.private_ip
          ansible_user = local.ssh_user
          hostname     = node.hostname
          role         = "control_plane"
        }
      }
    }
    workers = {
      hosts = {
        for node in local.worker_nodes : node.name => {
          ansible_host = node.private_ip
          ansible_user = local.ssh_user  
          hostname     = node.hostname
          role         = "worker"
        }
      }
    }
    all = {
      vars = {
        ansible_ssh_private_key_file = var.ssh_private_key_path
        ansible_ssh_common_args      = "-o StrictHostKeyChecking=no"
      }
    }
  }
}

output "network_info" {
  description = "Network configuration details"
  value = {
    vpc_id              = try(local.vpc_id, null)
    subnet_ids          = try(local.subnet_ids, [])
    security_group_ids  = try(local.security_group_ids, [])
    load_balancer_dns   = try(local.load_balancer_dns, null)
  }
}
