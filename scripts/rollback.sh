#!/usr/bin/env bash
# ==============================================================================
# Automated Zero-Downtime Rollback Script
# ==============================================================================

set -eo pipefail

ENV="${1:-dev}"
NAMESPACE="${ENV}"

echo "=========================================================="
echo " Triggering Automated Rollback for iac-quality-gate-app"
echo " Environment: ${ENV} | Namespace: ${NAMESPACE}"
echo "=========================================================="

CLUSTER_NAME=$(aws ssm get-parameter --name "/iac-pipeline/${ENV}/cluster_name" --query 'Parameter.Value' --output text 2>/dev/null || true)
if [[ -n "${CLUSTER_NAME}" && "${CLUSTER_NAME}" != "None" && "${CLUSTER_NAME}" != "null" ]]; then
    echo "[INFO] Refreshing kubeconfig for cluster: ${CLUSTER_NAME}"
    aws eks update-kubeconfig --region "${AWS_REGION:-ap-south-1}" --name "${CLUSTER_NAME}"
    aws eks wait cluster-active --region "${AWS_REGION:-ap-south-1}" --name "${CLUSTER_NAME}"
else
    echo "[ERROR] EKS cluster metadata is missing in SSM for environment '${ENV}'. Run Terraform first." >&2
    exit 1
fi

echo "[INFO] Rolling back deployment to previous stable revision..."
kubectl rollout undo deployment/iac-quality-gate-app -n "${NAMESPACE}"

echo "[INFO] Awaiting rollback completion..."
kubectl rollout status deployment/iac-quality-gate-app -n "${NAMESPACE}" --timeout=120s

echo "[INFO] Verifying healthy pods after rollback..."
POD=$(kubectl get pods -n "${NAMESPACE}" -l app=iac-quality-gate-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -n "$POD" ]]; then
    RESP=$(kubectl exec -n "${NAMESPACE}" "${POD}" -- curl -s -f http://localhost:8080/health || true)
    echo "[RESPONSE] ${RESP}"

    if echo "$RESP" | grep -q '"status":"ok"'; then
        echo "[SUCCESS] Rollback completed and health verified!"
    else
        echo "[ALERT] Rollback finished but health check is still reporting errors!" >&2
        exit 1
    fi
fi
