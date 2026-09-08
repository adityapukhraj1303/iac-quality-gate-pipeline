#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${1:-dev}"
REGION="${AWS_REGION:-ap-south-1}"
SKIP_APPLY="${SKIP_APPLY:-false}"
SKIP_MONITORING="${SKIP_MONITORING:-false}"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

for command_name in aws terraform kubectl helm jq; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "${command_name} is required."
done

echo "[1/5] Checking AWS identity..."
aws sts get-caller-identity --region "${REGION}" --output table

echo "[2/5] Initializing and planning Terraform..."
cd "${PROJECT_ROOT}/terraform"
terraform init -upgrade=false -input=false
terraform plan -input=false \
    -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
    -out=setup.tfplan

if [[ "${SKIP_APPLY}" != "true" ]]; then
    read -r -p "Apply this Terraform plan? [y/N] " answer
    [[ "${answer}" =~ ^[Yy]$ ]] || fail "Terraform apply cancelled. Set SKIP_APPLY=true to skip the apply prompt."
    echo "[3/5] Applying Terraform..."
    terraform apply -input=false setup.tfplan
else
    echo "[3/5] Terraform apply skipped."
fi

echo "[4/5] Connecting kubectl to the EKS cluster..."
PARAMETERS="$(aws ssm get-parameters-by-path \
    --path "/iac-pipeline/${ENVIRONMENT}" \
    --recursive --region "${REGION}" --output json)"
CLUSTER_NAME="$(printf '%s' "${PARAMETERS}" | jq -r '.Parameters[] | select(.Name | endswith("/cluster_name")) | .Value')"
[[ -n "${CLUSTER_NAME}" && "${CLUSTER_NAME}" != "null" ]] || fail "Cluster name not found in SSM."
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"
aws eks wait cluster-active --region "${REGION}" --name "${CLUSTER_NAME}"
kubectl get nodes -o wide

if [[ "${SKIP_MONITORING}" != "true" ]]; then
    echo "[5/5] Installing or repairing Prometheus and Grafana..."
    bash "${PROJECT_ROOT}/scripts/monitoring.sh" install
    bash "${PROJECT_ROOT}/scripts/monitoring.sh" status
else
    echo "[5/5] Monitoring install skipped."
fi

echo
echo "[SUCCESS] Setup complete for ${ENVIRONMENT}."
echo "Grafana password: bash scripts/monitoring.sh password"
echo "Grafana access:   bash scripts/monitoring.sh port-forward grafana"
echo "Prometheus access: bash scripts/monitoring.sh port-forward prometheus"