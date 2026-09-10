# Operator setup guide for the iac-quality-gate-pipeline

This guide reflects the actual repo behavior and the real values defined in the codebase. The project is pinned to AWS region `ap-south-1`, the Terraform environment is `dev`, the cluster name is `iac-pipeline-dev-eks`, and the ECR repository name created by Terraform is `iac-pipeline-app-dev`.

This is the order the stack must actually be stood up:

1. Install the required local tools.
2. Optional local smoke test with Minikube.
3. Configure AWS CLI and IAM context.
4. Run `terraform apply` for the dev environment.
5. Verify the five SSM parameters exist.
6. Run `scripts/bootstrap.sh dev` and connect `kubectl`.
7. Build and push the app image to ECR.
8. Run `scripts/deploy.sh dev latest`.
9. Install and verify monitoring.
10. Configure Jenkins and the SonarQube server integration.
11. Validate the full stack end-to-end.

---

## 1) Prerequisites

This repo expects a Linux-based environment (Ubuntu/Debian is the most typical choice). The following packages and tools are required before any real AWS deployment.

### 1.1 Install system packages

```bash
sudo apt-get update
sudo apt-get install -y \
  curl unzip git jq ca-certificates \
  apt-transport-https software-properties-common \
  docker.io

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$USER"
newgrp docker
```

### 1.2 Install AWS CLI v2

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

### 1.3 Install Terraform

```bash
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update
sudo apt-get install -y terraform
terraform version
```

### 1.4 Install kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### 1.5 Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### 1.6 Install eksctl

```bash
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin/
eksctl version
```

### 1.7 Install Minikube (local-only testing before real EKS)

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
```

### 1.8 Confirm environment variables

```bash
export AWS_REGION=ap-south-1
aws configure set region ap-south-1
```

---

## 2) Local smoke test with Minikube (optional but recommended first)

Before creating AWS infrastructure, it is useful to validate that the Kubernetes YAML is syntactically valid and that the app deploys in a local cluster.

### 2.1 Start Minikube

```bash
minikube start --driver=docker --memory 4096 --cpus 2
kubectl config use-context minikube
kubectl get nodes
```

### 2.2 Create the dev namespace

```bash
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
```

### 2.3 Apply the manifests

```bash
kubectl apply -f k8s/configmap.yaml -n dev
kubectl apply -f k8s/service.yaml -n dev
kubectl apply -f k8s/ingress.yaml -n dev
kubectl apply -f k8s/hpa.yaml -n dev
kubectl apply -f k8s/deployment.yaml -n dev
```

### 2.4 Verify the deployment and health endpoint

```bash
kubectl rollout status deployment/iac-quality-gate-app -n dev --timeout=180s
kubectl get pods -n dev -l app=iac-quality-gate-app
POD=$(kubectl get pods -n dev -l app=iac-quality-gate-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n dev "$POD" -- curl -s -f http://localhost:8080/health
```

This is a cheap validation step before spending money on AWS resources. It confirms the deployment and service YAML is valid and the app responds on `/health`.

---

## 3) AWS CLI configuration

The repo assumes the caller is authenticated with AWS and has an IAM role or profile active. The region is `ap-south-1` throughout the project.

### 3.1 Configure AWS CLI profile

```bash
aws configure --profile dev
export AWS_PROFILE=dev
export AWS_REGION=ap-south-1
aws configure set region ap-south-1 --profile dev
```

### 3.2 Verify AWS access

```bash
aws sts get-caller-identity --profile dev
```

Expected output includes:
- AWS account ID
- ARN of the active IAM principal
- user or role name

If this fails, fix IAM access first; the rest of the stack depends on an authenticated AWS identity.

---

## 4) Terraform

The Terraform root module is in the `terraform/` directory and the dev environment variables file is `terraform/environments/dev/terraform.tfvars`.

### 4.1 Initialize and review the plan

```bash
cd terraform
terraform init -backend=false -input=false
terraform plan -var-file="environments/dev/terraform.tfvars" -no-color
```

### 4.2 Apply the dev environment

```bash
terraform apply -auto-approve -var-file="environments/dev/terraform.tfvars" -no-color
```

This provision creates the VPC, ECR repository, IAM roles, EKS cluster, and writes the SSM metadata used by the rest of the repo.

### 4.3 Verify the five SSM parameters before proceeding

The exact SSM verification command is:

```bash
aws ssm get-parameters-by-path \
  --path "/iac-pipeline/dev" \
  --recursive \
  --query "Parameters[*].[Name,Value]" \
  --output table
```

The repo publishes these exact keys:
- `/iac-pipeline/dev/cluster_name`
- `/iac-pipeline/dev/cluster_endpoint`
- `/iac-pipeline/dev/ecr_repository_url`
- `/iac-pipeline/dev/vpc_id`
- `/iac-pipeline/dev/grafana_url`

Do not continue to `bootstrap.sh` or `deploy.sh` until these values exist.

---

## 5) EKS cluster

The cluster created by Terraform is named:

```text
iac-pipeline-dev-eks
```

The repo root logic is built around that name and the SSM parameter `/iac-pipeline/dev/cluster_name`.

### 5.1 Connect kubectl to the cluster

The repository helper script does the cluster lookup and kubeconfig update:

```bash
cd ..
bash scripts/bootstrap.sh dev
```

This script reads the cluster name from SSM and then runs the EKS kubeconfig update. If the cluster metadata is missing, it can fail early with a clear message instead of continuing to `kubectl` commands.

### 5.2 Manual EKS kubeconfig update if needed

```bash
aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks
kubectl get nodes
```

### 5.3 Verify node readiness

```bash
kubectl get nodes
kubectl get pods -A
```

Nodes must show `Ready` before continuing with app deployment and monitoring installation.

---

## 6) Docker + ECR

Terraform creates the ECR repository and publishes its URL as `/iac-pipeline/dev/ecr_repository_url`.

### 6.1 Get the ECR repository URL from SSM

```bash
REPO=$(aws ssm get-parameter --name "/iac-pipeline/dev/ecr_repository_url" --query 'Parameter.Value' --output text)
echo "$REPO"
```

The repo created by Terraform is named `iac-pipeline-app-dev`, and the repo URL resolves to that repository.

### 6.2 Log in to ECR and build the image

```bash
REGISTRY_HOST=$(echo "$REPO" | cut -d'/' -f1)
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin "$REGISTRY_HOST"

docker build -t "$REPO":latest -t "$REPO":dev -f docker/Dockerfile .
```

### 6.3 Push the image

```bash
docker push "$REPO":latest
docker push "$REPO":dev
```

This is the image the Kubernetes deployment later references using the `bash-microservice` container name.

---

## 7) Kubernetes deployment

The app deployment is driven by `scripts/deploy.sh` and the Kubernetes manifest in `k8s/deployment.yaml`.

### 7.1 Run the app deployment

From the repo root:

```bash
bash scripts/deploy.sh dev latest
```

The script:
- reads `/iac-pipeline/dev/cluster_name`
- refreshes kubeconfig
- validates Docker is available
- applies the Kubernetes configmap, service, ingress, hpa, and deployment manifests
- sets the container image using `kubectl set image deployment/iac-quality-gate-app bash-microservice=<ECR_REPO>:latest`
- waits for rollout completion
- runs a smoke test against `/health`

### 7.2 Verify rollout and app health

```bash
kubectl rollout status deployment/iac-quality-gate-app -n dev --timeout=180s
kubectl get pods -n dev -l app=iac-quality-gate-app
POD=$(kubectl get pods -n dev -l app=iac-quality-gate-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n dev "$POD" -- curl -s -f http://localhost:8080/health
```

Expected response includes a JSON payload with a `status` field equal to `ok`, matching the smoke-test logic in `scripts/deploy.sh`.

---

## 8) Prometheus + Grafana

The repo includes monitoring configuration under `monitoring/` and the `scripts/setup.sh` and `scripts/monitoring.sh` flow.

### 8.1 Install or repair monitoring

From the repo root:

```bash
bash scripts/setup.sh dev
```

If you only want to connect the cluster and skip monitoring, use:

```bash
SKIP_MONITORING=true bash scripts/setup.sh dev
```

### 8.2 Verify monitoring resources

```bash
kubectl get pods -A | grep -E 'prometheus|grafana|alertmanager'
kubectl get svc -A | grep -E 'prometheus|grafana|alertmanager'
```

### 8.3 Get the Grafana admin password

```bash
bash scripts/monitoring.sh password
```

### 8.4 Port-forward Grafana to the local machine

```bash
bash scripts/monitoring.sh port-forward grafana
```

Then open:

```text
http://localhost:3000
```

Use the admin user and the password output from the previous step. Prometheus can also be reached through the same monitoring script or a direct port-forward if needed.

---

## 9) Jenkins

The repo includes the Jenkins pipeline in `jenkins/Jenkinsfile` and the Sonar configuration in `jenkins/sonar-project.properties`.

### 9.1 Install Jenkins

The project includes a local Docker Compose stack in `docker/docker-compose.yml` for local testing, but for real AWS EKS deployment the Jenkins controller should run in a reachable environment with the required agent tools installed.

A typical local stack test is:

```bash
docker compose -f docker/docker-compose.yml up -d
```

The Jenkins service is exposed locally by the compose file and the pipeline is designed for Jenkins declarative builds.

### 9.2 Initial unlock and setup

When Jenkins is first started:
- open the Jenkins UI
- complete the initial admin unlock step
- install the recommended plugins or at least the plugins used by this pipeline

### 9.3 Required SonarQube integration name

This repo requires the SonarQube integration name to be exactly:

```text
SonarQube-Server
```

This is referenced in the Jenkinsfile as:

```groovy
withSonarQubeEnv('SonarQube-Server') {
```

If this server is not configured under `Manage Jenkins` > `System`, the build will fail in the Sonar stage.

### 9.4 Required agent tools on the Jenkins node

The Jenkins agent must have the following installed and available on PATH:
- AWS CLI v2
- Docker
- kubectl
- Terraform
- sonar-scanner

The pipeline also expects the Jenkins agent to have AWS access through an IAM instance profile or equivalent AWS credentials.

### 9.5 No explicit credential IDs are used

The pipeline does not reference a `credentialsId` in the Jenkinsfile. The documented setup expects IAM-based auth from the agent, not a stored Jenkins secret credential.

### 9.6 Four pipeline parameters

The Jenkins pipeline in `jenkins/Jenkinsfile` defines these four parameters.

1. `ENVIRONMENT`
   - Values: `dev` or `prod`
   - Purpose: chooses the AWS environment and SSM path to use.

2. `IMAGE_TAG`
   - Default: `build-${BUILD_NUMBER}`
   - Purpose: tags the Docker image built in the pipeline.

3. `SKIP_QUALITY_GATE`
   - Default: `false`
   - Purpose: emergency override to bypass SonarQube quality gate enforcement.

4. `AUTO_ROLLBACK`
   - Default: `true`
   - Purpose: attempts a Kubernetes rollback when the smoke-test stage fails.

Example build parameters:

```bash
ENVIRONMENT=dev
IMAGE_TAG=build-42
SKIP_QUALITY_GATE=false
AUTO_ROLLBACK=true
```

---

## 10) Known issues and how the infra handles them

This section covers the failure modes that are explicitly guarded by the repo, and the exact behavior of the code when they happen.

### 10.1 Running deploy.sh or bootstrap.sh before Terraform has populated SSM

What the failure looks like:
- `scripts/deploy.sh` reads `/iac-pipeline/${ENV}/cluster_name` and then fails if the value is missing.
- The script exits with a clear error telling the operator to run Terraform first.

Why it happens:
- The repo expects these SSM values to be created by the Terraform root module in `terraform/main.tf` after `terraform apply`.
- The deploy script is intentionally written to fail before it does a `kubectl` or EKS action if the metadata is absent.

What the repo already does to guard against it:
- `terraform/main.tf` writes the five SSM parameters:
  - `/iac-pipeline/${var.environment}/cluster_name`
  - `/iac-pipeline/${var.environment}/cluster_endpoint`
  - `/iac-pipeline/${var.environment}/ecr_repository_url`
  - `/iac-pipeline/${var.environment}/vpc_id`
  - `/iac-pipeline/${var.environment}/grafana_url`
- `scripts/deploy.sh` checks for `/iac-pipeline/${ENV}/cluster_name` before calling `aws eks update-kubeconfig`.

What to do manually if it still occurs:

```bash
cd terraform
terraform apply -auto-approve -var-file="environments/dev/terraform.tfvars"
aws ssm get-parameters-by-path --path "/iac-pipeline/dev" --recursive --query "Parameters[*].[Name,Value]" --output table
```

Then rerun:

```bash
cd ..
bash scripts/bootstrap.sh dev
bash scripts/deploy.sh dev latest
```

There is no automatic retry in the script beyond the explicit exit and error message; this is a preflight guard, not a self-healing flow.

### 10.2 SSM GetParametersByPath permission gaps if the IAM policy is narrowed incorrectly

What the failure looks like:
- AWS CLI calls such as `aws ssm get-parameters-by-path --path "/iac-pipeline/dev"` fail with access denied.
- The bootstrap or deploy flow cannot discover the EKS cluster metadata from SSM.

Why it happens:
- The repo uses path-based reads and exact-parameter reads for cluster, endpoint, ECR, VPC, and Grafana values.
- If an IAM policy narrows access too aggressively or removes the required `ssm:GetParametersByPath` permission, discovery breaks even though Terraform created the parameters.

What the repo already does to guard against it:
- The IAM module now splits the SSM permissions into:
  - `SSMPathAccess` for `ssm:GetParametersByPath`
  - `SSMExactParameterAccess` for `ssm:GetParameter` and `ssm:GetParameters`
- The path is scoped to:

```text
arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/iac-pipeline/${var.environment}/*
```

and the exact parameter values are scoped to the five parameter ARNs defined in the module.

What to do manually if it still occurs:
- check the policy attached to the EC2 or runner role
- ensure `ssm:GetParametersByPath` is still allowed for `/iac-pipeline/${ENV}/*`
- ensure `ssm:GetParameter` and `ssm:GetParameters` remain allowed for the exact parameter ARNs

### 10.3 Container name mismatches between the manifest and deploy scripts

What the failure looks like:
- `kubectl set image deployment/iac-quality-gate-app bash-microservice=...` fails with a container-not-found error.

Why it happens:
- The container name in the deployment manifest must match the name used by the `kubectl set image` command exactly.

What the repo already does to guard against it:
- The manifest in `k8s/deployment.yaml` defines:

```yaml
containers:
  - name: bash-microservice
```

- The deploy script uses:

```bash
kubectl set image deployment/iac-quality-gate-app bash-microservice="${IMAGE_TARGET}" -n "${NAMESPACE}"
```

- The Jenkins pipeline does the same thing.

What to do manually if it still occurs:
- confirm the container name in the deployment is still exactly `bash-microservice`
- do not rename the container in one place without updating both the manifest and the `kubectl set image` commands

### 10.4 Jenkins builds failing because SonarQube-Server is not configured yet

What the failure looks like:
- the pipeline reaches the SonarQube stage and fails because the server connection is not configured in Jenkins

Why it happens:
- The Jenkinsfile explicitly calls:

```groovy
withSonarQubeEnv('SonarQube-Server')
```

and waits for a quality gate result.

What the repo already does to guard against it:
- It does not auto-create the SonarQube integration.
- It expects the operator to configure `Manage Jenkins` > `System` first.

What to do manually if it still occurs:
- in Jenkins, go to `Manage Jenkins` > `System`
- add a SonarQube server named exactly `SonarQube-Server`
- ensure the Jenkins agent has `sonar-scanner` installed and on PATH
- ensure the agent has AWS CLI/Docker/kubectl/Terraform available

---

## 11) Final verification checklist

Use this final command list as the end-to-end health check for the whole stack.

### 11.1 Terraform and SSM

```bash
cd terraform
terraform init -backend=false -input=false
terraform plan -var-file="environments/dev/terraform.tfvars"
terraform apply -auto-approve -var-file="environments/dev/terraform.tfvars"

aws ssm get-parameters-by-path \
  --path "/iac-pipeline/dev" \
  --recursive \
  --query "Parameters[*].[Name,Value]" \
  --output table
```

### 11.2 Cluster connectivity

```bash
cd ..
aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks
kubectl get nodes
kubectl get pods -A
```

### 11.3 Bootstrap and deploy

```bash
bash scripts/bootstrap.sh dev
bash scripts/deploy.sh dev latest
kubectl rollout status deployment/iac-quality-gate-app -n dev --timeout=180s
kubectl get pods -n dev -l app=iac-quality-gate-app
POD=$(kubectl get pods -n dev -l app=iac-quality-gate-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n dev "$POD" -- curl -s -f http://localhost:8080/health
```

### 11.4 ECR image validation

```bash
REPO=$(aws ssm get-parameter --name "/iac-pipeline/dev/ecr_repository_url" --query 'Parameter.Value' --output text)
aws ecr describe-images --repository-name iac-pipeline-app-dev --region ap-south-1 --output table
```

### 11.5 Monitoring validation

```bash
bash scripts/monitoring.sh status
bash scripts/monitoring.sh password
bash scripts/monitoring.sh port-forward grafana
```

Then open:

```text
http://localhost:3000
```

### 11.6 Jenkins validation

- Confirm Jenkins is running
- Confirm `Manage Jenkins` > `System` contains `SonarQube-Server`
- Verify the agent has Docker, AWS CLI, kubectl, Terraform, and sonar-scanner installed
- Start a build with:

```text
ENVIRONMENT=dev
IMAGE_TAG=build-1
SKIP_QUALITY_GATE=false
AUTO_ROLLBACK=true
```

The pipeline should reach the SonarQube stage, then the Terraform stage, then the ECR push, deploy stage, and smoke test.

---

## Final note

This repo is intentionally strict about startup order. The actual operational sequence is:

```bash
cd terraform
terraform apply -auto-approve -var-file="environments/dev/terraform.tfvars"
aws ssm get-parameters-by-path --path "/iac-pipeline/dev" --recursive --query "Parameters[*].[Name,Value]" --output table
cd ..
bash scripts/bootstrap.sh dev
bash scripts/deploy.sh dev latest
```

This order matches the code paths in the repo and is the safe path to first success.
