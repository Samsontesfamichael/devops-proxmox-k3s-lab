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
  description = "Template file ID"
  default     = ""
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
  description = "Enable nesting"
  default     = false
}

variable "keyctl" {
  type        = bool
  description = "Enable keyctl"
  default     = false
}
