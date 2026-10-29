# kubectl Practice Guide (for this lab)

A beginner's list of commands to explore **your own K3s cluster**. Every name below (namespaces, apps, services) is real and exists in this lab, so you can copy-paste and run them.

> **Tip:** Read-only commands (`get`, `describe`, `logs`, `top`) are always safe. Commands marked ⚠️ change something. They are safe to practise here, but read them before running.

---

## 0. One-time setup: connect kubectl to the cluster

kubectl needs a **kubeconfig** file to know which cluster to talk to. Yours is already on your PC.

Pick the line for **where you are typing**:

**On your PC, PowerShell (Windows):**

```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-proxmox-k3s"
```

**On your PC, WSL / Git Bash:**

```bash
export KUBECONFIG=~/.kube/config-proxmox-k3s
```

> **WSL says `Command 'kubectl' not found`?** WSL is its own Linux system and needs its own kubectl. Don't use `snap`; install the official binary once:
>
> ```bash
> cd ~ && curl -LO "https://dl.k8s.io/release/v1.36.5/bin/linux/amd64/kubectl"
> sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl
> ```
>
> Or just use PowerShell, where kubectl already works.

**On k3s-master itself** (logged in with `ssh root@192.168.1.201`): nothing to set. K3s's kubectl reads `/etc/rancher/k3s/k3s.yaml` by itself. If you set `KUBECONFIG` to the PC path above by mistake, you'll get
`connection to the server localhost:8080 was refused`. Fix it with:

```bash
unset KUBECONFIG
```

Run kubectl on the master, not the workers. The workers have a `kubectl` command, but no kubeconfig, so it can't reach the cluster from there.

This lasts only for the current terminal window. Run it again each time you open a new one.

> **Git Bash note:** Git Bash rewrites paths like `/usr/share/...` inside
> `kubectl exec` commands into Windows paths. Use PowerShell or WSL for section 5, or put `MSYS_NO_PATHCONV=1 ` in front of the command.

Check it works:

```bash
kubectl cluster-info
```

---

## 1. Words you'll see

| Word                         | What it means                                                                            |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| **Node**               | A machine in the cluster. You have 3: `k3s-master`, `k3s-worker-1`, `k3s-worker-2` |
| **Namespace**          | A folder that groups resources. Your apps live in `enterprise-apps`                    |
| **Pod**                | One running copy of an app (one or more containers)                                      |
| **Deployment**         | Keeps N copies of a pod running, and replaces them if they die                           |
| **Service**            | A stable network name and port in front of pods                                          |
| **Ingress**            | Routes web traffic (by host name) from outside to a Service                              |
| **ConfigMap / Secret** | Settings and passwords given to pods                                                     |
| **PVC**                | A request for disk storage (a PersistentVolumeClaim)                                     |

### Namespaces in this lab

| Namespace            | What's in it                                                  |
| -------------------- | ------------------------------------------------------------- |
| `enterprise-apps`  | Your apps: web apps, MySQL, Postgres, File Browser, demos     |
| `monitoring`       | Prometheus and Grafana                                        |
| `cert-manager`     | Creates TLS certificates                                      |
| `kube-system`      | K3s's own parts: CoreDNS, Traefik, metrics-server             |
| `external-secrets` | Namespace and permissions only (the operator isn't installed) |

---

## 2. Look at the cluster

```bash
kubectl get nodes                      # the 3 machines, and whether they're Ready
kubectl get nodes -o wide              # plus IP address, OS and container runtime
kubectl describe node k3s-master       # full detail: CPU, memory, pods on it
kubectl top nodes                      # live CPU and memory use per node
kubectl get namespaces                 # list all namespaces
kubectl version                        # client and server versions
kubectl api-resources                  # every kind of object the cluster knows
```

---

## 3. Look at your apps

`-n enterprise-apps` means "in the enterprise-apps namespace".
`-A` means "in every namespace".

```bash
kubectl get pods -n enterprise-apps              # all app pods
kubectl get pods -n enterprise-apps -o wide      # plus the node each pod runs on
kubectl get pods -A                              # pods in every namespace
kubectl get deployments -n enterprise-apps       # how many copies are ready
kubectl get services -n enterprise-apps          # network entry points
kubectl get ingress -n enterprise-apps           # web routes by host name
kubectl get all -n enterprise-apps               # pods, deployments, services, all at once
kubectl get pods -n enterprise-apps --watch      # live updates (Ctrl+C to stop)
```

### Filter by label (`-l`)

Each app's pods carry a label. Use it to pick out one app's pods:

| App (Deployment)         | Label                     |
| ------------------------ | ------------------------- |
| `sample-web-app`       | `app=web-test`          |
| `self-healing-web`     | `app=resilient-web`     |
| `config-demo-app`      | `app=config-test`       |
| `secret-demo-app`      | `app=secret-test`       |
| `corporate-custom-app` | `app=enterprise-custom` |
| `autoscale-app`        | `app=autoscale-web`     |
| `mysql-db`             | `app=mysql`             |
| `postgres-db`          | `app=postgres`          |
| `filebrowser`          | `app=filebrowser`       |

```bash
kubectl get pods -n enterprise-apps -l app=mysql
kubectl get pods -n enterprise-apps --show-labels
```

---

## 4. Find out why something is wrong

These 3 commands solve most problems.

```bash
# 1. Status and recent events (look at the "Events:" section at the bottom)
kubectl describe deployment mysql-db -n enterprise-apps
kubectl describe pod -n enterprise-apps -l app=mysql

# 2. What the app itself printed
kubectl logs deploy/mysql-db -n enterprise-apps
kubectl logs deploy/mysql-db -n enterprise-apps --tail=50     # last 50 lines
kubectl logs deploy/mysql-db -n enterprise-apps -f            # follow live (Ctrl+C)
kubectl logs deploy/mysql-db -n enterprise-apps --previous    # from before the last crash

# 3. Cluster events, oldest first
kubectl get events -n enterprise-apps --sort-by=.lastTimestamp
```

### Common pod statuses

| Status                                  | Meaning                                                              |
| --------------------------------------- | -------------------------------------------------------------------- |
| `Running`                             | Working                                                              |
| `Pending`                             | Waiting for a node with enough room, or for its disk                 |
| `ContainerCreating`                   | Downloading the image or attaching the disk (slow on a slow network) |
| `ImagePullBackOff` / `ErrImagePull` | Can't download the image: wrong name, or a network or DNS problem    |
| `CrashLoopBackOff`                    | Starts and then crashes repeatedly. Check `logs --previous`        |
| `OOMKilled`                           | Used more memory than its limit                                      |
| `Completed`                           | A one-off job finished (normal for jobs)                             |

---

## 5. Get inside a running container

```bash
# Run one command inside the container
kubectl exec deploy/sample-web-app -n enterprise-apps -- ls /usr/share/nginx/html

# Open a shell (type `exit` to leave)
kubectl exec -it deploy/sample-web-app -n enterprise-apps -- sh
```

### Talk to the databases

The passwords are already inside the containers as environment variables, so you don't need to type them.

```bash
# MySQL: list databases
kubectl exec -it deploy/mysql-db -n enterprise-apps -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"'

# MySQL: interactive prompt (type `exit;` to leave)
kubectl exec -it deploy/mysql-db -n enterprise-apps -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'

# Postgres: list databases (user postgres_user, database company_db)
kubectl exec -it deploy/postgres-db -n enterprise-apps -- psql -U postgres_user -d company_db -c '\l'

# Postgres: interactive prompt (type `\q` to leave)
kubectl exec -it deploy/postgres-db -n enterprise-apps -- psql -U postgres_user -d company_db
```

---

## 6. Open the apps in your browser

### Option A: port-forward (works for anything, no setup)

This connects a port on your PC to a Service in the cluster. Leave the window open while you use it, and press Ctrl+C to stop.

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring              # http://localhost:3000
kubectl port-forward svc/prometheus 9090:9090 -n monitoring           # http://localhost:9090
kubectl port-forward svc/filebrowser-service 8080:80 -n enterprise-apps   # http://localhost:8080
kubectl port-forward svc/web-entrypoint 8081:80 -n enterprise-apps        # http://localhost:8081
```

Grafana logs in as user `admin`. Its password is in the `grafana-admin` secret,under the key `password` (see section 7).

### Option B: host names through Traefik (Ingress), HTTPS and LAN-only

All web access goes through Traefik on `192.168.1.201`. It only accepts
requests from your home network (`192.168.1.0/24`), redirects HTTP to HTTPS, and nothing is open to the internet.

The setup is in `kubernetes-architecture/15-secure-access.yaml`.

1. Add this line to `C:\Windows\System32\drivers\etc\hosts` (open Notepad as Administrator):

   ```
   192.168.1.201  my-app.local  files.my-app.local  grafana.my-app.local  prometheus.my-app.local
   ```
2. Trust the lab's certificate authority once, so the browser shows no warning.
   In PowerShell, from the project folder:

   ```powershell
   Import-Certificate -FilePath .\lab-root-ca.crt -CertStoreLocation Cert:\CurrentUser\Root
   ```

   (Windows asks you to confirm. If the file is missing, export it again with `kubectl get secret lab-root-ca -n cert-manager -o jsonpath='{.data.ca\.crt}'` and base64-decode it.)
3. Open them:

| Address                         | Login                                                                                                       |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| https://my-app.local            | none (demo page)                                                                                            |
| https://files.my-app.local      | File Browser's own login                                                                                    |
| https://grafana.my-app.local    | `admin` + password from the `grafana-admin` secret                                                      |
| https://prometheus.my-app.local | `admin` + password from the `prometheus-basic-auth` secret (namespace `monitoring`, key `password`) |

---

## 7. Configuration and secrets

```bash
kubectl get configmaps -n enterprise-apps
kubectl describe configmap app-config -n enterprise-apps     # shows its values

kubectl get secrets -n enterprise-apps
kubectl describe secret enterprise-vault -n enterprise-apps  # key names only, not values
```

Secrets are stored base64-encoded. To read one value:

**WSL / Git Bash:**

```bash
kubectl get secret grafana-admin -n monitoring -o jsonpath='{.data.password}' | base64 -d; echo
```

**PowerShell:**

```powershell
$b64 = kubectl get secret grafana-admin -n monitoring -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
```

---

## 8. Storage

```bash
kubectl get pvc -n enterprise-apps     # mysql-pvc, postgres-pvc, backup-shared-pvc
kubectl get pv                         # the actual disks behind them
kubectl get storageclass               # local-path (K3s's built-in storage)
```

---

## 9. Exercises (things to try)

### Exercise 1: Self-healing ⚠️

Delete a pod and watch Kubernetes replace it automatically.

```bash
kubectl get pods -n enterprise-apps -l app=resilient-web
kubectl delete pod -n enterprise-apps -l app=resilient-web --wait=false
kubectl get pods -n enterprise-apps -l app=resilient-web --watch
```

The new pods have different names. That's the Deployment doing its job.

### Exercise 2: Scale up and down ⚠️

```bash
kubectl scale deployment sample-web-app -n enterprise-apps --replicas=4
kubectl get pods -n enterprise-apps -l app=web-test -o wide    # spread across nodes
kubectl scale deployment sample-web-app -n enterprise-apps --replicas=2
```

Memory is tight in this lab, so don't go much higher than 4.

### Exercise 3: Rolling update and rollback ⚠️

```bash
kubectl set image deployment/sample-web-app -n enterprise-apps nginx=nginx:1.27-alpine
kubectl rollout status deployment/sample-web-app -n enterprise-apps
kubectl rollout history deployment/sample-web-app -n enterprise-apps
kubectl rollout undo deployment/sample-web-app -n enterprise-apps      # go back
```

`nginx=` is the container's name inside the pod. To find a container's name:

```bash
kubectl get deploy sample-web-app -n enterprise-apps -o jsonpath='{.spec.template.spec.containers[*].name}'
```

### Exercise 4: Restart an app ⚠️

```bash
kubectl rollout restart deployment/config-demo-app -n enterprise-apps
kubectl rollout status deployment/config-demo-app -n enterprise-apps
```

### Exercise 5: Autoscaling (HPA) ⚠️

The `web-autoscaler` HPA adds copies of `autoscale-app` (up to 4) when CPU goes above 50%.

```bash
kubectl get hpa -n enterprise-apps

# In a SECOND terminal, create load (Ctrl+C to stop; the pod deletes itself):
kubectl run load-generator -n enterprise-apps --rm -it --image=busybox:1.36 --restart=Never -- sh -c "while true; do wget -q -O- http://autoscale-service; done"

# Back in the first terminal, watch replicas grow over 1–3 minutes:
kubectl get hpa web-autoscaler -n enterprise-apps --watch
```

After you stop the load, it scales back down within about 5 minutes.

### Exercise 6: Run a one-off pod ⚠️

```bash
# Test DNS and the network from inside the cluster (pod deletes itself on exit)
kubectl run test -n enterprise-apps --rm -it --image=busybox:1.36 --restart=Never -- sh
#   inside it, try:
#   nslookup mysql-db
#   wget -qO- http://web-entrypoint
#   exit
```

### Exercise 7: Run the backup CronJob now ⚠️

```bash
kubectl get cronjob -n enterprise-apps
kubectl create job manual-backup --from=cronjob/database-nightly-backup -n enterprise-apps
kubectl get jobs -n enterprise-apps
kubectl logs job/manual-backup -n enterprise-apps
kubectl delete job manual-backup -n enterprise-apps     # clean up
```

### Exercise 8: Network policy

`isolate-database-tier` limits which pods may talk to the databases.

```bash
kubectl describe networkpolicy isolate-database-tier -n enterprise-apps
```

### Exercise 9: Permissions (RBAC)

Ask "is this service account allowed to do X?"

```bash
kubectl auth can-i list pods -n enterprise-apps --as=system:serviceaccount:enterprise-apps:enterprise-app-sa
kubectl auth can-i delete pods -n enterprise-apps --as=system:serviceaccount:enterprise-apps:enterprise-app-sa
kubectl describe role enterprise-app-role -n enterprise-apps
```

### Exercise 10: Certificates

```bash
kubectl get clusterissuer
kubectl get certificate -n enterprise-apps
kubectl describe certificate my-app-tls -n enterprise-apps
```

---

## 10. Output formats (handy everywhere)

```bash
kubectl get pod -n enterprise-apps -l app=mysql -o yaml     # the full object as YAML
kubectl get pods -n enterprise-apps -o name                 # names only
kubectl get pods -A --sort-by=.metadata.creationTimestamp   # oldest first
kubectl get pods -n enterprise-apps --field-selector=status.phase!=Running   # only problems
kubectl explain deployment.spec.replicas                    # built-in docs for any field
```

---

## 11. Apply, change and delete YAML files ⚠️

The app definitions are in this repo under `kubernetes-architecture/` an `kubernetes-core/`.

```bash
kubectl diff -f kubernetes-architecture/06-health-checks.yaml     # preview a change first
kubectl apply -f kubernetes-architecture/06-health-checks.yaml    # create or update
kubectl apply --dry-run=server -f kubernetes-architecture/        # validate, change nothing
kubectl delete -f kubernetes-architecture/06-health-checks.yaml   # remove what the file created
```

`kubectl apply` again restores anything you deleted or broke while practising.

---

## 12. Shortcuts

| Long                         | Short      |
| ---------------------------- | ---------- |
| `pods`                     | `po`     |
| `deployments`              | `deploy` |
| `services`                 | `svc`    |
| `namespaces`               | `ns`     |
| `configmaps`               | `cm`     |
| `persistentvolumeclaims`   | `pvc`    |
| `horizontalpodautoscalers` | `hpa`    |
| `ingress`                  | `ing`    |

Example: `kubectl get po,svc -n enterprise-apps`

Tired of typing `-n enterprise-apps`? Make it the default for this kubeconfig:

```bash
kubectl config set-context --current --namespace=enterprise-apps
```

Switch back with `--namespace=default`.

---

## 13. Proxmox side (for reference)

These run on the Proxmox host (`ssh proxmox-node`), not with kubectl:

```bash
pct list                 # the 3 LXC containers and their state
pct enter 201            # open a shell inside k3s-master (type `exit` to leave)
pct config 201           # the container's settings
```

Inside a node, K3s's own logs:

```bash
journalctl -u k3s -f          # on k3s-master
journalctl -u k3s-agent -f    # on the workers
```
