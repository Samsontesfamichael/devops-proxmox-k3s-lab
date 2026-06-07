# devops-proxmox-k3s-lab

End-to-end enterprise DevOps lab that automates the full lifecycle:
**Terraform** provisions Proxmox LXC nodes → **Ansible** installs K3s and injects secrets → **Kubernetes** runs a multi-tier application stack.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  rebuild-cluster Orchestrator               │
│  (PowerShell / Bash / Python — all do the same 6 steps)     │
│                                                             │
│  1. terraform/.env  ──►  Terraform│                         │
│  2. terraform init/apply          │                         │
│  3. Terraform outputs             ▼                         │
│                          Dynamic Ansible Inventory          │
│  4. Ansible roles/k3s_install     │                         │
│     roles/vault_secrets           │                         │
│     roles/storage_optimize        ▼                         │
│                          K3s Cluster Live                   │
│  5. kubectl apply                                           │
│     ├─ cert-manager, metrics-server, external-secrets       │
│     └─ kubernetes-core + kubernetes-architecture            │
│  6. Enterprise apps running on K3s                          │
└─────────────────────────────────────────────────────────────┘

Physical/Cloud Resources Used
─────────────────────────────
Proxmox VE
 ├─ LXC Container 201  → k3s-master   (2 CPU, 1.5 GB RAM, 20 GB disk)
 ├─ LXC Container 202  → k3s-worker-1 (1 CPU, 1 GB RAM, 20 GB disk)
 └─ LXC Container 203  → k3s-worker-2 (1 CPU, 1 GB RAM, 20 GB disk)

K3s Cluster
 ├─ Master  → 192.168.1.201  (control-plane + etcd)
 ├─ Worker  → 192.168.1.202
 └─ Worker  → 192.168.1.203

Kubernetes Namespaces
 ├─ default
 ├─ kube-system
 ├─ local-path-storage
 ├─ monitoring
 ├─ external-secrets
 └─ enterprise-apps
```

## Quick Start

```powershell
# Prereqs: Terraform, Ansible, kubectl, WSL2 Ubuntu
# 1. Fill secrets
notepad .\terraform\.env
ansible-vault create .\ansible\group_vars\vault.yml

# 2. Run pipeline (choose one)
.\rebuild-cluster.ps1   # Windows PowerShell
bash rebuild-cluster.sh # WSL2 / Git Bash
python3 rebuild-cluster.py # Python (cross-platform)

# 3. Access cluster
kubectl config use-context docker-desktop  # local K8s
# or, if Proxmox+K3s path used:
export KUBECONFIG=~/.kube/config-proxmox-k3s
kubectl get nodes -o wide
```

## Table of Contents

1. [Terraform Layer](#terraform-layer)
2. [Ansible Layer](#ansible-layer)
3. [Kubernetes Layer](#kubernetes-layer)
4. [Orchestrators](#orchestrators)
5. [File Reference](#file-reference)

---

## Terraform Layer

### Purpose
Declares the cloud/Proxmox infrastructure using HCL. Creates 3 LXC containers with Ubuntu Noble template and assigns static IPs.

### Modules

| Module | Path | Resource Created |
|--------|------|------------------|
| `ubuntu_template` | `terraform/modules/proxmox-ubuntu-template/` | `proxmox_virtual_environment_download_file` — Ubuntu cloud image tarball |
| `k3s Workers` | `terraform/modules/proxmox-k3s-container/` | `proxmox_virtual_environment_container` — K3s-ready LXC container |

### Key Features
- `for_each` eliminates duplicate worker blocks
- Outputs `master_ip`, `worker_ips`, `worker_vm_ids` feed directly into Ansible inventory generation
- Variables for network prefix, datastores, CPU, memory, disk sizes make the config reusable

### How it works
```hcl
module "k3s_master" { ... }           # 1 master
module "k3s_workers" {
  for_each = { for idx, vm_id in var.worker_vm_ids : idx => vm_id }
  ...
}
```

---

## Ansible Layer

### Purpose
Configuration management — automates K3s installation, secret injection into Kubernetes, and storage configuration across the newly created LXC nodes.

### Roles

| Role | Path | Responsibility |
|------|------|----------------|
| `k3s_install` | `ansible/roles/k3s_install/` | Installs K3s server on master, agents on workers, captures join token |
| `vault_secrets` | `ansible/roles/vault_secrets/` | Creates `enterprise-vault` Kubernetes Secret with DB credentials |
| `storage_optimize` | `ansible/roles/storage_optimize/` | Deploys `/etc/rancher/k3s/config.yaml` with image GC thresholds, restarts k3s |

### Playbooks

| Playbook | Purpose |
|----------|---------|
| `playbook.yml` | Runs all 3 roles in sequence |
| `optimize-storage.yml` | Legacy wrapper around `storage_optimize` role |

### Idempotency
- K3s install uses `creates: /usr/local/bin/k3s` guard
- Storage config uses `copy` module with explicit content (not shell hacks)
- `vault_secrets` uses `kubernetes.core.k8s` with `state: present`

### Vault
Secrets live in `ansible/group_vars/vault.yml`, encrypted with `ansible-vault`. The `k3s_install` role distills the join token into a fact that propagates from master to workers across playbook boundaries.

---

## Kubernetes Layer

### Purpose
Application and platform manifests deployed after the cluster is live.

### Namespaces

| Namespace | Purpose |
|-----------|---------|
| `default` | Grace period |
| `kube-system` | Core K8s components |
| `local-path-storage` | Dynamic PVC provisioner |
| `monitoring` | Prometheus + Grafana |
| `external-secrets` | External Secrets Operator CRDs + deployment |
| `enterprise-apps` | All user-facing apps, databases, backups, policies |

### Manifests

| File | Component |
|------|-----------|
| `kubernetes-core/app-deploy.yaml` | Sample nginx Deployment + ClusterIP Service |
| `kubernetes-core/ingress-routing.yaml` | Traefik Ingress with TLS via cert-manager |
| `kubernetes-core/cert-manager.yaml` | selfsigned ClusterIssuer |
| `kubernetes-core/certificate.yaml` | TLS cert for `my-app.local` |
| `kubernetes-architecture/01-configmap-demo.yaml` | ConfigMap demo + alpine consumer pod |
| `kubernetes-architecture/02-secret-demo.yaml` | Secret demo pod reading `enterprise-vault` |
| `kubernetes-architecture/03-network-policy.yaml` | NetworkPolicy isolating DB tier to web pods |
| `kubernetes-architecture/04-enterprise-apps.yaml` | MySQL, Postgres, FileBrowser Deployments + PVCs + Services |
| `kubernetes-architecture/05-backup-cronjob.yaml` | CronJob dumping MySQL + Postgres to `/backups` PVC |
| `kubernetes-architecture/06-health-checks.yaml` | Deployment with liveness + readiness probes |
| `kubernetes-architecture/07-custom-app-deploy.yaml` | Node.js custom app Deployment |
| `kubernetes-architecture/08-scalable-app.yaml` | HPA-ready Deployment + Service |
| `kubernetes-architecture/09-hpa-rule.yaml` | HorizontalPodAutoscaler targeting `autoscale-app` |
| `kubernetes-architecture/10-rbac.yaml` | SA + Role + RoleBinding for app namespace |
| `kubernetes-architecture/11-external-secrets-rbac.yaml` | ClusterRole + binding for External Secrets Operator |
| `kubernetes-architecture/11.5-external-secrets-namespace.yaml` | `external-secrets` namespace |
| `kubernetes-architecture/12-external-secrets-store.yaml` | ClusterSecretStore backed by Vault |
| `kubernetes-architecture/13-external-secret.yaml` | ExternalSecret mapping Vault keys to `enterprise-vault` |
| `kubernetes-architecture/14-monitoring.yaml` | Prometheus + Grafana + ClusterRole + Service |

### Addons installed by orchestrator
- **metrics-server** — required for HPA `cpu` metrics
- **cert-manager** — TLS certificate issuance
- **external-secrets-operator** — syncs secrets from Vault into K8s Secrets
- **ClusterIssuer** (`selfsigned-cluster-issuer`) — self-signed CA for local domains

---

## Orchestrators

Three equivalent scripts run the same 6-step pipeline. Pick the one matching your shell.

| File | Platform | Invocation |
|------|----------|------------|
| `rebuild-cluster.ps1` | Windows PowerShell | `.\rebuild-cluster.ps1` |
| `rebuild-cluster.sh` | WSL2 / Git Bash / macOS / Linux | `bash rebuild-cluster.sh` |
| `rebuild-cluster.py` | Any OS with Python 3 | `python3 rebuild-cluster.py` |

### Pipeline Steps
1. Read `terraform/.env` for Proxmox credentials
2. `terraform destroy -auto-approve` (clean slate)
3. `terraform apply -auto-approve`
4. Generate `ansible/hosts.ini` dynamically from Terraform outputs
5. Run Ansible playbooks (`playbook.yml`, `optimize-storage.yml`)
6. Install addons, then apply `kubernetes-core/` and `kubernetes-architecture/`

---

## File Reference

### Root

| File | Purpose |
|------|---------|
| `README.md` | This documentation |
| `.gitignore` | Prevents committing `.env`, `.tfstate`, vault files, `.kube/` |
| `rebuild-cluster.ps1` | Windows PowerShell orchestrator |
| `rebuild-cluster.sh` | Bash orchestrator |
| `rebuild-cluster.py` | Python orchestrator |
| `install-addons.sh` | Bash helper installing metrics-server, cert-manager, external-secrets |

### Terraform

| File | Purpose |
|------|---------|
| `terraform/main.tf` | Root config — variables, provider, modules, outputs |
| `terraform/.env` | **SECRET** — `TF_VAR_proxmox_api_token`, `TF_VAR_proxmox_endpoint`, `TF_VAR_gateway` |
| `terraform/modules/proxmox-ubuntu-template/main.tf` | Downloads Ubuntu LXC template |
| `terraform/modules/proxmox-ubuntu-template/variables.tf` | Input vars for template module |
| `terraform/modules/proxmox-ubuntu-template/outputs.tf` | Exposes `file_id` |
| `terraform/modules/proxmox-k3s-container/main.tf` | Reusable K3s LXC container resource |
| `terraform/modules/proxmox-k3s-container/variables.tf` | Input vars for container module |
| `terraform/modules/proxmox-k3s-container/outputs.tf` | Exposes `container_id`, `vm_id`, `ip_address` |

### Ansible

| File | Purpose |
|------|---------|
| `ansible/ansible.cfg` | Defaults: inventory path, privilege escalation, roles/collections paths |
| `ansible/requirements.yml` | Declares `kubernetes.core` collection |
| `ansible/playbook.yml` | Primary playbook — runs `k3s_install`, `vault_secrets`, `storage_optimize` |
| `ansible/optimize-storage.yml` | Legacy playbook calling `storage_optimize` role |
| `ansible/hosts.ini` | Inventory template (overwritten by orchestrator at runtime) |
| `ansible/generate-inventory.sh` | Bash script parsing Terraform outputs into `hosts.ini` |
| `ansible/group_vars/vault.yml` | **ENCRYPTED** — MySQL/Postgres/FileBrowser passwords |
| `ansible/roles/k3s_install/tasks/main.yml` | K3s server/agent install tasks |
| `ansible/roles/vault_secrets/tasks/main.yml` | Creates `enterprise-vault` K8s Secret |
| `ansible/roles/storage_optimize/tasks/main.yml` | Image GC config + k3s restart |
| `ansible/roles/storage_optimize/handlers/main.yml` | Restart k3s handler |

### Kubernetes

| File | Purpose |
|------|---------|
| `kubernetes-core/app-deploy.yaml` | nginx sample app Deployment + Service |
| `kubernetes-core/ingress-routing.yaml` | Traefik Ingress with TLS for `my-app.local` |
| `kubernetes-core/cert-manager.yaml` | `selfsigned-cluster-issuer` ClusterIssuer |
| `kubernetes-core/certificate.yaml` | Certificate resource for local domains |
| `kubernetes-architecture/01-configmap-demo.yaml` | ConfigMap + consumer pod |
| `kubernetes-architecture/02-secret-demo.yaml` | Secret consumer pod |
| `kubernetes-architecture/03-network-policy.yaml` | DB tier network isolation |
| `kubernetes-architecture/04-enterprise-apps.yaml` | MySQL + Postgres + FileBrowser + Services |
| `kubernetes-architecture/05-backup-cronjob.yaml` | Nightly DB backups CronJob |
| `kubernetes-architecture/06-health-checks.yaml` | Liveness/readiness probe demo |
| `kubernetes-architecture/07-custom-app-deploy.yaml` | Custom Node.js app |
| `kubernetes-architecture/08-scalable-app.yaml` | HPA-capable Deployment + Service |
| `kubernetes-architecture/09-hpa-rule.yaml` | HorizontalPodAutoscaler |
| `kubernetes-architecture/10-rbac.yaml` | SA + Role + RoleBinding |
| `kubernetes-architecture/11-external-secrets-rbac.yaml` | Operator ClusterRole + binding |
| `kubernetes-architecture/11.5-external-secrets-namespace.yaml` | `external-secrets` namespace |
| `kubernetes-architecture/12-external-secrets-store.yaml` | ClusterSecretStore (Vault backend) |
| `kubernetes-architecture/13-external-secret.yaml` | ExternalSecret mapping Vault → K8s |
| `kubernetes-architecture/14-monitoring.yaml` | Prometheus + Grafana |
| `kubernetes-architecture/.env` | **DEPRECATED** — secrets now in Ansible Vault |

---

## Process Walkthrough

### Phase 1: Infrastructure Provisioning (Terraform)
1. `terraform init` downloads the `bpg/proxmox` provider
2. `terraform apply`:
   - Downloads Ubuntu Noble LXC template to Proxmox
   - Creates 3 LXC containers with static IPs
   - Exposes outputs consumed by next phases
3. State saved to `terraform.tfstate`

### Phase 2: Configuration Management (Ansible)
1. Orchestrator generates `hosts.ini` from Terraform outputs (`master_ip`, `worker_ips`)
2. `playbook.yml` runs across `k3s_cluster`:
   - `k3s_install` installs K3s server on master, joins workers via captured join token
   - `vault_secrets` creates `enterprise-vault` Kubernetes Secret on the live cluster
   - `storage_optimize` sets image GC thresholds and restarts k3s
3. `optimize-storage.yml` applies the same storage config again (idempotent)

### Phase 3: Platform Addons (kubectl)
1. Install `metrics-server` (HPA metrics source)
2. Install `cert-manager` (TLS issuance)
3. Install `external-secrets-operator` (Vault → K8s Secret sync)

### Phase 4: Application Deployment (kubectl)
1. `kubernetes-core/` — foundational routing, ingress, TLS
2. `kubernetes-architecture/` — all enterprise apps, databases, backups, policies, monitoring

---

## Resource Sizing

| Component | CPU | RAM | Disk |
|-----------|-----|-----|------|
| k3s-master | 2 cores | 1536 MB | 20 GB |
| k3s-worker-1 | 1 core | 1024 MB | 20 GB |
| k3s-worker-2 | 1 core | 1024 MB | 20 GB |

Total K3s cluster footprint: **4 cores / 3.5 GB RAM / 60 GB disk**

---

## Security Model

- **Terraform `.env`** — API token injected via environment; excluded by `.gitignore`
- **Ansible Vault** — DB passwords encrypted at rest; decrypted at runtime by vault password
- **Kubernetes Secrets** — created by `kubectl create secret`/`kubernetes.core.k8s` with `no_log: yes`
- **Workers vs Master** — workers only receive `K3S_TOKEN`; no other secrets touch them
- **SSH/Root** — containers accept `ansible_user=root`; configure SSH keys for production

## Retry, Wait, and Timeout Handling

The orchestrators don’t fail-fast. Every network-bound or cluster-stability step is wrapped in retry and readiness polling.

### Retry behavior

| Step | Default retries | Default delay |
|------|----------------|---------------|
| `terraform destroy` | 3 | 30s |
| `terraform apply` | 3 | 30s |
| `generate-inventory` | 3 | 30s |
| `ansible-playbook` | 3 | 30s |
| `kubectl apply` (addons) | 3 | 30s |
| `kubectl apply` (apps) | 3 | 30s |

Configure via environment variables:
```bash
export RETRY_COUNT=5
export RETRY_DELAY=60
python3 rebuild-cluster.py
```

### Readiness gates

Between Ansible and addon installation, the pipeline actively waits for the K3s cluster to stabilize:

| Gate | Timeout | Check |
|------|---------|-------|
| `kube-system` pods Ready | 600s | `kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=600s` |
| All nodes Ready | 600s | `kubectl get nodes --no-headers | grep -v ' Ready '` |

### Why this matters

- **Slow Proxmox downloads** — Ubuntu template over the public Internet can take minutes. `terraform apply` is retried automatically.
- **Late K3s node joins** — workers may not appear in `kubectl get nodes` immediately after Ansible finishes. The readiness gate prevents addons from installing against a half-formed API server.
- **Transient `kubectl apply` failures** — If the API server restarts or etcd flakes mid-apply, the retry loop re-applies instead of aborting.

### Implementation

| Script | Retry helper | Readiness implementation |
|--------|-------------|--------------------------|
| `rebuild-cluster.ps1` | `Retry-Command` function | `Wait-ClusterReady` poller with deadline |
| `rebuild-cluster.sh` | `retry()` function | `wait_ready()` polling loop |
| `rebuild-cluster.py` | `retry()` wrapper | `wait_cluster_ready()` timeout loop |

---

## Troubleshooting

| Symptom | Cause | Fix |
|----------|-------|-----|
| `provider registry.terraform.io does not have hashicorp/proxmox` | Module missing `required_providers` block | Ensure module `main.tf` declares `source = "bpg/proxmox"` |
| `ansible-inventory Unable to parse hosts.ini` | Escaped brackets in inventory | Use unescaped `[section]` in `hosts.ini` |
| `kubectl apply ingress never becomes ready` | Missing Traefik/cert-manager/metrics-server | Run `rebuild-cluster.ps1` step 5 |
| `HPA not scaling` | `metrics-server` not installed | `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` |
| `vault_secrets role fails` | `kubernetes` Python package missing | `pip3 install kubernetes` |
| `terraform init fails with provider mismatch` | `.terraform/` stale after edits | `terraform init -upgrade` |
