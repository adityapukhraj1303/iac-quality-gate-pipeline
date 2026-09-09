#!/usr/bin/env bash
# ==============================================================================
# AWS Instance Bootstrapper
#
# Configures ANY fresh AWS EC2/EKS instance to run this project:
# 1. Idempotently installs Terraform, Docker, kubectl, Helm, AWS CLI, and socat
# 2. Authenticates via attached IAM Instance Profile (Zero hardcoded secrets!)
# 3. Pulls environment configuration dynamically from AWS SSM Parameter Store
# 4. Updates kubeconfig for immediate cluster administration
# ==============================================================================

set -eo pipefail

ENV="${1:-dev}"
REGION="${AWS_REGION:-ap-south-1}"
SSM_PREFIX="/iac-pipeline/${ENV}"

echo "=========================================================="
echo " Bootstrapping AWS Instance for iac-quality-gate-pipeline"
echo " Environment: ${ENV} | AWS Region: ${REGION}"
echo "=========================================================="

# 1. Detect Package Manager & Distro
detect_pkg_manager() {
    if command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    else
        echo "unknown"
    fi
}

PKG_MGR=$(detect_pkg_manager)
echo "[INFO] Detected package manager: ${PKG_MGR}"

# 2. Install missing core packages
install_packages() {
    echo "[INFO] Checking and installing core utility dependencies..."
    case "$PKG_MGR" in
        dnf|yum)
            sudo "$PKG_MGR" update -y
            sudo "$PKG_MGR" install -y curl tar gzip unzip git jq socat
            ;;
        apt)
            sudo apt-get update -y
            sudo apt-get install -y curl tar gzip unzip git jq socat ca-certificates apt-transport-https
            ;;
        *)
            echo "[WARN] Unknown package manager. Ensure curl, tar, jq, socat, and git are installed."
            ;;
    esac
}

install_packages

# 3. Install Docker if not present
if ! command -v docker >/dev/null 2>&1; then
    echo "[INFO] Installing Docker..."
    if [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; then
        sudo "$PKG_MGR" install -y docker
        sudo systemctl enable --now docker
        sudo usermod -aG docker "$USER" || true
    elif [[ "$PKG_MGR" == "apt" ]]; then
        curl -fsSL https://get.docker.com | sh
        sudo systemctl enable --now docker
        sudo usermod -aG docker "$USER" || true
    fi
else
    echo "[OK] Docker is already installed: $(docker --version)"
fi

# 4. Install AWS CLI v2 if not present
if ! command -v aws >/dev/null 2>&1; then
    echo "[INFO] Installing AWS CLI v2..."
    TMP_DIR=$(mktemp -d)
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "${TMP_DIR}/awscliv2.zip"
    unzip -q "${TMP_DIR}/awscliv2.zip" -d "${TMP_DIR}"
    sudo "${TMP_DIR}/aws/install"
    rm -rf "${TMP_DIR}"
else
    echo "[OK] AWS CLI is already installed: $(aws --version)"
fi

# 5. Install Terraform if not present
if ! command -v terraform >/dev/null 2>&1; then
    echo "[INFO] Installing Terraform..."
    TF_VERSION="1.7.5"
    TMP_DIR=$(mktemp -d)
    curl -s "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip" -o "${TMP_DIR}/terraform.zip"
    unzip -q "${TMP_DIR}/terraform.zip" -d "${TMP_DIR}"
    sudo mv "${TMP_DIR}/terraform" /usr/local/bin/
    rm -rf "${TMP_DIR}"
else
    echo "[OK] Terraform is already installed: $(terraform version -json | grep -o '"terraform_version":"[^"]*"' || echo 'installed')"
fi

# 6. Install kubectl if not present
if ! command -v kubectl >/dev/null 2>&1; then
    echo "[INFO] Installing kubectl..."
    K8S_VER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${K8S_VER}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
else
    echo "[OK] kubectl is already installed."
fi

# 7. Install Helm if not present
if ! command -v helm >/dev/null 2>&1; then
    echo "[INFO] Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "[OK] Helm is already installed: $(helm version --short)"
fi

# 8. Verify AWS IAM Authentication
echo "[INFO] Verifying AWS IAM Instance Profile authentication..."
CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null || true)
if [[ -n "$CALLER_IDENTITY" ]]; then
    ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r .Account)
    ARN=$(echo "$CALLER_IDENTITY" | jq -r .Arn)
    echo "[OK] Authenticated as: ${ARN} (Account: ${ACCOUNT_ID})"
else
    echo "[WARN] No IAM role detected on this instance! AWS commands may require credentials."
fi

# 9. Resolve cluster state dynamically: reuse existing cluster or create it if needed
connect_to_cluster() {
    local cluster_name="$1"
    if [[ -n "$cluster_name" && "$cluster_name" != "null" && "$cluster_name" != "None" ]]; then
        echo "[INFO] Updating kubeconfig for ${cluster_name}..."
        aws eks update-kubeconfig --region "${REGION}" --name "${cluster_name}"
        aws eks wait cluster-active --region "${REGION}" --name "${cluster_name}"
        echo "[OK] Kubeconfig updated successfully and cluster is active."
        return 0
    fi
    return 1
}

create_infrastructure_if_needed() {
    echo "[INFO] No active EKS cluster found in SSM or AWS. Creating infrastructure now..."
    cd "${PROJECT_ROOT}/terraform"
    terraform init -upgrade=false -input=false
    terraform apply -auto-approve -input=false -var-file="environments/${ENV}/terraform.tfvars"
    echo "[OK] Terraform apply completed. Refreshing cluster metadata..."
}

echo "[INFO] Pulling environment parameters from AWS SSM: ${SSM_PREFIX}..."
PARAMETERS=$(aws ssm get-parameters-by-path --path "${SSM_PREFIX}" --region "${REGION}" --output json 2>/dev/null || true)
CLUSTER_NAME=""
ECR_URL=""
VPC_ID=""

if [[ -n "$PARAMETERS" && "$PARAMETERS" != '{"Parameters":[]}' ]]; then
    CLUSTER_NAME=$(echo "$PARAMETERS" | jq -r '.Parameters[] | select(.Name | endswith("/cluster_name")) | .Value')
    ECR_URL=$(echo "$PARAMETERS" | jq -r '.Parameters[] | select(.Name | endswith("/ecr_repository_url")) | .Value')
    VPC_ID=$(echo "$PARAMETERS" | jq -r '.Parameters[] | select(.Name | endswith("/vpc_id")) | .Value')
fi

if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "null" && "$CLUSTER_NAME" != "None" ]]; then
    echo "=========================================================="
    echo " Discovered Infrastructure Coordinates from SSM:"
    echo " EKS Cluster Name: ${CLUSTER_NAME}"
    echo " ECR Repository:   ${ECR_URL}"
    echo " VPC ID:           ${VPC_ID}"
    echo "=========================================================="
    connect_to_cluster "$CLUSTER_NAME" || echo "[WARN] Cluster metadata was found but kubeconfig connection failed. Continuing with recovery checks..."
else
    echo "[INFO] No cluster metadata found under ${SSM_PREFIX}. Checking whether the cluster already exists in AWS..."
    CLUSTER_NAME=$(aws eks list-clusters --region "${REGION}" --query "clusters[?@ == 'iac-pipeline-${ENV}-eks'] | [0]" --output text 2>/dev/null || true)
    if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "None" && "$CLUSTER_NAME" != "null" ]]; then
        echo "[INFO] Found an existing EKS cluster in AWS: ${CLUSTER_NAME}"
        connect_to_cluster "$CLUSTER_NAME"
    else
        echo "[INFO] No cluster found in AWS. Creating the project infrastructure now."
        create_infrastructure_if_needed || {
            echo "[ERROR] Terraform infrastructure creation failed. Check AWS permissions and variables." >&2
            exit 1
        }
        PARAMETERS=$(aws ssm get-parameters-by-path --path "${SSM_PREFIX}" --region "${REGION}" --output json 2>/dev/null || true)
        CLUSTER_NAME=$(echo "$PARAMETERS" | jq -r '.Parameters[] | select(.Name | endswith("/cluster_name")) | .Value' 2>/dev/null || true)
        if ! connect_to_cluster "$CLUSTER_NAME"; then
            echo "[ERROR] Cluster creation completed but kubeconfig connection still failed." >&2
            exit 1
        fi
    fi
fi

echo "[INFO] Helpful next steps:"
echo "  1) bash scripts/setup.sh ${ENV}  -> reconnect to cluster + install/repair monitoring"
echo "  2) bash scripts/deploy.sh ${ENV} latest -> deploy app to Kubernetes"
echo "  3) bash scripts/rollback.sh ${ENV} -> roll back the last deployment"
echo "[SUCCESS] Instance bootstrap completed. The EC2 instance is connected to the correct cluster or created it automatically."
