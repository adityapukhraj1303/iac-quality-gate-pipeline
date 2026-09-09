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

# 9. Fetch parameters from AWS SSM Parameter Store
echo "[INFO] Pulling environment parameters from AWS SSM: ${SSM_PREFIX}..."
PARAMETERS=$(aws ssm get-parameters-by-path --path "${SSM_PREFIX}" --region "${REGION}" --output json 2>/dev/null || true)

if [[ -n "$PARAMETERS" && "$PARAMETERS" != '{"Parameters":[]}' ]]; then
    CLUSTER_NAME=$(echo "$PARAMETERS" | jq -r '.Parameters[] | select(.Name | endswith("/cluster_name")) | .Value')
    ECR_URL=$(echo "$PARAMETERS" | jq -r '.Parameters[] | select(.Name | endswith("/ecr_repository_url")) | .Value')
    VPC_ID=$(echo "$PARAMETERS" | jq -r '.Parameters[] | select(.Name | endswith("/vpc_id")) | .Value')

    echo "=========================================================="
    echo " Discovered Infrastructure Coordinates from SSM:"
    echo " EKS Cluster Name: ${CLUSTER_NAME}"
    echo " ECR Repository:   ${ECR_URL}"
    echo " VPC ID:           ${VPC_ID}"
    echo "=========================================================="

    if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "null" ]]; then
        echo "[INFO] Updating kubeconfig for ${CLUSTER_NAME}..."
        aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"
        aws eks wait cluster-active --region "${REGION}" --name "${CLUSTER_NAME}"
        echo "[OK] Kubeconfig updated successfully and cluster is active."
    else
        echo "[WARN] SSM exists but cluster name is empty. Run Terraform and publish the cluster metadata first."
    fi
else
    echo "[INFO] No parameters found under ${SSM_PREFIX} yet. Run Terraform to provision the infrastructure."
    echo "[INFO] To provision the environment on a fresh AWS account: bash scripts/setup-all.sh ${ENV}"
fi

echo "[INFO] Helpful next steps:"
echo "  1) bash scripts/setup.sh ${ENV}  -> reconnect to cluster + install/repair monitoring"
echo "  2) bash scripts/deploy.sh ${ENV} latest -> deploy app to Kubernetes"
echo "  3) bash scripts/rollback.sh ${ENV} -> roll back the last deployment"
echo "[SUCCESS] Instance bootstrap completed. Environment is ready for pipeline operations!"
