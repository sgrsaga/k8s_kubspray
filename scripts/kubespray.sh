#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/kubespray.sh <cluster> <playbook> [extra-ansible-flags]
#
#   ./scripts/kubespray.sh dev-ap-south-1 cluster.yml
#   ./scripts/kubespray.sh dev-ap-south-1 scale.yml
#   ./scripts/kubespray.sh dev-ap-south-1 upgrade-cluster.yml
#   ./scripts/kubespray.sh dev-ap-south-1 reset.yml
#   ./scripts/kubespray.sh dev-ap-south-1 cluster.yml --list-tasks
#
# Environment variables:
#   KUBESPRAY_VERSION  Docker image tag (default: v2.30.0)
#   SSH_KEY            Path to SSH private key (default: ~/.ssh/id_rsa)

CLUSTER="${1:?Usage: ./scripts/kubespray.sh <cluster> <playbook> [flags]}"
PLAYBOOK="${2:?Usage: ./scripts/kubespray.sh <cluster> <playbook> [flags]}"
shift 2

KUBESPRAY_VERSION="${KUBESPRAY_VERSION:-v2.31.0}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_DIR="${REPO_ROOT}/clusters/${CLUSTER}"

if [[ ! -d "${CLUSTER_DIR}" ]]; then
  echo "Error: cluster directory not found: ${CLUSTER_DIR}" >&2
  exit 1
fi

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "Error: SSH key not found: ${SSH_KEY}" >&2
  exit 1
fi

DOCKER_ARGS=(
  --rm
  -v "${CLUSTER_DIR}:/inventory:rw"
  -v "${SSH_KEY}:/root/.ssh/id_rsa:ro"
  -e ANSIBLE_CONFIG=/inventory/ansible.cfg
)

# Mount custom playbooks if the directory exists.
PLAYBOOKS_DIR="${REPO_ROOT}/playbooks"
if [[ -d "${PLAYBOOKS_DIR}" ]]; then
  DOCKER_ARGS+=(-v "${PLAYBOOKS_DIR}:/playbooks:ro")
fi

# Allocate a TTY only when running interactively.
if [[ -t 0 ]]; then
  DOCKER_ARGS+=(-it)
fi

# Resolve playbook path: custom playbooks take precedence over built-ins.
if [[ -d "${PLAYBOOKS_DIR}" && -f "${PLAYBOOKS_DIR}/${PLAYBOOK}" ]]; then
  PLAYBOOK_PATH="/playbooks/${PLAYBOOK}"
else
  PLAYBOOK_PATH="/kubespray/${PLAYBOOK}"
fi

docker run "${DOCKER_ARGS[@]}" \
  "quay.io/kubespray/kubespray:${KUBESPRAY_VERSION}" \
  ansible-playbook \
    -i /inventory/inventory.ini \
    --private-key /root/.ssh/id_rsa \
    -e ansible_ssh_common_args="-o StrictHostKeyChecking=no" \
    "${PLAYBOOK_PATH}" \
    "$@"
