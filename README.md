# devops-proxmox-k3s-lab

A home-lab that builds a 3-node Kubernetes (K3s) cluster on Proxmox VE and runs
a small multi-tier app stack on it, using infrastructure as code end to end:

**Terraform** creates the LXC containers on Proxmox → **Ansible** installs K3s
and injects secrets → **Kubernetes** manifests deploy the apps, monitoring and
LAN-only HTTPS access.

> **Status:** running on a single Proxmox VE 9.1 host. The cluster was built
> with the step-by-step path in [Build the lab](#build-the-lab). The one-shot
> `rebuild-cluster` scripts still have known bugs. See
> [Known issues](#known-issues).

---

## What's running

| App | URL (LAN only) | Login |
|---|---|---|
| Sample web app (nginx) | https://my-app.local | none |
| File Browser | https://files.my-app.local | `admin` + vault password |
| Grafana | https://grafana.my-app.local | `admin` + `grafana-admin` secret |
| Prometheus | https://prometheus.my-app.local | `admin` + `prometheus-basic-auth` secret |
| MySQL 8.0 | internal only | `root` / `dev_user` + vault passwords |
| PostgreSQL 15 | internal only | `postgres_user` + vault password |

Plus: a ConfigMap demo, a Secret demo, a self-healing web app with probes, a
Node.js app, an autoscaling app with an HPA, RBAC, a NetworkPolicy and a
nightly database backup CronJob. See [Credentials](#credentials) for where
each password lives.

---

## Architecture

```
                      Your PC (192.168.1.x, LAN only)
                                  │  HTTPS 443 (HTTP 80 → redirect)
                                  ▼
┌──────────────────────── Proxmox VE 9.1 host (192.168.1.220) ─────────────────────────┐
│                                                                                       │
│  LXC 201  k3s-master  192.168.1.201   2 vCPU · 3 GB RAM · 20 GB                       │
│    ├─ K3s server (control plane, SQLite datastore)                                    │
│    └─ Traefik on host ports 80/443 ── LAN allow-list ── lab CA certificates           │
│                                                                                       │
│  LXC 202  k3s-worker-1  192.168.1.202   1 vCPU · 1 GB RAM · 20 GB   (K3s agent)       │
│  LXC 203  k3s-worker-2  192.168.1.203   1 vCPU · 1 GB RAM · 20 GB   (K3s agent)       │
│                                                                                       │
│  All 3: Ubuntu 22.04, privileged LXC, nesting on, DNS 192.168.1.1 + 8.8.8.8           │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

### Namespaces

| Namespace | Contents |
|---|---|
| `enterprise-apps` | Web apps, MySQL, Postgres, File Browser, demos, backups, HPA, RBAC, NetworkPolicy |
| `monitoring` | Prometheus, Grafana |
| `cert-manager` | cert-manager and the lab root CA |
| `kube-system` | K3s components: CoreDNS, Traefik, metrics-server, local-path storage |
| `external-secrets` | Namespace and RBAC only (operator not installed, see [Known issues](#known-issues)) |

---

## Repository layout

```
terraform/
  main.tf                               # provider, variables, 3 containers, outputs
  modules/proxmox-ubuntu-template/      # downloads the Ubuntu 22.04 LXC template
  modules/proxmox-k3s-container/        # one K3s-ready LXC container
ansible/
  playbook.yml                          # K3s install → kubeconfig → secrets → storage
  hosts.ini                             # inventory (master + 2 workers)
  roles/k3s_install/                    # K3s server/agents, /dev/kmsg fix, join token
  roles/vault_secrets/                  # creates the enterprise-vault Secret
  roles/storage_optimize/               # kubelet image garbage-collection thresholds
  group_vars/vault.yml                  # app passwords (git-ignored, see Security)
kubernetes-core/                        # git-ignored: sample app, issuer, cert, ingress
kubernetes-architecture/                # 01–15: apps, policies, monitoring, secure access
rebuild-cluster.{sh,ps1,py}             # one-shot orchestrators (see Known issues)
install-addons.sh                       # add-on installer used by rebuild-cluster.sh
proxmox-user-create.sh                  # example Proxmox API user/role/token setup
KUBECTL-PRACTICE.md                     # beginner kubectl exercises for this cluster
```

---

## Prerequisites

- A **Proxmox VE** host with about 6 GB of free RAM and storage pools `local`
  (templates) and `local-lvm` (container disks).
- On your PC: **Terraform** and **kubectl**, plus **WSL2 Ubuntu** with
  **Ansible** (Ansible doesn't run natively on Windows).
- An SSH key without a passphrase (automation can't type one), for example
  `~/.ssh/id_ed25519_k3s`.

---

## Build the lab

This is the path the running lab was built with. Commands marked
**(Proxmox shell)** run as root on the Proxmox host (web UI → node → Shell, or
`ssh root@<proxmox>`).

### 1. One-time Proxmox setup

**SSH key for root** (Proxmox shell). Lets your PC, and Terraform's containers,
use your key:
```bash
echo 'ssh-ed25519 AAAA... you@pc' >> /root/.ssh/authorized_keys
```

**API token for Terraform** (Proxmox shell). The token needs permissions both
on its user and on the token itself. `Administrator` is the simple choice for a
lab:
```bash
pveum user add terraform@pam
pveum user token add terraform@pam terraform --privsep 0
pveum acl modify / --roles Administrator --users terraform@pam --tokens 'terraform@pam!terraform'
```
`proxmox-user-create.sh` shows a narrower custom role, for a separate
`terraform1@pve` user.

**`terraform/.env`** (git-ignored):
```bash
TF_VAR_proxmox_api_token=terraform@pam!terraform=<token-secret>
TF_VAR_proxmox_endpoint=https://<proxmox-ip>:8006/
TF_VAR_gateway=192.168.1.1
```

### 2. Create the containers (Terraform)

```powershell
cd terraform
Get-Content .env | ForEach-Object { $k,$v = $_ -split '=',2; Set-Item "env:$k" $v }
terraform init
terraform apply
```
This downloads the Ubuntu 22.04 template, then creates containers 201–203 with
static IPs, your SSH public key (`ssh_public_key_file`, default
`~/.ssh/id_ed25519_k3s.pub`) and explicit DNS servers.

### 3. Container settings K3s needs (Proxmox shell, root only)

Proxmox only lets `root@pam` set feature flags and raw LXC options on
privileged containers. An API token can't, so Terraform leaves these out:
```bash
for id in 201 202 203; do
  pct set $id --features nesting=1
  printf 'lxc.apparmor.profile: unconfined\nlxc.cgroup2.devices.allow: a\nlxc.cap.drop:\nlxc.mount.auto: "proc:rw sys:rw"\n' >> /etc/pve/lxc/$id.conf
  pct reboot $id
done
```
The warning `explicitly configured lxc.apparmor.profile overrides ... nesting`
is expected.

> These settings remove AppArmor confinement and give the containers access to
> host devices. That's normal for K3s in privileged LXC on a home lab, but it
> weakens isolation from the Proxmox host.

### 4. Install K3s (Ansible, from WSL)

Create `ansible/group_vars/vault.yml` with the 4 app passwords:
```yaml
vault_mysql_root_password: "..."
vault_mysql_password: "..."
vault_postgres_password: "..."
vault_filebrowser_password: "..."
```
Then, in WSL, run from the repo:
```bash
cp /mnt/c/Users/<you>/.ssh/id_ed25519_k3s* ~/.ssh/ && chmod 600 ~/.ssh/id_ed25519_k3s
cd ansible
ansible-galaxy collection install -r requirements.yml
ANSIBLE_CONFIG=$PWD/ansible.cfg ansible-playbook -i hosts.ini playbook.yml --private-key ~/.ssh/id_ed25519_k3s
```
`ANSIBLE_CONFIG` is needed because Ansible ignores `ansible.cfg` in a
world-writable directory, which every `/mnt/c` path is.

`playbook.yml`:
- installs K3s on the master and joins both workers
- copies the kubeconfig to `~/.kube/config-proxmox-k3s` (with the master's IP)
- creates the `enterprise-vault` Secret
- sets the image garbage-collection thresholds

### 5. Install cert-manager

```bash
export KUBECONFIG=~/.kube/config-proxmox-k3s     # PowerShell: $env:KUBECONFIG = "$env:USERPROFILE\.kube\config-proxmox-k3s"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl -n cert-manager rollout status deploy --timeout=600s
```
Don't install the upstream metrics-server: K3s already ships one.

### 6. Deploy the apps

```bash
kubectl apply -f kubernetes-core/          # local only, see Known issues
for f in kubernetes-architecture/0*.yaml kubernetes-architecture/10-rbac.yaml \
         kubernetes-architecture/11.5-external-secrets-namespace.yaml \
         kubernetes-architecture/11-external-secrets-rbac.yaml \
         kubernetes-architecture/14-monitoring.yaml; do kubectl apply -f "$f"; done

# 15-secure-access.yaml needs this secret first (keeps the password out of git)
kubectl create secret generic prometheus-basic-auth -n monitoring \
  --type=kubernetes.io/basic-auth \
  --from-literal=username=admin --from-literal=password='<choose one>'
kubectl apply -f kubernetes-architecture/15-secure-access.yaml
```
`12-external-secrets-store.yaml` and `13-external-secret.yaml` are left out on
purpose (see [Known issues](#known-issues)). Images download slowly on a slow
link; watch progress with `kubectl get pods -A -w`.

### 7. Use it from your PC

1. Add to `C:\Windows\System32\drivers\etc\hosts` (edit as Administrator):
   ```
   192.168.1.201  my-app.local  files.my-app.local  grafana.my-app.local  prometheus.my-app.local
   ```
2. Export the lab CA and trust it once, so the browser shows no warning:
   ```powershell
   kubectl get secret lab-root-ca -n cert-manager -o jsonpath='{.data.ca\.crt}' | Out-File -Encoding ascii lab-root-ca.b64
   certutil -decode lab-root-ca.b64 lab-root-ca.crt
   Import-Certificate -FilePath .\lab-root-ca.crt -CertStoreLocation Cert:\CurrentUser\Root
   ```
   Restart Chrome or Edge completely afterwards (`chrome://restart`). Firefox
   keeps its own certificate list.

---

## Terraform layer

| Module | Creates |
|---|---|
| `proxmox-ubuntu-template` | `proxmox_virtual_environment_download_file`: Ubuntu 22.04 root tarball as an LXC template |
| `proxmox-k3s-container` | `proxmox_virtual_environment_container`: one container (used once for the master, `for_each` for the workers) |

Provider: `bpg/proxmox` 0.71.0. Outputs: `master_ip`, `master_vm_id`,
`worker_ips`, `worker_vm_ids`, `kubeconfig_path`.

Design notes:
- **Template:** containers are created from it with `operating_system {}`, not
  `clone`.
- **Feature flags:** only sent for *unprivileged* containers, and Terraform
  ignores later changes to them, because only `root@pam` can set them on
  privileged ones (step 3).
- **SSH and DNS:** `user_account.keys` installs your SSH key. `dns.servers`
  stops containers inheriting the Proxmox host's `127.0.0.1` resolver, which
  broke image pulls.
- **Restarts:** the provider **restarts a container** when some settings change
  (DNS, memory). Plan changes for a time when a short outage is fine.

---

## Ansible layer

| Role | What it does |
|---|---|
| `k3s_install` | Installs packages and the Python `kubernetes` client, installs the K3s server and agents, and passes the join token from master to workers. It also adds a `systemd-tmpfiles` rule that recreates `/dev/kmsg` at every boot: the kubelet won't start in LXC without it, and `/dev` is wiped on each container restart. |
| `vault_secrets` | Creates namespace `enterprise-apps` and the `enterprise-vault` Secret from `group_vars/vault.yml` (loaded with `vars_files`) |
| `storage_optimize` | Writes `/etc/rancher/k3s/config.yaml` with image GC thresholds 65% / 50% and restarts K3s through a handler |

Idempotency: K3s installs are guarded with `creates:`, and the secret uses
`kubernetes.core.k8s` with `state: present`.

---

## Kubernetes layer

| File | Contents |
|---|---|
| `kubernetes-core/app-deploy.yaml` | `sample-web-app` (nginx, 2 replicas) + Service `web-entrypoint` |
| `kubernetes-core/cert-manager.yaml` | ClusterIssuer `selfsigned-cluster-issuer` (used to sign the lab CA) |
| `kubernetes-core/certificate.yaml` | Certificate for `my-app.local` from `lab-ca-issuer` |
| `kubernetes-core/ingress-routing.yaml` | HTTPS Ingress for `my-app.local` |
| `01-configmap-demo.yaml` | ConfigMap `app-config` + consumer Deployment |
| `02-secret-demo.yaml` | Deployment reading `enterprise-vault` |
| `03-network-policy.yaml` | Only `web-test` and `config-test` pods may reach MySQL on 3306 |
| `04-enterprise-apps.yaml` | MySQL 8.0 and Postgres 15 (10 Gi volume each); File Browser with a persistent database and its admin password set from the vault at every start; HTTPS Ingress `files.my-app.local` |
| `05-backup-cronjob.yaml` | `database-nightly-backup` at 02:00 into a 20 Gi volume |
| `06-health-checks.yaml` | `self-healing-web` (2 replicas) with liveness and readiness probes |
| `07-custom-app-deploy.yaml` | Node.js `corporate-custom-app` |
| `08-scalable-app.yaml` | `autoscale-app` + Service `autoscale-service` |
| `09-hpa-rule.yaml` | HPA `web-autoscaler`: 1–4 replicas at 50% CPU |
| `10-rbac.yaml` | ServiceAccount, Role and RoleBinding in `enterprise-apps` |
| `11-external-secrets-rbac.yaml` / `11.5-...namespace.yaml` | RBAC and namespace for External Secrets |
| `12-external-secrets-store.yaml` / `13-external-secret.yaml` | **Not applied.** A ClusterSecretStore for a HashiCorp Vault server that doesn't exist |
| `14-monitoring.yaml` | Prometheus v2.47 (15 s scrape, 15 d retention) + Grafana 10.2 |
| `15-secure-access.yaml` | Lab root CA + `lab-ca-issuer`; Traefik settings (host ports, LAN allow-list, HTTP→HTTPS); Grafana and Prometheus Ingresses; Prometheus basic auth |

Built into K3s, not installed separately: **Traefik** (ingress), **CoreDNS**,
**metrics-server** (HPA metrics) and **local-path-provisioner** (volumes).
Installed in step 5: **cert-manager**.

---

## Security

- **Not on the internet.** Nothing is port-forwarded. Traefik is the only entry
  point (k3s-master ports 80 and 443), and it only accepts clients from
  `192.168.1.0/24`. Traefik binds the host ports directly, instead of going
  through K3s's ServiceLB, so it sees real client IPs. For remote access, use a
  VPN (for example Tailscale) rather than opening router ports.
- **HTTPS everywhere.** HTTP redirects to HTTPS. Certificates come from a
  private lab CA (`lab-root-ca`, 10 years) that you trust once on your PC.
- **Every web app has a login.** Prometheus has none of its own, so Traefik
  adds basic auth.
- **Internal-only services.** The databases, Grafana and Prometheus are
  ClusterIP Services, reachable only inside the cluster or through the
  Ingress. A NetworkPolicy limits who can reach MySQL.
- **Secrets stay out of git.** `terraform/.env`, `group_vars/vault.yml`,
  `*.tfstate` and kubeconfigs are git-ignored. The Prometheus password exists
  only as a Kubernetes Secret.
- **SSH key logins only.** Containers allow root login by SSH key; no root
  password is set.
- **Caveats:**
  - `group_vars/vault.yml` is currently **plain text**, not encrypted. To
    encrypt it, run `ansible-vault encrypt group_vars/vault.yml`, then add
    `--ask-vault-pass` to `ansible-playbook`.
  - Grafana's admin password is in plain text in `14-monitoring.yaml`. Change it
    after the first login, or move it to the vault.
  - The privileged LXC settings in step 3 weaken host isolation.

## Credentials

No values here, only where to find them (PowerShell):
```powershell
function Show-Secret($ns, $name, $key) { $b = kubectl get secret $name -n $ns -o jsonpath="{.data.$key}"; [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) }
Show-Secret monitoring grafana-admin password                     # Grafana, user admin
Show-Secret monitoring prometheus-basic-auth password             # Prometheus, user admin
Show-Secret enterprise-apps enterprise-vault FILEBROWSER_PASSWORD # File Browser, user admin
Show-Secret enterprise-apps enterprise-vault MYSQL_ROOT_PASSWORD  # MySQL root
Show-Secret enterprise-apps enterprise-vault MYSQL_PASSWORD       # MySQL dev_user (db training_db)
Show-Secret enterprise-apps enterprise-vault POSTGRES_PASSWORD    # Postgres postgres_user (db company_db)
```
To change the File Browser password, edit `vault.yml`, re-run the playbook,
then `kubectl rollout restart deploy/filebrowser -n enterprise-apps`.

---

## Resource sizing

| Container | vCPU | RAM | Disk |
|---|---|---|---|
| k3s-master (201) | 2 | 3072 MB | 20 GB |
| k3s-worker-1 (202) | 1 | 1024 MB | 20 GB |
| k3s-worker-2 (203) | 1 | 1024 MB | 20 GB |
| **Total** | **4** | **5 GB** | **60 GB** |

The master ran out of memory at 1.5 GB (the API server stalled), so it now has
3 GB. With all apps running, the master uses about 75% of its RAM and the
workers 45–60%.

---

## Orchestrators

`rebuild-cluster.sh`, `rebuild-cluster.ps1` and `rebuild-cluster.py` automate
the pipeline in 6 steps:
1. Destroy the old infrastructure (`terraform destroy`)
2. Create new containers (`terraform apply`)
3. Write `hosts.ini` from Terraform outputs
4. Run the Ansible playbooks
5. Install the add-ons
6. Apply `kubernetes-core/` and `kubernetes-architecture/`

Between steps 4 and 5, they wait for the nodes and `kube-system` pods to be
Ready. Retries default to 3 attempts, 30 s apart; set `RETRY_COUNT` and
`RETRY_DELAY` to change that.

> ⚠️ **Step 1 deletes the whole cluster and its data.** And the scripts don't
> currently work end to end; see below. Use [Build the lab](#build-the-lab)
> until they're fixed.

---

## Known issues

| Issue | Effect |
|---|---|
| The inventory step in all 3 orchestrators (and `generate-inventory.sh`) writes `192.168.1.201/24` (with the CIDR) and no `ansible_host` | Ansible can't connect, or workers can't find the master. `generate-inventory.sh` also never passes its JSON arguments to Python. |
| None of the orchestrators do step 3 (root-only LXC settings) | K3s won't start on freshly created containers |
| `rebuild-cluster.ps1` calls `install-addons.ps1`, which doesn't exist; it also runs Ansible natively on Windows | The PowerShell orchestrator can't complete |
| Add-on steps install the upstream metrics-server, and the external-secrets operator from `deploy/all.yaml` (now 404) | A second, conflicting metrics-server; the operator install fails |
| Files `12`/`13` need a HashiCorp Vault server at `192.168.1.201:8200` | Not deployed; applying `13` would try to take over `enterprise-vault` |
| `kubernetes-core/*.yaml` is in `.gitignore` | A fresh clone is missing the sample app, issuer, certificate and its Ingress |
| `ansible/optimize-storage.yml` isn't valid YAML (list items indented too deep) | Fails to parse. `playbook.yml` already applies the same role, so the lab isn't affected |
| The `rebuild-cluster.sh` and `.ps1` app deploy (step 6) has no retry | A transient API error aborts the run |
| File Browser image `v2-alpine` is v2.11.0 (2020) | Old; newer versions changed their setup |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Permission check failed (changing feature flags for privileged container is only allowed for root@pam)` | Terraform tried to set LXC features | Leave `features` to step 3 (the module already does this) |
| `403` on storage or `{}` from `/access/permissions` | API token has no ACL | `pveum acl modify / ... --users ... --tokens ...` (step 1) |
| K3s crash-loops with `open /dev/kmsg: no such file or directory` | `/dev` was reset by a container restart | `printf 'L /dev/kmsg - - - - /dev/console\n' > /etc/tmpfiles.d/kmsg.conf && systemd-tmpfiles --create` (the role does this) |
| `ImagePullBackOff` with `lookup ... Try again` | Container DNS points at `127.0.0.1` | Terraform `dns_servers` (already set), then `terraform apply` |
| `kubectl` hangs, `apiserver not ready` | Master out of memory | `free -m` on the master; raise `memory_mb` |
| All HTTPS requests return `403` | LAN allow-list sees non-LAN client IPs | Traefik must use host ports, not ServiceLB (`15-secure-access.yaml`) |
| Browser says "Not secure" | Lab CA not trusted | [Step 7](#7-use-it-from-your-pc), then fully restart the browser |
| `connection to the server localhost:8080 was refused` | `KUBECONFIG` points at a file that doesn't exist | On your PC, use `~/.kube/config-proxmox-k3s`; on the master, `unset KUBECONFIG` |
| `apt` says `dpkg was interrupted` in a container | `snapd` hung during an upgrade (snaps don't work in LXC) | Mask `snapd.seeded.service snapd.service snapd.socket`, run `dpkg --configure -a`, then `apt-get purge -y snapd` |
| Ansible ignores `ansible.cfg` under `/mnt/c` | World-writable directory | Prefix commands with `ANSIBLE_CONFIG=$PWD/ansible.cfg` |

---

## Learn kubectl on this cluster

[KUBECTL-PRACTICE.md](KUBECTL-PRACTICE.md) is a beginner's guide that uses this
cluster's real names: looking around, debugging, getting into containers, and
10 hands-on exercises (self-healing, scaling, rollbacks, autoscaling and more).
