variable "node_name" {
  type        = string
  description = "Proxmox node name"
}

variable "datastore_id" {
  type        = string
  description = "Proxmox datastore ID"
}

variable "url" {
  type        = string
  description = "Template download URL"
}

variable "content_type" {
  type        = string
  description = "Template file content type"
}
