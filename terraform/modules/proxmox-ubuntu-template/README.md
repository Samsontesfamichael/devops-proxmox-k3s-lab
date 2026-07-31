# terraform/modules/proxmox-ubuntu-template/

Reusable Terraform module that downloads an Ubuntu LXC template from the Internet into a Proxmox datastore.

## Files

| File | Purpose |
|------|---------|
| `main.tf` | `proxmox_virtual_environment_download_file` resource definition |
| `variables.tf` | Input variable declarations (`node_name`, `datastore_id`, `url`, `content_type`) |
| `outputs.tf` | Outputs the downloaded `file_id` for use by parent modules |

## Inputs

- `node_name` — Proxmox node name
- `datastore_id` — Target datastore (e.g., `local`)
- `url` — Full URL to the Ubuntu cloud image tarball
- `content_type` — Set to `vztmpl` for LXC templates

## Outputs

- `file_id` — Proxmox file ID passed to `template_file_id` in container modules

## Usage

```hcl
module "ubuntu_template" {
  source      = "./modules/proxmox-ubuntu-template"
  node_name   = "pve"
  datastore_id = "local"
  url         = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64-root.tar.xz"
  content_type = "vztmpl"
}
```

## Notes

- The download happens during `terraform apply`. Internet access is required.
- Changing `url` forces a re-download.
