output "container_id" {
  value = proxmox_virtual_environment_container.k3s_container.id
}

output "vm_id" {
  value = proxmox_virtual_environment_container.k3s_container.vm_id
}

output "ip_address" {
  value = proxmox_virtual_environment_container.k3s_container.initialization[0].ip_config[0].ipv4[0].address
}
