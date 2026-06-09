#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
INVENTORY_FILE="${ANSIBLE_DIR}/hosts.ini"
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAY="${RETRY_DELAY:-30}"
export KUBECONFIG="${HOME}/.kube/config-proxmox-k3s"

echo "=========================================="
echo "  Proxmox K3s Cluster Rebuild Pipeline"
echo "=========================================="

retry() {
  local attempts=$1
  local delay=$2
  shift 2
  local n=1
  local output
  until "$@" 2>&1 | tee /tmp/rebuild_cmd.log > /dev/null; do
    output=$(cat /tmp/rebuild_cmd.log)
    if (( n >= attempts )); then
      echo "[ERROR] Command failed after ${attempts} attempts: $*"
      echo "[ERROR OUTPUT] ${output}"
      return 1
    fi
    echo "[RETRY ${n}/${attempts}] $* failed. Retrying in ${delay}s..."
    sleep "${delay}"
    ((n++))
  done
}

wait_ready() {
  local label="$1"
  local timeout="${2:-300}"
  local check_cmd="${3:-}"
  echo "[WAIT] ${label} (timeout ${timeout}s)..."
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if eval "${check_cmd}" >/dev/null 2>&1; then
      echo "[READY] ${label}"
      return 0
    fi
    sleep 10
  done
  echo "[ERROR] Timeout waiting for: ${label}"
  return 1
}

if [[ ! -f "${TERRAFORM_DIR}/.env" ]]; then
  echo "[ERROR] terraform/.env not found. Create it with TF_VAR_proxmox_api_token, TF_VAR_proxmox_endpoint, TF_VAR_gateway."
  exit 1
fi

echo "[1/6] Destroying old infrastructure..."
cd "${TERRAFORM_DIR}"
set -a; source .env; set +a
retry "${RETRY_COUNT}" "${RETRY_DELAY}" terraform destroy -auto-approve

echo "[2/6] Provisioning fresh infrastructure..."
retry "${RETRY_COUNT}" "${RETRY_DELAY}" terraform apply -auto-approve

echo "[3/6] Generating dynamic Ansible inventory from Terraform outputs..."
cd "${ANSIBLE_DIR}"
retry "${RETRY_COUNT}" "${RETRY_DELAY}" bash generate-inventory.sh

echo "[4/6] Running Ansible automation..."
retry "${RETRY_COUNT}" "${RETRY_DELAY}" ansible-playbook -i "${INVENTORY_FILE}" playbook.yml
retry "${RETRY_COUNT}" "${RETRY_DELAY}" ansible-playbook -i "${INVENTORY_FILE}" optimize-storage.yml

echo "[4.5/6] Waiting for K3s cluster to become Ready..."
wait_ready "all kube-system pods Ready" 600 "kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=600s"
wait_ready "all nodes Ready" 600 "kubectl get nodes --no-headers | grep -v ' Ready '"

echo "[5/6] Installing cluster addons (cert-manager, metrics-server, external-secrets)..."
bash "${SCRIPT_DIR}/install-addons.sh"

echo "[6/6] Deploying Kubernetes applications..."
kubectl apply --wait --timeout=5m -f ../kubernetes-core/
kubectl wait --for=condition=Ready clusterissuer/selfsigned-cluster-issuer --timeout=120s || true
kubectl apply --wait --timeout=5m -f ../kubernetes-architecture/

echo "=========================================="
echo "  Cluster rebuilt successfully!"
echo "=========================================="
kubectl get nodes -o wide
