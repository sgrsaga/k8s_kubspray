#!/usr/bin/env bash
# Run a kubespray playbook (built-in OR a custom one from this repo) against
# one of our environments, using the official kubespray Docker image. All
# kubespray playbooks come from the image; our own playbooks are mounted at
# /playbooks/.
#
# Usage:
#   ./scripts/kubespray.sh <env> [playbook]
#
# Built-in kubespray playbooks (resolve to /kubespray/<name>):
#   ./scripts/kubespray.sh dev cluster.yml          # first install
#   ./scripts/kubespray.sh dev scale.yml            # add a (BM) node after editing inventory
#   ./scripts/kubespray.sh dev upgrade-cluster.yml  # upgrade after bumping kube_version
#   ./scripts/kubespray.sh dev reset.yml            # destructive teardown
#
# Custom playbooks in this repo (mount at /playbooks/, pass absolute path):
#   ./scripts/kubespray.sh dev /playbooks/longhorn.yml
#
# Extra ansible-playbook flags can be passed after the playbook, e.g.:
#   ./scripts/kubespray.sh dev cluster.yml -e kube_version=1.34.4 --check

set -euo pipefail

ENV="${1:?env required (dev|ppe|pro)}"
PLAYBOOK="${2:-cluster.yml}"
shift 2 || shift $# || true

KSPV="${KUBESPRAY_VERSION:-v2.30.0}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INV_DIR="${REPO_ROOT}/inventory/${ENV}"
PB_DIR="${REPO_ROOT}/playbooks"

if [[ ! -d "${INV_DIR}" ]]; then
  echo "Inventory directory not found: ${INV_DIR}" >&2
  exit 1
fi

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH key not found: ${SSH_KEY}" >&2
  echo "Set SSH_KEY=/path/to/key to override (default: ~/.ssh/id_rsa)." >&2
  exit 1
fi

# Mount /playbooks only if the directory exists (keeps the command minimal
# for users who never write custom playbooks).
PB_MOUNT=()
if [[ -d "${PB_DIR}" ]]; then
  PB_MOUNT=(-v "${PB_DIR}:/playbooks:ro")
fi

echo "==> Running kubespray ${KSPV} :: ${PLAYBOOK} against env=${ENV}"

# Only allocate a TTY when stdin is one; otherwise `docker run -t` fails with
# "the input device is not a TTY" (CI, non-interactive shells, pipes).
TTY_FLAGS=(-i)
if [[ -t 0 ]]; then
  TTY_FLAGS+=(-t)
fi

docker run --rm "${TTY_FLAGS[@]}" \
  -v "${INV_DIR}:/inventory:rw" \
  "${PB_MOUNT[@]}" \
  -v "${SSH_KEY}:/root/.ssh/id_rsa:ro" \
  -e ANSIBLE_HOST_KEY_CHECKING=False \
  -e ANSIBLE_CONFIG=/inventory/ansible.cfg \
  "quay.io/kubespray/kubespray:${KSPV}" \
  ansible-playbook \
    -i /inventory/inventory.ini \
    --become --become-user=root \
    "${PLAYBOOK}" "$@"
