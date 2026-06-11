#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/tf.sh <cluster> <terraform-command> [extra-terraform-flags]
#
#   ./scripts/tf.sh dev-ap-south-1 plan
#   ./scripts/tf.sh dev-ap-south-1 apply
#   ./scripts/tf.sh dev-ap-south-1 destroy
#   ./scripts/tf.sh dev-ap-southeast-1 apply -target=module.network
#
# Each cluster has its own S3 state key (terraform/aws/backends/<cluster>.hcl).
# This script re-inits with the correct backend before every command so that
# running two clusters from the same directory never shares state.

CLUSTER="${1:?Usage: ./scripts/tf.sh <cluster> <command> [flags]}"
COMMAND="${2:?Usage: ./scripts/tf.sh <cluster> <command> [flags]}"
shift 2

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/aws"
BACKEND_CFG="${TF_DIR}/backends/${CLUSTER}.hcl"
TFVARS="${TF_DIR}/${CLUSTER}.tfvars"

if [[ ! -f "${BACKEND_CFG}" ]]; then
  echo "Error: backend config not found: ${BACKEND_CFG}" >&2
  exit 1
fi

if [[ ! -f "${TFVARS}" ]]; then
  echo "Error: tfvars file not found: ${TFVARS}" >&2
  exit 1
fi

cd "${TF_DIR}"

echo "==> terraform init -reconfigure (backend: ${CLUSTER})"
terraform init -reconfigure -backend-config="${BACKEND_CFG}"

echo "==> terraform ${COMMAND} (cluster: ${CLUSTER})"
terraform "${COMMAND}" \
  -var-file="${TFVARS}" \
  -var="cluster_name=${CLUSTER}" \
  "$@"
