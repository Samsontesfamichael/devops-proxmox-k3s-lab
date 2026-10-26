variable "node_name" {
  type        = string
  description = "Proxmox node name"
}

variable "vm_id" {
  type        = number
  description = "Container VM ID"
}

variable "unprivileged" {
  type        = bool
  description = "Whether the container is unprivileged"
  default     = false
}

variable "template_file_id" {
  type        = string
  description = "LXC template file ID, e.g. local:vztmpl/ubuntu-22.04.tar.xz"
}

variable "os_type" {
  type        = string
  description = "Container OS type"
  default     = "ubuntu"
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys authorized for root"
  default     = []
}

variable "root_password" {
  type        = string
  description = "Root password (optional; SSH keys are preferred)"
  default     = null
  sensitive   = true
}

variable "hostname" {
  type        = string
  description = "Container hostname"
}

variable "ip_address" {
  type        = string
  description = "IPv4 address with CIDR"
}

variable "gateway" {
  type        = string
  description = "IPv4 gateway"
}

variable "datastore_id" {
  type        = string
  description = "Container disk datastore"
}

variable "cpu_cores" {
  type        = number
  description = "CPU cores"
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB"
}

variable "disk_gb" {
  type        = number
  description = "Disk size in GB"
}

variable "nesting" {
  type        = bool
  description = "Enable nesting (unprivileged containers only)"
  default     = false
}

variable "keyctl" {
  type        = bool
  description = "Enable keyctl (unprivileged containers only)"
  default     = false
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers for the container"
  default     = ["8.8.8.8", "8.8.4.4"]
}
