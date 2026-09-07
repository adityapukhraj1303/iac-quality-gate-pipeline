#!/usr/bin/env bash
# ==============================================================================
# Automated Kubernetes Deployment & Smoke Verification Script
# ==============================================================================

set -eo pipefail

ENV="${1:-dev}"
IMAGE_TAG="${2:-latest}"
NAMESPACE="${ENV}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=========================================================="
echo " Deploying iac-quality-gate-app to Kubernetes"
echo " Environment: ${ENV} | Namespace: ${NAMESPACE} | Tag: ${IMAGE_TAG}"
echo "=========================================================="

# 1. Ensure Namespace Exists
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 2. Apply ConfigMap & Service
echo "[INFO] Applying ConfigMap and Service manifests..."
kubectl apply -f "${PROJECT_ROOT}/k8s/configmap.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_ROOT}/k8s/service.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_ROOT}/k8s/ingress.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_ROOT}/k8s/hpa.yaml" -n "${NAMESPACE}"

# 3. Apply Deployment
echo "[INFO] Applying Deployment manifest..."
kubectl apply -f "${PROJECT_ROOT}/k8s/deployment.yaml" -n "${NAMESPACE}"

# 4. Update Container Image Tag
echo "[INFO] Setting container image to tag: ${IMAGE_TAG}..."
# In live clusters, replace with ECR URL if available
SSM_ECR=$(aws ssm get-parameter --name "/iac-pipeline/${ENV}/ecr_repository_url" --query 'Parameter.Value' --output text 2>/dev/null || true)
if [[ -n "$SSM_ECR" && "$SSM_ECR" != "None" ]]; then
    IMAGE_TARGET="${SSM_ECR}:${IMAGE_TAG}"
else
    IMAGE_TARGET="iac-quality-gate-app:${IMAGE_TAG}"
fi

kubectl set image deployment/iac-quality-gate-app bash-microservice="${IMAGE_TARGET}" -n "${NAMESPACE}"

# 5. Await Rollout Completion
echo "[INFO] Awaiting Kubernetes rollout status..."
kubectl rollout status deployment/iac-quality-gate-app -n "${NAMESPACE}" --timeout=180s

# 6. Post-Deploy Smoke Test Verification
echo "[INFO] Executing smoke test against /health endpoint..."
POD=$(kubectl get pods -n "${NAMESPACE}" -l app=iac-quality-gate-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -n "$POD" ]]; then
    echo "[INFO] Testing pod: ${POD}..."
    RESP=$(kubectl exec -n "${NAMESPACE}" "${POD}" -- curl -s -f http://localhost:8080/health || true)
    echo "[RESPONSE] ${RESP}"

    if echo "$RESP" | grep -q '"status":"ok"'; then
        echo "[SUCCESS] Smoke test passed! Service is healthy."
    else
        echo "[ERROR] Smoke test failed! Rolling back deployment..." >&2
        "${PROJECT_ROOT}/scripts/rollback.sh" "${ENV}"
        exit 1
    fi
else
    echo "[WARN] Could not find running pod to execute direct smoke test."
fi

echo "=========================================================="
echo " Deployment Successfully Completed!"
echo "=========================================================="
