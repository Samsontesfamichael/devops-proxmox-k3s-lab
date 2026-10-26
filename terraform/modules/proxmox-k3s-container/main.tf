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

  # Proxmox only lets root@pam set feature flags on privileged containers, so an
  # API token can't; set them on the host as root after creation instead
  dynamic "features" {
    for_each = var.unprivileged ? [1] : []
    content {
      nesting = var.nesting
      keyctl  = var.keyctl
    }
  }

  network_interface {
    name = "veth0"
  }

  initialization {
    hostname = var.hostname

    # Without this the container copies the host's resolv.conf, whose
    # 127.0.0.1 entry has nothing listening inside the container
    dns {
      servers = var.dns_servers
    }

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

  lifecycle {
    ignore_changes = [features]
  }
}
