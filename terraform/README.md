# terraform/

Infrastructure as Code for the Proxmox VE LXC container layer. Uses the `bpg/proxmox` provider.

## Files

| File | Purpose |
|------|---------|
| `terraform/main.tf` | Root module — variables, provider, template module, K3s master + workers via `for_each`, outputs |
| `terraform/.env` | **SECRET** — Proxmox API token, endpoint URL, gateway (gitignored) |
| `terraform/modules/proxmox-ubuntu-template/` | Reusable module: downloads Ubuntu LXC template from the Internet |
| `terraform/modules/proxmox-k3s-container/` | Reusable module: deploys a single K3s-ready LXC container |

## State

Run `terraform init` in this directory before first use. State is stored in `terraform.tfstate` (gitignored).

## Variables

All inputs are declared in `main.tf`:

- `proxmox_api_token` — Proxmox API token for authentication
- `proxmox_endpoint` — Proxmox API URL (e.g., `https://192.168.1.10:8006/api2/json`)
- `gateway` — Default network gateway
- `target_node` — Proxmox node name (default: `pve`)
- `ubuntu_template_url` — Ubuntu cloud image URL (Noble by default)
- `network_prefix` — IP prefix (default: `192.168.1.`)
- `network_cidr` — CIDR suffix (default: `24`)
- `container_datastore` — LXC root disk storage (default: `local-lvm`)
- `image_datastore` — Template storage (default: `local`)
- `master_vm_id` — VM ID for the master node (default: `201`)
- `worker_vm_ids` — List of VM IDs for workers (default: `[202, 203]`)

## Outputs

- `master_ip` — master container IPv4 address
- `master_vm_id` — master VM ID
- `worker_ips` — map of worker index → IP address
- `worker_vm_ids` — map of worker index → VM ID
- `kubeconfig_path` — resolved local path for the kubeconfig file

These outputs power the dynamic Ansible inventory generation in `ansible/generate-inventory.sh`.
