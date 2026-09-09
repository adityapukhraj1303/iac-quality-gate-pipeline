#!/usr/bin/env bash
set -Eeuo pipefail

# One-command EC2 bootstrap for the iac-quality-gate-pipeline project.
# This script installs the required tooling, clones the repo if needed,
# and then runs the project bootstrap flow for the selected environment.

ENVIRONMENT="${1:-dev}"
REGION="${AWS_REGION:-ap-south-1}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/iac-quality-gate-pipeline}"
REPO_URL="${REPO_URL:-https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git}"

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

echo "=========================================================="
echo " EC2 Bootstrap for iac-quality-gate-pipeline"
echo " Environment: ${ENVIRONMENT} | Region: ${REGION}"
echo "=========================================================="

if ! command -v sudo >/dev/null 2>&1; then
  echo "[INFO] sudo not found; assuming root user."
  SUDO=""
else
  SUDO="sudo"
fi

if [[ -z "${SUDO}" ]]; then
  echo "[INFO] Running as root user."
else
  echo "[INFO] Ensuring required system packages are installed..."
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y git curl unzip jq ca-certificates software-properties-common gnupg wget
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "[INFO] Installing AWS CLI..."
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
  unzip -q /tmp/awscliv2.zip -d /tmp
  ${SUDO} /tmp/aws/install
else
  echo "[OK] AWS CLI already installed: $(aws --version)"
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "[INFO] Installing Terraform..."
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | ${SUDO} tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo $VERSION_CODENAME) main" | ${SUDO} tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y terraform
else
  echo "[OK] Terraform already installed: $(terraform version -json | jq -r '.terraform_version')"
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[INFO] Installing kubectl..."
  K8S_VER="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -LO "https://dl.k8s.io/release/${K8S_VER}/bin/linux/amd64/kubectl"
  chmod +x kubectl
  ${SUDO} mv kubectl /usr/local/bin/
else
  echo "[OK] kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "[INFO] Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "[OK] Helm already installed: $(helm version --short 2>/dev/null || helm version)"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[INFO] Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi

${SUDO} systemctl enable --now docker
${SUDO} usermod -aG docker "$USER" || true

export AWS_REGION="${REGION}"
aws sts get-caller-identity --region "${REGION}" >/dev/null || fail "AWS credentials or IAM role are not configured on this EC2 instance. Attach an IAM role with AWS access first."

if [[ ! -d "${PROJECT_DIR}" ]]; then
  echo "[INFO] Cloning the project repo..."
  git clone "${REPO_URL}" "${PROJECT_DIR}"
fi

cd "${PROJECT_DIR}"

if [[ -f "scripts/bootstrap.sh" ]]; then
  echo "[INFO] Running project bootstrap..."
  bash scripts/bootstrap.sh "${ENVIRONMENT}"
else
  fail "Repository is missing scripts/bootstrap.sh. Check the clone path: ${PROJECT_DIR}"
fi

if [[ -f "scripts/setup.sh" ]]; then
  echo "[INFO] Running cluster setup and monitoring bootstrap..."
  bash scripts/setup.sh "${ENVIRONMENT}"
else
  fail "Repository is missing scripts/setup.sh."
fi

echo "=========================================================="
echo " EC2 instance is ready."
echo " Next commands:"
echo "   bash scripts/deploy.sh ${ENVIRONMENT} latest"
echo "   bash scripts/monitoring.sh status"
echo "   kubectl get nodes -A"
echo "=========================================================="
