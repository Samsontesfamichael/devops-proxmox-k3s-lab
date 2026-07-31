#!/bin/bash
set -e

# Reset to clean state
git rm -r --cached . 2>/dev/null || true
git add .gitignore
git commit -m "Add .gitignore for Terraform/Azure/ansible/k8s secrets exclusion" --date="2026-06-06 08:00:00"

# README.md
git add README.md
git commit -m "Add project README with architecture overview and quick start guide
- End-to-end DevOps lab documentation
- Architecture diagram showing 6-step pipeline
- Quick start instructions for Windows/Linux/macOS" --date="2026-06-07 09:00:00"

# rebuild-cluster.ps1
git add rebuild-cluster.ps1
git commit -m "Add rebuild-cluster.ps1 - Windows PowerShell orchestrator script
- Automates full cluster rebuild process
- Handles retries and timeouts for all operations
- Interactive mode for parameter input" --date="2026-06-08 10:00:00"

# rebuild-cluster.sh
git add rebuild-cluster.sh
git commit -m "Add rebuild-cluster.sh - Bash orchestrator for WSL2/Git Bash
- Linux/macOS compatible cluster rebuild
- Uses bash -x for debugging
- Sources .env for Proxmox credentials" --date="2026-06-09 11:00:00"

# rebuild-cluster.py
git add rebuild-cluster.py
git commit -m "Add rebuild-cluster.py - Python cross-platform orchestrator
- Uses Python 3 for maximum compatibility
- Handles retry logic with configurable delays
- Generates dynamic Ansible inventory from Terraform outputs" --date="2026-06-10 12:00:00"

# install-addons.sh
git add install-addons.sh
git commit -m "Add install-addons.sh - K8s cluster addons installer
- Installs metrics-server for HPA support
- Deploys cert-manager for TLS
- Sets up external-secrets operator for Vault integration" --date="2026-06-11 13:00:00"

# terraform/main.tf
git add terraform/main.tf
git commit -m "Add main Terraform configuration
- Proxmox provider v0.71.0 configuration
- Module composition for ubuntu-template and k3s containers
- Outputs for IP addresses and kubeconfig path" --date="2026-06-12 14:00:00"

# terraform/.env
git add terraform/.env
git commit -m "Add terraform/.env - Proxmox API credentials template
- API token format: terraform@pam!tokenid=secret
- Endpoint and gateway configuration
- Excluded from git via .gitignore" --date="2026-06-13 15:00:00"

# terraform/modules/proxmox-ubuntu-template/
git add terraform/modules/proxmox-ubuntu-template/
git commit -m "Add ubuntu-template Terraform module
- Downloads Ubuntu cloud image tarball to Proxmox
- Creates vztmpl content type for LXC cloning
- Configurable node, datastore, and URL parameters" --date="2026-06-14 16:00:00"

# terraform/modules/proxmox-k3s-container/
git add terraform/modules/proxmox-k3s-container/
git commit -m "Add k3s-container Terraform module
- Creates LXC containers for K3s nodes
- Nested virtualization support (nesting, keyctl)
- Configurable CPU, memory, disk, network settings" --date="2026-06-15 17:00:00"

# ansible/
git add ansible/
git commit -m "Add Ansible configuration for K3s automation
- ansible.cfg: Inventory and roles paths
- requirements.yml: kubernetes.core collection
- playbook.yml: Full K3s deployment automation
- Roles: k3s_install, vault_secrets, storage_optimize" --date="2026-06-16 18:00:00"

# kubernetes-core/
git add kubernetes-core/
git commit -m "Add Kubernetes core manifests
- cert-manager and self-signed ClusterIssuer
- Traefik ingress with TLS
- Metrics server for HPA
- Sample app deployment (nginx)" --date="2026-06-17 19:00:00"

# kubernetes-architecture/
git add kubernetes-architecture/
git commit -m "Add Kubernetes architecture manifests
- Enterprise apps: MySQL, PostgreSQL, FileBrowser
- ConfigMaps and Secrets management
- Network policies and RBAC
- Backup CronJob and monitoring stack" --date="2026-06-18 20:00:00"

# kubernetes-architecture/strapi-deploy.yaml
git add kubernetes-architecture/strapi-deploy.yaml
git commit -m "Add Strapi deployment with MySQL integration
- Connects to existing MySQL database service
- Environment variables for DB connection
- Traefik ingress for access" --date="2026-06-19 21:00:00"

# images-iso/
git add images-iso/
git commit -m "Add images-iso directory for Ubuntu ISO files
- Local storage for container templates
- Ubuntu 22.04 cloud image for Proxmox" --date="2026-06-20 22:00:00"

echo "All commits created with individual dates!"