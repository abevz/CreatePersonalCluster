variable "environment" {
  type        = string
  description = "Тип дистрибутива ОС для развертываемого кластера (e.g., debian, ubuntu, rocky). Используется для именования ресурсов и ключа состояния бэкенда."
}

variable "os_type" {
  type        = string
  description = "Тип ОС для шаблона: debian, ubuntu, rocky. Обычно устанавливается через соответствующий .tfvars файл окружения."
}

variable "pm_node" {
  type        = string
  description = "Proxmox node name where VMs will be created."
  # Example: default = "homelab"
}

variable "dns_servers" {
  type        = list(string)
  description = "List of DNS servers for VM initialization."
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