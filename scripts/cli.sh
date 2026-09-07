#!/usr/bin/env bash
# ==============================================================================
# Interactive DevOps Operations CLI (Pure Bash)
#
# Primary interactive terminal interface for managing the entire pipeline:
# - Terraform Plan & Apply
# - Jenkins Parameterized Build Trigger
# - SonarQube Quality Gate Inspection
# - Kubernetes Rollout & Rollback Management
# - Live Log Streaming
# ==============================================================================

set -eo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JENKINS_URL="${JENKINS_URL:-http://localhost:8085}"
SONAR_URL="${SONAR_URL:-http://localhost:9000}"
DEFAULT_ENV="dev"

print_header() {
    clear
    echo "=================================================================="
    echo "  🚀 IaC Quality Gate & Auto-Deployment Interactive CLI"
    echo "=================================================================="
    echo " Active Directory: ${PROJECT_ROOT}"
    echo " Jenkins Endpoint: ${JENKINS_URL}"
    echo " SonarQube Server: ${SONAR_URL}"
    echo " Target Env:       ${DEFAULT_ENV}"
    echo "=================================================================="
}

pause() {
    read -rp "Press [Enter] to return to menu..."
}

select_environment() {
    echo ""
    echo "Select Target Environment:"
    echo "1) dev"
    echo "2) prod"
    read -rp "Choice [1/2] (default: 1): " env_choice
    case "$env_choice" in
        2) DEFAULT_ENV="prod" ;;
        *) DEFAULT_ENV="dev" ;;
    esac
    echo "[INFO] Active environment set to: ${DEFAULT_ENV}"
}

do_terraform_plan() {
    select_environment
    echo "[INFO] Running Terraform Plan for ${DEFAULT_ENV}..."
    cd "${PROJECT_ROOT}/terraform"
    terraform plan -var-file="environments/${DEFAULT_ENV}/terraform.tfvars"
    cd - >/dev/null
    pause
}

do_terraform_apply() {
    select_environment
    echo "[ALERT] Preparing to Apply Terraform for ${DEFAULT_ENV}..."
    read -rp "Are you SURE you want to apply infrastructure changes? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        cd "${PROJECT_ROOT}/terraform"
        terraform apply -var-file="environments/${DEFAULT_ENV}/terraform.tfvars"
        cd - >/dev/null
    else
        echo "[INFO] Terraform apply aborted."
    fi
    pause
}

do_trigger_jenkins() {
    select_environment
    read -rp "Enter Image Tag (e.g. v1.0.1, build-42) [latest]: " tag
    tag="${tag:-latest}"
    read -rp "Skip Quality Gate? [y/N]: " skip_qg
    skip_val="false"
    [[ "$skip_qg" =~ ^[Yy]$ ]] && skip_val="true"

    echo "[INFO] Triggering Jenkins parameterized build on ${JENKINS_URL}..."
    local job_url="${JENKINS_URL}/job/iac-quality-gate-pipeline/buildWithParameters"
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${job_url}" \
        --data-urlencode "ENVIRONMENT=${DEFAULT_ENV}" \
        --data-urlencode "IMAGE_TAG=${tag}" \
        --data-urlencode "SKIP_QUALITY_GATE=${skip_val}" \
        --data-urlencode "AUTO_ROLLBACK=true" || echo "000")

    if [[ "$http_code" == "201" || "$http_code" == "200" || "$http_code" == "302" ]]; then
        echo "[SUCCESS] Jenkins build triggered successfully (HTTP ${http_code})!"
        echo "View build queue at: ${JENKINS_URL}/job/iac-quality-gate-pipeline/"
    else
        echo "[WARN] Could not trigger Jenkins directly (HTTP ${http_code})."
        echo "Ensure Jenkins is running and reachable at: ${JENKINS_URL}"
    fi
    pause
}

do_check_sonarqube() {
    echo "[INFO] Querying SonarQube Quality Gate status for project 'iac-quality-gate-pipeline'..."
    local api_url="${SONAR_URL}/api/qualitygates/project_status?projectKey=iac-quality-gate-pipeline"

    local resp
    resp=$(curl -s "${api_url}" || true)

    if [[ -n "$resp" && "$resp" != *"<html>"* ]]; then
        echo "=========================================================="
        echo " SonarQube Quality Gate Report:"
        echo "=========================================================="
        local status
        status=$(echo "$resp" | grep -o '"status":"[^"]*"' | head -n1 | cut -d'"' -f4 || echo "UNKNOWN")
        echo " Overall Status: ${status}"
        echo " Raw Details:   ${resp}"
    else
        echo "[WARN] Could not connect to SonarQube at ${SONAR_URL}."
        echo "Ensure SonarQube container/server is running on port 9000."
    fi
    pause
}

do_k8s_rollout_status() {
    select_environment
    echo "[INFO] Checking rollout status for iac-quality-gate-app in namespace '${DEFAULT_ENV}'..."
    kubectl rollout status deployment/iac-quality-gate-app -n "${DEFAULT_ENV}" || true
    echo ""
    echo "[INFO] Current Pod Replicas:"
    kubectl get pods -n "${DEFAULT_ENV}" -l app=iac-quality-gate-app -o wide || true
    pause
}

do_k8s_rollback() {
    select_environment
    echo "[ALERT] Rollback initiated for namespace '${DEFAULT_ENV}'!"
    read -rp "Confirm rollback to previous revision? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        "${PROJECT_ROOT}/scripts/rollback.sh" "${DEFAULT_ENV}"
    else
        echo "[INFO] Rollback aborted."
    fi
    pause
}

do_tail_logs() {
    select_environment
    echo "[INFO] Streaming logs for deployment/iac-quality-gate-app in '${DEFAULT_ENV}' (Press Ctrl+C to stop)..."
    kubectl logs -f deployment/iac-quality-gate-app -n "${DEFAULT_ENV}" --all-containers=true --tail=50 || true
    pause
}

# Main Interactive Loop
while true; do
    print_header
    echo "Please choose an action:"
    options=(
        "Plan Terraform Infrastructure"
        "Apply Terraform Infrastructure"
        "Trigger Jenkins Pipeline Build"
        "Check SonarQube Quality Gate Status"
        "Check Kubernetes Rollout Status"
        "Rollback Last Deployment"
        "Tail Application / Pipeline Logs"
        "Quit"
    )

    select opt in "${options[@]}"; do
        case "$REPLY" in
            1) do_terraform_plan; break ;;
            2) do_terraform_apply; break ;;
            3) do_trigger_jenkins; break ;;
            4) do_check_sonarqube; break ;;
            5) do_k8s_rollout_status; break ;;
            6) do_k8s_rollback; break ;;
            7) do_tail_logs; break ;;
            8) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid option $REPLY. Please select 1-8."; break ;;
        esac
    done
done
