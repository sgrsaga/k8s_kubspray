#!/usr/bin/env bash
# Install Longhorn into an environment's cluster (post-cluster.yml).
# Wraps the kubespray docker image so we reuse its ansible + ssh stack.
#
# Usage:
#   ./scripts/install-longhorn.sh <env>
#
# Env overrides:
#   KUBESPRAY_VERSION  (default: v2.30.0)
#   SSH_KEY            (default: ~/.ssh/id_rsa)

set -euo pipefail

ENV="${1:?env required (dev|ppe|pro)}"
KSPV="${KUBESPRAY_VERSION:-v2.30.0}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INV_DIR="${REPO_ROOT}/inventory/${ENV}"
PB_DIR="${REPO_ROOT}/playbooks"

[[ -d "${INV_DIR}" ]] || { echo "Inventory not found: ${INV_DIR}" >&2; exit 1; }
[[ -f "${SSH_KEY}" ]] || { echo "SSH key not found: ${SSH_KEY}" >&2; exit 1; }
[[ -f "${PB_DIR}/longhorn.yml" ]] || { echo "Playbook not found: ${PB_DIR}/longhorn.yml" >&2; exit 1; }

echo "==> Installing Longhorn on env=${ENV}"

docker run --rm -it \
  -v "${INV_DIR}:/inventory:rw" \
  -v "${PB_DIR}:/playbooks:ro" \
  -v "${SSH_KEY}:/root/.ssh/id_rsa:ro" \
  -e ANSIBLE_HOST_KEY_CHECKING=False \
  -e ANSIBLE_CONFIG=/inventory/ansible.cfg \
  "quay.io/kubespray/kubespray:${KSPV}" \
  ansible-playbook \
    -i /inventory/inventory.ini \
    --become --become-user=root \
    /playbooks/longhorn.yml
