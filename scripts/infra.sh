#!/usr/bin/env bash
# Safe Terraform entry point for the iac-quality-gate-pipeline infrastructure.

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
ENVIRONMENT="${1:-dev}"
ACTION="${2:-status}"
REGION="${AWS_REGION:-ap-south-1}"
VARS_FILE="${TERRAFORM_DIR}/environments/${ENVIRONMENT}/terraform.tfvars"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

command -v aws >/dev/null 2>&1 || fail "AWS CLI is required."
command -v terraform >/dev/null 2>&1 || fail "Terraform is required."
[[ -f "${VARS_FILE}" ]] || fail "Unknown environment: ${ENVIRONMENT}"

cd "${TERRAFORM_DIR}"

echo "[INFO] Checking AWS credentials..."
aws sts get-caller-identity --region "${REGION}" --output table

terraform init -upgrade=false -input=false >/dev/null

vpc_ids="$(aws ec2 describe-vpcs \
    --region "${REGION}" \
    --filters "Name=tag:Name,Values=iac-pipeline-${ENVIRONMENT}-vpc" \
    --query 'Vpcs[*].VpcId' --output text)"
vpc_count=0
if [[ -n "${vpc_ids}" && "${vpc_ids}" != "None" ]]; then
    vpc_count="$(wc -w <<< "${vpc_ids}")"
fi

echo "[INFO] Matching VPCs: ${vpc_count}"
if (( vpc_count > 0 )); then
    aws ec2 describe-vpcs --region "${REGION}" \
        --vpc-ids ${vpc_ids} \
        --query 'Vpcs[*].{VpcId:VpcId,Cidr:CidrBlock,State:State,Name:Tags[?Key==`Name`]|[0].Value}' \
        --output table
fi

state_has_vpc=0
if terraform state list 2>/dev/null | grep -qx 'module.vpc.aws_vpc.this'; then
    state_has_vpc=1
fi

require_safe_state() {
    (( vpc_count <= 1 )) || fail "Multiple matching VPCs found; resolve them before continuing."
    if (( vpc_count == 1 && state_has_vpc == 0 )); then
        fail "A matching AWS VPC exists outside Terraform state. Run status, verify the VPC, then import/recover it before plan/apply."
    fi
}

case "${ACTION}" in
    status)
        echo "[INFO] Terraform state resources:"
        terraform state list || true
        if (( vpc_count > 1 )); then
            echo "[WARN] Multiple matching VPCs found. Do not apply until the stale VPC is identified." >&2
        elif (( vpc_count == 1 && state_has_vpc == 0 )); then
            echo "[WARN] AWS has a matching VPC, but Terraform does not own it yet." >&2
            echo "       Import it only after confirming it is the intended VPC:" >&2
            echo "       terraform import module.vpc.aws_vpc.this <vpc-id>" >&2
        fi
        ;;
    plan)
        require_safe_state
        terraform plan -input=false -var-file="${VARS_FILE}"
        ;;
    apply)
        require_safe_state
        terraform plan -input=false -var-file="${VARS_FILE}" -out=infra.tfplan
        echo "[INFO] Plan saved to terraform/infra.tfplan"
        read -r -p "Apply this plan? [y/N] " answer
        [[ "${answer}" =~ ^[Yy]$ ]] || { echo "[INFO] Apply cancelled."; exit 0; }
        terraform apply -input=false infra.tfplan
        ;;
    *)
        fail "Usage: $0 [dev|prod] [status|plan|apply]"
        ;;
esac