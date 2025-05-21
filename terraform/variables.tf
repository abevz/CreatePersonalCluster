variable "pm_node" {
  type        = string
  description = "Proxmox node name where VMs will be created."
  # Example: 
  default = "homelab"
}

variable "dns_servers" {
  type        = list(string)
  description = "List of DNS servers for VM initialization."
  default = ["10.10.10.187"]
  # Example: default = ["1.1.1.1", "8.8.8.8"]
}

variable "network_bridge" {
  description = "Network bridge to use"
  type        = string
  default     = "vmbr0"
}

variable "storage" {
  description = "Storage to use for VM disks"
  type        = string
  default     = "local-lvm"
}

# Add other common variables here that might be overridden by .tfvars files
variable "vm_cpu_cores" {
  type        = number
  description = "Number of CPU cores for VMs."
  default     = 1
}

variable "vm_memory_dedicated" {
  type        = number
  description = "Dedicated memory in MB for VMs."
  default     = 2048
}

variable "vm_disk_size" {
  description = "Disk size in GB for each VM."
  type        = number
  default     = 20
}

variable "vm_started" {
  description = "Defines the power state of the VMs. true for running, false for stopped."
  type        = bool
  default     = true
}

variable "proxmox_user" {
  description = "Proxmox user name"
  type        = string
  default     = "abevz" # You can change the default value or remove it so that it is always requested
}

variable "domain_name" {
  description = "Domain name for the VMs"
  type        = string
  default     = ".bevz.net" # You can change the default value or remove it so that it is always requested
}

variable "vm_template_name" {
  description = "Name of the VM template to use for cloning."
  type        = string
  default     = "ubuntu-template" # Change this to your template name
}

variable "vm_id_start" {
  description = "ID to start assigning VM IDs from."
  type        = number
  default     = 100
}

variable "vm_count" {
  description = "Number of VMs to create."
  type        = number
  default     = 1
}

variable "ssh_keys" {
  description = "SSH keys for VM access."
  type        = list(string)
  default     = []
}

variable "cloud_init_user_data" {
  description = "Cloud-init user data for VM customization."
  type        = string
  default     = <<EOF
#cloud-config
users:
  - name: abe
    ssh-authorized-keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArD1...
EOF
}

variable "cloud_init_network_config" {
  description = "Cloud-init network configuration."
  type        = string
  default     = <<EOF
#cloud-config
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: true
EOF
}