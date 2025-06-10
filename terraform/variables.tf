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
  default     = "MyStorage"
}

# Add other common variables here that might be overridden by .tfvars files
variable "vm_cpu_cores" {
  type        = number
  description = "Number of CPU cores for VMs."
  default     = 2
}

variable "pm_template_debian_id" {
  description = "ID of the Proxmox VM template for Debian."
  type        = number
  default     = 9410 # Please set the correct template ID
}

variable "pm_template_ubuntu_id" {
  description = "ID of the Proxmox VM template for Ubuntu."
  type        = number
  default     = 9420 # Please set the correct template ID
}

variable "pm_template_rocky_id" {
  description = "ID of the Proxmox VM template for Rocky Linux."
  type        = number
  default     = 9430 # Please set the correct template ID
}

variable "pm_template_suse_id" {
  description = "ID of the Proxmox VM template for SUSE Linux."
  type        = number
  default     = 9440 # Please set the correct template ID
}

variable "vm_domain" {
  description = "Domain suffix for VM hostnames (e.g., .example.com)."
  type        = string
  default     = ".bevz.net" # Please set your desired domain suffix
}

variable "vm_user" {
  description = "Default user to create on VMs via cloud-init."
  type        = string
  default     = "abevz" # Please set your desired default username
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


