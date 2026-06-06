#!/usr/bin/env python3
import os
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
TERRAFORM_DIR = REPO_ROOT / "terraform"
ANSIBLE_DIR = REPO_ROOT / "ansible"
INVENTORY_FILE = ANSIBLE_DIR / "hosts.ini"
KUBECONFIG = Path.home() / ".kube" / "config-proxmox-k3s"
ENV_FILE = TERRAFORM_DIR / ".env"

RETRY_COUNT = int(os.environ.get("RETRY_COUNT", "3"))
RETRY_DELAY = int(os.environ.get("RETRY_DELAY", "30"))
KUBECTL_TIMEOUT = "5m"


def run(cmd, cwd=None, env=None, check=True):
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, env=env, text=True)
    if check and result.returncode != 0:
        print(f"[ERROR] Command failed: {' '.join(cmd)}")
        sys.exit(result.returncode)
    return result


def retry(func, attempts=RETRY_COUNT, delay=RETRY_DELAY):
    last_exception = None
    for attempt in range(1, attempts + 1):
        try:
            return func()
        except Exception as e:
            last_exception = e
            if attempt >= attempts:
                print(f"[ERROR] Operation failed after {attempts} attempts: {e}")
                sys.exit(1)
            print(f"[RETRY {attempt}/{attempts}] Failed. Retrying in {delay}s...")
            time.sleep(delay)
    raise last_exception  # unreachable but satisfies linters


def load_env(path):
    env = os.environ.copy()
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip("\"'")
            if key:
                env[key] = value
    return env


def step1_destroy(env):
    print("[1/6] Destroying old infrastructure...")
    def _run():
        r = run(["terraform", "destroy", "-auto-approve"], cwd=TERRAFORM_DIR, env=env)
        if r.returncode != 0:
            raise RuntimeError("terraform destroy failed")
    retry(_run)


def step2_apply(env):
    print("[2/6] Provisioning fresh infrastructure...")
    def _run():
        r = run(["terraform", "apply", "-auto-approve"], cwd=TERRAFORM_DIR, env=env)
        if r.returncode != 0:
            raise RuntimeError("terraform apply failed")
    retry(_run)


def step3_generate_inventory():
    print("[3/6] Generating dynamic Ansible inventory from Terraform outputs...")
    env = load_env(ENV_FILE)
    def _run():
        r1 = run(["terraform", "output", "-raw", "master_ip"], cwd=TERRAFORM_DIR, env=env)
        r2 = run(["terraform", "output", "-json", "worker_ips"], cwd=TERRAFORM_DIR, env=env)
        if r1.returncode != 0 or r2.returncode != 0:
            raise RuntimeError("terraform output failed")
        return r1.stdout.strip(), r2.stdout.strip()
    master_ip, worker_ips_json = retry(_run)

    import json
    try:
        worker_data = json.loads(worker_ips_json)
    except json.JSONDecodeError as e:
        print(f"[ERROR] Failed to parse Terraform worker_ips JSON: {e}")
        sys.exit(1)

    lines = ["[master]", f"{master_ip} ansible_user=root", "", "[workers]"]
    for key in sorted(worker_data.keys(), key=lambda k: int(k) if k.isdigit() else k):
        ip = worker_data[key]
        lines.append(f"{ip} ansible_user=root # worker_{key}")
    lines += ["", "[k3s_cluster:children]", "master", "workers"]

    INVENTORY_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"  Inventory written to {INVENTORY_FILE}")


def step4_ansible():
    print("[4/6] Running Ansible automation...")
    def _run1():
        r = run(["ansible-playbook", "-i", str(INVENTORY_FILE), "playbook.yml"], cwd=ANSIBLE_DIR)
        if r.returncode != 0:
            raise RuntimeError("ansible playbook.yml failed")
    def _run2():
        r = run(["ansible-playbook", "-i", str(INVENTORY_FILE), "optimize-storage.yml"], cwd=ANSIBLE_DIR)
        if r.returncode != 0:
            raise RuntimeError("ansible optimize-storage.yml failed")
    retry(_run1)
    retry(_run2)


def wait_cluster_ready(label, check_cmd, timeout=600):
    print(f"[WAIT] {label} (timeout {timeout}s)...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = subprocess.run(check_cmd, capture_output=True, text=True, env={**os.environ, "KUBECONFIG": str(KUBECONFIG)})
            if r.returncode == 0:
                print(f"[READY] {label}")
                return
        except Exception:
            pass
        time.sleep(10)
    print(f"[ERROR] Timeout waiting for: {label}")
    sys.exit(1)


def step4b_wait_k3s_ready():
    print("[4.5/6] Waiting for K3s cluster to become Ready...")
    wait_cluster_ready(
        "all kube-system pods Ready",
        ["kubectl", "wait", "--for=condition=Ready", "pods", "--all", "-n", "kube-system", "--timeout=300s"],
        timeout=700
    )
    wait_cluster_ready(
        "all nodes Ready",
        ["kubectl", "get", "nodes", "--no-headers"],
        timeout=700
    )


def step5_addons():
    print("[5/6] Installing cluster addons (cert-manager, metrics-server, external-secrets)...")
    env = {**os.environ, "KUBECONFIG": str(KUBECONFIG)}

    def _apply(url):
        r = run(["kubectl", "apply", "-f", url], env=env)
        if r.returncode != 0:
            raise RuntimeError(f"kubectl apply -f {url} failed")

    retry(lambda: _apply("https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"))
    retry(lambda: _apply("https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml"))

    wait_cluster_ready(
        "cert-manager ClusterIssuer ready",
        ["kubectl", "wait", "--for=condition=Ready", "clusterissuer/selfsigned-cluster-issuer", "--timeout=60s"],
        timeout=120
    )

    subprocess.run(["kubectl", "create", "namespace", "external-secrets", "--dry-run=client", "-o", "yaml"], capture_output=True, text=True, env=env) | \
    subprocess.run(["kubectl", "apply", "-f", "-"], input=subprocess.Popen(["kubectl", "create", "namespace", "external-secrets", "--dry-run=client", "-o", "yaml"], capture_output=True, text=True, env=env).stdout, text=True, env=env)

    retry(lambda: _apply("https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml"))
    retry(lambda: _apply("https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/all.yaml"))


def step6_deploy_apps():
    print("[6/6] Deploying Kubernetes applications...")
    env = {**os.environ, "KUBECONFIG": str(KUBECONFIG)}

    def _apply_dir(path):
        r = run(["kubectl", "apply", "--wait", f"--timeout={KUBECTL_TIMEOUT}", "-f", str(path)], env=env)
        if r.returncode != 0:
            raise RuntimeError(f"kubectl apply -f {path} failed")

    retry(lambda: _apply_dir(REPO_ROOT / "kubernetes-core"))
    run(["kubectl", "wait", "--for=condition=Ready", "clusterissuer/selfsigned-cluster-issuer", "--timeout=120s"], env=env)
    retry(lambda: _apply_dir(REPO_ROOT / "kubernetes-architecture"))


def main():
    if not ENV_FILE.exists():
        print("[ERROR] terraform/.env not found. Create it with TF_VAR_proxmox_api_token, TF_VAR_proxmox_endpoint, TF_VAR_gateway.")
        sys.exit(1)

    print("")
    print("==========================================")
    print("  Proxmox K3s Cluster Rebuild Pipeline")
    print("==========================================")
    print("")

    env = load_env(ENV_FILE)

    try:
        step1_destroy(env)
        step2_apply(env)
        step3_generate_inventory()
        step4_ansible()
        step4b_wait_k3s_ready()
        step5_addons()
        step6_deploy_apps()
    except KeyboardInterrupt:
        print("\n[ABORTED] Pipeline interrupted by user.")
        sys.exit(130)

    print("")
    print("==========================================")
    print("  Cluster rebuilt successfully!")
    print("==========================================")

    env_final = {**os.environ, "KUBECONFIG": str(KUBECONFIG)}
    subprocess.run(["kubectl", "get", "nodes", "-o", "wide"], env=env_final)


if __name__ == "__main__":
    main()
