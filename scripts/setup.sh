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
    --output json 2>/dev/null || true)"

CLUSTER_NAME="$(printf '%s' "${PARAMETERS}" | jq -r '.Parameters[] | select(.Name | endswith("/cluster_name")) | .Value' 2>/dev/null || true)"
ECR_URL="$(printf '%s' "${PARAMETERS}" | jq -r '.Parameters[] | select(.Name | endswith("/ecr_repository_url")) | .Value' 2>/dev/null || true)"

if [[ -z "${CLUSTER_NAME}" || "${CLUSTER_NAME}" == "null" || "${CLUSTER_NAME}" == "None" ]]; then
    CLUSTER_NAME="$(aws eks list-clusters --region "${REGION}" --query "clusters[?@ == 'iac-pipeline-${ENVIRONMENT}-eks'] | [0]" --output text 2>/dev/null || true)"
fi

if [[ -z "${CLUSTER_NAME}" || "${CLUSTER_NAME}" == "null" || "${CLUSTER_NAME}" == "None" ]]; then
    echo "[INFO] No cluster found for ${ENVIRONMENT}. Creating infrastructure with Terraform..."
    bash "${PROJECT_ROOT}/scripts/setup-all.sh" "${ENVIRONMENT}" SKIP_MONITORING="${SKIP_MONITORING}"
    PARAMETERS="$(aws ssm get-parameters-by-path --path "/iac-pipeline/${ENVIRONMENT}" --recursive --region "${REGION}" --output json 2>/dev/null || true)"
    CLUSTER_NAME="$(printf '%s' "${PARAMETERS}" | jq -r '.Parameters[] | select(.Name | endswith("/cluster_name")) | .Value' 2>/dev/null || true)"
fi

[[ -n "${CLUSTER_NAME}" && "${CLUSTER_NAME}" != "null" && "${CLUSTER_NAME}" != "None" ]] || fail "No cluster found in SSM or AWS for ${ENVIRONMENT}. Run Terraform first or verify permissions."

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