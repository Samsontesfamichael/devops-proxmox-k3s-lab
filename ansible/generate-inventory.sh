#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
INVENTORY_FILE="${SCRIPT_DIR}/hosts.ini"

echo "[generate-inventory] Reading Terraform outputs..."

cd "${TERRAFORM_DIR}"

MASTER_IP=$(terraform output -raw master_ip)
MASTER_VM_ID=$(terraform output -raw master_vm_id)

WORKER_IPS_JSON=$(terraform output -json worker_ips)
WORKER_VM_IDS_JSON=$(terraform output -json worker_vm_ids)

# Parse worker IPs and VM IDs from JSON using Python (more portable than jq)
python3 - <<PYEOF
import json, sys

master_ip = "${MASTER_IP}"
master_vm_id = "${MASTER_VM_ID}"
worker_ips = json.loads(sys.argv[1])
worker_vm_ids = json.loads(sys.argv[2])

lines = ["[master]"]
lines.append(f"{master_ip} ansible_user=root")

lines.append("")
lines.append("[workers]")
for key in sorted(worker_ips.keys(), key=int):
    vm_id = worker_vm_ids[key]
    ip = worker_ips[key]
    lines.append(f"{ip} ansible_user=root # vm_id={vm_id}")

lines.append("")
lines.append("[k3s_cluster:children]")
lines.append("master")
lines.append("workers")

with open("${INVENTORY_FILE}", "w") as f:
    f.write("\n".join(lines) + "\n")
PYEOF
"${WORKER_IPS_JSON}" "${WORKER_VM_IDS_JSON}"

echo "[generate-inventory] Inventory written to ${INVENTORY_FILE}"
