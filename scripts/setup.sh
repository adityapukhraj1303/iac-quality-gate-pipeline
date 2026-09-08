#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${1:-dev}"
REGION="${AWS_REGION:-ap-south-1}"
SKIP_MONITORING="${SKIP_MONITORING:-false}"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

for command_name in aws kubectl helm jq; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "${command_name} is required."
done

echo "[INFO] Checking AWS identity..."
aws sts get-caller-identity --region "${REGION}" --output table

PARAMETERS="$(aws ssm get-parameters-by-path \
    --path "/iac-pipeline/${ENVIRONMENT}" \
    --recursive \
    --region "${REGION}" \
    --output json)"

CLUSTER_NAME="$(printf '%s' "${PARAMETERS}" | jq -r '.Parameters[] | select(.Name | endswith("/cluster_name")) | .Value')"
ECR_URL="$(printf '%s' "${PARAMETERS}" | jq -r '.Parameters[] | select(.Name | endswith("/ecr_repository_url")) | .Value')"
[[ -n "${CLUSTER_NAME}" && "${CLUSTER_NAME}" != "null" ]] || fail "No cluster found in SSM for ${ENVIRONMENT}. Run Terraform first."

echo "[INFO] Connecting kubectl to ${CLUSTER_NAME}..."
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}" >/dev/null
aws eks wait cluster-active --region "${REGION}" --name "${CLUSTER_NAME}"

echo "[INFO] Cluster status:"
kubectl get nodes -o wide
kubectl get pods -A
echo "[INFO] ECR repository: ${ECR_URL}"

if [[ "${SKIP_MONITORING}" != "true" ]]; then
    echo "[INFO] Installing or repairing Prometheus and Grafana..."
    bash "${PROJECT_ROOT}/scripts/monitoring.sh" install
    bash "${PROJECT_ROOT}/scripts/monitoring.sh" status
fi

echo
echo "[SUCCESS] Setup complete."
echo "[INFO] Grafana password: bash scripts/monitoring.sh password"
echo "[INFO] Grafana access:   bash scripts/monitoring.sh port-forward grafana"
echo "[INFO] Prometheus access: bash scripts/monitoring.sh port-forward prometheus"