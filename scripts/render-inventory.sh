#!/usr/bin/env bash
# Regenerate the [all] block + [bastion] block of inventory/<env>/inventory.ini
# from the env's Terraform outputs. Bare-metal lines (commented or active) are
# preserved untouched.
#
# Usage:
#   ./scripts/render-inventory.sh <env>          # uses terraform/ workspace already init'd for <env>
#   ./scripts/render-inventory.sh <env> --init   # re-runs `terraform init -reconfigure` first
#
# Requires: terraform, jq.

set -euo pipefail

ENV="${1:?env required (dev|ppe|pro)}"
DO_INIT="${2:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform"
INV_FILE="${REPO_ROOT}/inventory/${ENV}/inventory.ini"

for cmd in terraform jq; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
done

if [[ ! -f "${INV_FILE}" ]]; then
  echo "Inventory file not found: ${INV_FILE}" >&2
  exit 1
fi

if [[ "${DO_INIT}" == "--init" ]]; then
  echo "==> Re-initialising terraform backend for ${ENV}"
  terraform -chdir="${TF_DIR}" init -reconfigure \
    -backend-config="backends/${ENV}.hcl" -input=false
fi

echo "==> Reading terraform outputs for ${ENV}"
TF_OUT="$(terraform -chdir="${TF_DIR}" output -json)"

BASTION_IP="$(jq -r '.bastion_public_ip.value' <<<"${TF_OUT}")"
mapfile -t NODE_IPS < <(jq -r '.node_private_ips.value[]' <<<"${TF_OUT}")

if [[ -z "${BASTION_IP}" || "${BASTION_IP}" == "null" ]]; then
  echo "Could not read bastion_public_ip from terraform state. Did you run 'terraform apply' for ${ENV}?" >&2
  exit 1
fi
if [[ "${#NODE_IPS[@]}" -lt 3 ]]; then
  echo "Expected >=3 node_private_ips, got ${#NODE_IPS[@]}" >&2
  exit 1
fi

echo "    bastion: ${BASTION_IP}"
for i in "${!NODE_IPS[@]}"; do
  echo "    node-$((i+1)): ${NODE_IPS[$i]}"
done

# Atomic in-place rewrite via a temp file.
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

awk -v B="${BASTION_IP}" \
    -v N1="${NODE_IPS[0]}" \
    -v N2="${NODE_IPS[1]}" \
    -v N3="${NODE_IPS[2]}" '
BEGIN { in_all=0; in_bastion=0 }
# Toggle section state on group headers
/^\[all\][[:space:]]*$/        { in_all=1; in_bastion=0; print; next }
/^\[bastion\][[:space:]]*$/    { in_bastion=1; in_all=0; print; next }
/^\[/                          { in_all=0; in_bastion=0; print; next }

# Rewrite node-N lines inside [all], leave bm-* and comments alone
in_all && /^node-1[[:space:]]/ { printf "node-1 ansible_host=%s ip=%s etcd_member_name=etcd1\n", N1, N1; next }
in_all && /^node-2[[:space:]]/ { printf "node-2 ansible_host=%s ip=%s etcd_member_name=etcd2\n", N2, N2; next }
in_all && /^node-3[[:space:]]/ { printf "node-3 ansible_host=%s ip=%s etcd_member_name=etcd3\n", N3, N3; next }

# Rewrite the bastion line
in_bastion && /^bastion[[:space:]]/ { printf "bastion ansible_host=%s ansible_user=ubuntu\n", B; next }

{ print }
' "${INV_FILE}" > "${TMP}"

mv "${TMP}" "${INV_FILE}"
trap - EXIT

echo "==> Wrote ${INV_FILE}"
