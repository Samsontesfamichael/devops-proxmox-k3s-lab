terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.71.0"
    }
  }
}

variable "proxmox_api_token" { type = string }
variable "proxmox_endpoint" { type = string }
variable "gateway"          { type = string }
variable "target_node" {
  type    = string
  default = "pve"
}

variable "ubuntu_template_url" {
  type    = string
   default = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64-root.tar.xz"
 }

variable "network_prefix" {
  type    = string
  default = "192.168.1."
}

variable "network_cidr" {
  type    = string
  default = "24"
}

variable "container_datastore" {
  type    = string
  default = "local-lvm"
}

variable "image_datastore" {
  type    = string
  default = "local"
}

variable "master_vm_id" {
  type    = number
  default = 201
}

variable "worker_vm_ids" {
  type    = list(number)
  default = [202, 203]
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

module "ubuntu_template" {
  source       = "./modules/proxmox-ubuntu-template"
  node_name    = var.target_node
  datastore_id = var.image_datastore
  content_type = "vztmpl"
  url          = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64-root.tar.xz"
}

module "k3s_master" {
  source           = "./modules/proxmox-k3s-container"
  node_name        = var.target_node
  vm_id            = var.master_vm_id
  hostname         = "k3s-master"
  ip_address       = "${var.network_prefix}${var.master_vm_id}/${var.network_cidr}"
  gateway          = var.gateway
  datastore_id     = var.container_datastore
  template_file_id = module.ubuntu_template.file_id
  cpu_cores        = 2
  memory_mb        = 1536
  disk_gb          = 20
  unprivileged     = false
  nesting          = true
  keyctl           = true
}

module "k3s_workers" {
  for_each = { for idx, vm_id in var.worker_vm_ids : idx => vm_id }

  source           = "./modules/proxmox-k3s-container"
  node_name        = var.target_node
  vm_id            = each.value
  hostname         = "k3s-worker-${each.key + 1}"
  ip_address       = "${var.network_prefix}${each.value}/${var.network_cidr}"
  gateway          = var.gateway
  datastore_id     = var.container_datastore
  template_file_id = module.ubuntu_template.file_id
  cpu_cores        = 1
  memory_mb        = 1024
  disk_gb          = 20
  unprivileged     = false
  nesting          = true
  keyctl           = true
}

output "master_ip" {
  value = module.k3s_master.ip_address
}

output "master_vm_id" {
  value = module.k3s_master.vm_id
}

output "worker_ips" {
  value = { for k, v in module.k3s_workers : k => v.ip_address }
}

output "worker_vm_ids" {
  value = { for k, v in module.k3s_workers : k => v.vm_id }
}

output "kubeconfig_path" {
  value = "${pathexpand("~")}/.kube/config-proxmox-k3s"
}
