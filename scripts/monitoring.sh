#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
RELEASE="${MONITORING_RELEASE:-kube-prometheus-stack}"
VALUES_FILE="${PROJECT_ROOT}/monitoring/kube-prometheus-values.yaml"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_commands() {
    command -v kubectl >/dev/null 2>&1 || fail "kubectl is required."
    command -v helm >/dev/null 2>&1 || fail "helm is required."
}

install_monitoring() {
    require_commands
    [[ -f "${VALUES_FILE}" ]] || fail "Missing ${VALUES_FILE}"

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
    helm repo update >/dev/null
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

    if helm status "${RELEASE}" --namespace "${NAMESPACE}" >/dev/null 2>&1; then
        release_status="$(helm status "${RELEASE}" --namespace "${NAMESPACE}" --output json | grep -o '"status":"[^"]*"' | head -n1 || true)"
        if [[ "${release_status}" == *'"failed"'* || "${release_status}" == *'"pending-'* ]]; then
            helm uninstall "${RELEASE}" --namespace "${NAMESPACE}" --wait --timeout 5m || true
        fi
    fi

    helm upgrade --install "${RELEASE}" prometheus-community/kube-prometheus-stack \
        --namespace "${NAMESPACE}" \
        --values "${VALUES_FILE}" \
        --wait --timeout 10m
}

status_monitoring() {
    require_commands
    helm status "${RELEASE}" --namespace "${NAMESPACE}" || true
    kubectl get pods,svc -n "${NAMESPACE}" -o wide
}

show_password() {
    require_commands
    kubectl get secret -n "${NAMESPACE}" "${RELEASE}-grafana" \
        -o jsonpath='{.data.admin-password}' | base64 --decode
    echo
}

port_forward() {
    require_commands
    local service="${1:-grafana}"
    case "${service}" in
        grafana) kubectl port-forward -n "${NAMESPACE}" svc/"${RELEASE}"-grafana 3000:80 ;;
        prometheus) kubectl port-forward -n "${NAMESPACE}" svc/"${RELEASE}"-prometheus 9090:9090 ;;
        *) fail "Usage: $0 port-forward [grafana|prometheus]" ;;
    esac
}

uninstall_monitoring() {
    require_commands
    helm uninstall "${RELEASE}" --namespace "${NAMESPACE}" --wait --timeout 5m || true
}

case "${1:-status}" in
    install) install_monitoring ;;
    status) status_monitoring ;;
    password) show_password ;;
    port-forward) port_forward "${2:-grafana}" ;;
    uninstall) uninstall_monitoring ;;
    *) fail "Usage: $0 [install|status|password|port-forward [grafana|prometheus]|uninstall]" ;;
esac