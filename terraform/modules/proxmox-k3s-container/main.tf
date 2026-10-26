terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.71.0"
    }
  }
}

resource "proxmox_virtual_environment_container" "k3s_container" {
  node_name    = var.node_name
  vm_id        = var.vm_id
  unprivileged = var.unprivileged

  operating_system {
    template_file_id = var.template_file_id
    type             = var.os_type
  }

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_gb
  }

  features {
    nesting = var.nesting
    # Proxmox only lets root@pam set keyctl, and it only applies to unprivileged containers
    keyctl = var.unprivileged ? var.keyctl : false
  }

  network_interface {
    name = "veth0"
  }

  initialization {
    hostname = var.hostname

    user_account {
      keys     = var.ssh_public_keys
      password = var.root_password
    }

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }
}
