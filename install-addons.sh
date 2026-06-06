#!/bin/bash
set -euo pipefail

export KUBECONFIG="${HOME}/.kube/config-proxmox-k3s"
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAY="${RETRY_DELAY:-30}"

retry() {
  local attempts=$1
  local delay=$2
  shift 2
  local n=1
  until "$@"; do
    if (( n >= attempts )); then
      echo "[ERROR] Command failed after ${attempts} attempts: $*"
      return 1
    fi
    echo "[RETRY ${n}/${attempts}] $* failed. Retrying in ${delay}s..."
    sleep "${delay}"
    ((n++))
  done
}

wait_ready() {
  echo "[WAIT] $1"
  local deadline=$((SECONDS + ${2:-300}))
  while (( SECONDS < deadline )); do
    if eval "$3" >/dev/null 2>&1; then
      echo "[READY] $1"
      return 0
    fi
    sleep 10
  done
  echo "[ERROR] Timeout waiting for: $1"
  return 1
}

echo "[addons] Installing metrics-server..."
retry "${RETRY_COUNT}" "${RETRY_DELAY}" kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "[addons] Installing cert-manager..."
retry "${RETRY_COUNT}" "${RETRY_DELAY}" kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

echo "[addons] Waiting for cert-manager to be ready..."
wait_ready "cert-manager ClusterIssuer" 300 "kubectl wait --for=condition=Ready clusterissuer/selfsigned-cluster-issuer --timeout=60s || true"

echo "[addons] Installing external-secrets-operator..."
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f - || true
retry "${RETRY_COUNT}" "${RETRY_DELAY}" kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml
retry "${RETRY_COUNT}" "${RETRY_DELAY}" kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/all.yaml

echo "[addons] Addons installed successfully."
