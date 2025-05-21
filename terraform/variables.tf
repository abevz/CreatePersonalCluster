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
  type        = number
  description = "Disk size in GB for VMs."
  default     = 20
}

variable "vm_user" {
  type        = string
  description = "Username to create on the VMs via cloud-init."
  default     = "abevz" # Вы можете изменить значение по умолчанию или убрать его, чтобы оно всегда запрашивалось
}

variable "vm_domain" {
  type        = string
  description = "Domain for VMs."
  default     = ".bevz.net" # Вы можете изменить значение по умолчанию или убрать его, чтобы оно всегда запрашивалось
}