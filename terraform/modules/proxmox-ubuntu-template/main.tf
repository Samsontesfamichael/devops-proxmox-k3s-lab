terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.71.0"
    }
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_template" {
  node_name             = var.node_name
  content_type          = var.content_type
  datastore_id          = var.datastore_id
  url                   = var.url
  verify                = false
  overwrite_unmanaged   = true
  overwrite             = false
}