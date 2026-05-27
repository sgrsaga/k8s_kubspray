#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/render-inventory.sh <cluster> [--init]
#
# Reads terraform output for the given cluster and rewrites the [all] block
# in clusters/<cluster>/inventory.ini with real node public IPs.
# Bare-metal lines (commented or active) are preserved untouched.
#
#   ./scripts/render-inventory.sh dev-ap-south-1
#   ./scripts/render-inventory.sh dev-ap-south-1 --init   # re-run terraform init first

CLUSTER="${1:?Usage: ./scripts/render-inventory.sh <cluster> [--init]}"
INIT=false
[[ "${2:-}" == "--init" ]] && INIT=true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/aws"
CLUSTER_DIR="${REPO_ROOT}/clusters/${CLUSTER}"
INVENTORY="${CLUSTER_DIR}/inventory.ini"

for cmd in terraform jq; do
  command -v "$cmd" &>/dev/null || { echo "Error: $cmd not found in PATH" >&2; exit 1; }
done

if [[ ! -f "${TF_DIR}/${CLUSTER}.tfvars" ]]; then
  echo "Error: ${TF_DIR}/${CLUSTER}.tfvars not found" >&2
  exit 1
fi

if [[ ! -f "${INVENTORY}" ]]; then
  echo "Error: inventory not found: ${INVENTORY}" >&2
  exit 1
fi

if [[ "${INIT}" == true ]]; then
  echo "Re-initialising Terraform backend for ${CLUSTER}..."
  (cd "${TF_DIR}" && terraform init \
    -backend-config="backends/${CLUSTER}.hcl" \
    -reconfigure -no-color)
fi

echo "Reading Terraform outputs for ${CLUSTER}..."
TF_OUTPUT=$(cd "${TF_DIR}" && terraform output \
  -var-file="${CLUSTER}.tfvars" \
  -var="cluster_name=${CLUSTER}" \
  -json 2>/dev/null)

# Extract public IPs — nodes are reachable directly (no bastion).
mapfile -t NODE_IPS < <(echo "${TF_OUTPUT}" | jq -r '.node_public_ips.value[]')

if [[ ${#NODE_IPS[@]} -eq 0 ]]; then
  echo "Error: no node_public_ips in Terraform output. Has terraform apply been run?" >&2
  exit 1
fi

echo "Found ${#NODE_IPS[@]} node(s): ${NODE_IPS[*]}"

# Build replacement [all] block (cloud nodes only; bare-metal lines preserved by awk).
ALL_BLOCK="[all]"$'\n'
for i in "${!NODE_IPS[@]}"; do
  N=$((i + 1))
  IP="${NODE_IPS[$i]}"
  ALL_BLOCK+="node-${N} ansible_host=${IP} ip=${IP} etcd_member_name=etcd${N}"$'\n'
done

TMPFILE=$(mktemp)
trap 'rm -f "${TMPFILE}"' EXIT

# awk rewrites the [all] block:
#   - Replaces "node-N ansible_host=..." lines with fresh IPs.
#   - Preserves commented bare-metal lines verbatim.
#   - Leaves all other sections untouched.
awk -v new_block="${ALL_BLOCK}" '
  /^\[all\]/ {
    print new_block
    in_all = 1
    next
  }
  in_all && /^\[/ {
    in_all = 0
  }
  in_all && /^node-[0-9]+ ansible_host=/ {
    next
  }
  { print }
' "${INVENTORY}" > "${TMPFILE}"

mv "${TMPFILE}" "${INVENTORY}"
echo "Inventory updated: ${INVENTORY}"
