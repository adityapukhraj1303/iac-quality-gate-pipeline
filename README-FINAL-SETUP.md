# Final Fresh EC2 Setup Guide for this project

This is the final, production-ready setup guide for a brand-new EC2 instance in AWS region `ap-south-1`.

It covers:
- EC2 security group
- IAM role and policy JSON
- AWS CLI configuration
- Terraform installation
- Docker installation
- kubectl, Helm, eksctl setup
- EKS cluster creation or reuse
- EKS access entry and admin permissions
- EKS nodegroup creation if missing
- project bootstrap
- Terraform apply
- app image build and ECR push
- Prometheus and Grafana installation
- Jenkins access
- final verification steps

> Use this as your single copy-paste setup guide. It is designed to minimize issues on a fresh EC2 instance.

---

## 1) EC2 security group rules

Open the following inbound ports on the EC2 instance security group:

- 22 -> SSH
- 80 -> HTTP
- 443 -> HTTPS
- 3000 -> Grafana
- 8080 -> Jenkins
- 9090 -> Prometheus
- 9093 -> Alertmanager

Do not expose the EKS control plane directly to the internet.

---

## 2) IAM role JSON for the EC2 instance

### 2.1 Trust policy

Create `trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### 2.2 Permissions policy

Create `ec2-eks-terraform-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FullEC2Access",
      "Effect": "Allow",
      "Action": [
        "ec2:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "FullEKSAccess",
      "Effect": "Allow",
      "Action": [
        "eks:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "FullECRAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "FullIAMAccessForTerraform",
      "Effect": "Allow",
      "Action": [
        "iam:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "FullSSMAccess",
      "Effect": "Allow",
      "Action": [
        "ssm:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchAndLogsAccess",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:*",
        "logs:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AutoscalingAndELBAccess",
      "Effect": "Allow",
      "Action": [
        "autoscaling:*",
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Route53AndACMAccess",
      "Effect": "Allow",
      "Action": [
        "route53:*",
        "acm:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "KMSAccess",
      "Effect": "Allow",
      "Action": [
        "kms:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSAccess",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity",
        "sts:AssumeRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TaggingAccess",
      "Effect": "Allow",
      "Action": [
        "tag:GetResources",
        "tag:TagResources",
        "tag:UntagResources"
      ],
      "Resource": "*"
    }
  ]
}
```

### 2.3 Create and attach the role

```bash
aws iam create-role \
  --role-name EC2-EKS-DevOps-Role \
  --assume-role-policy-document file://trust-policy.json

aws iam put-role-policy \
  --role-name EC2-EKS-DevOps-Role \
  --policy-name EC2-EKS-DevOps-Policy \
  --policy-document file://ec2-eks-terraform-policy.json

aws iam create-instance-profile \
  --instance-profile-name EC2-EKS-DevOps-Profile

aws iam add-role-to-instance-profile \
  --instance-profile-name EC2-EKS-DevOps-Profile \
  --role-name EC2-EKS-DevOps-Role
```

Then attach the instance profile to the EC2 instance from AWS Console or CLI.

---

## 3) Install required tools on the EC2 instance

Run this on a fresh Ubuntu EC2 instance:

```bash
sudo apt-get update -y
sudo apt-get install -y \
  curl unzip git jq ca-certificates gnupg lsb-release \
  software-properties-common docker.io

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$USER" || true
newgrp docker || true

# AWS CLI v2
if ! command -v aws >/dev/null 2>&1; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  sudo ./aws/install
fi
aws --version

# Terraform
if ! command -v terraform >/dev/null 2>&1; then
  wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

  sudo apt-get update -y
  sudo apt-get install -y terraform
fi
terraform version

# kubectl
if ! command -v kubectl >/dev/null 2>&1; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
fi
kubectl version --client

# Helm
if ! command -v helm >/dev/null 2>&1; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version

# eksctl
if ! command -v eksctl >/dev/null 2>&1; then
  curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
  sudo mv /tmp/eksctl /usr/local/bin
fi
eksctl version

export AWS_REGION=ap-south-1
aws configure set region ap-south-1
aws sts get-caller-identity
```

---

## 4) Clone the project

```bash
cd ~
if [ ! -d "iac-quality-gate-pipeline" ]; then
  git clone https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git
fi
cd iac-quality-gate-pipeline
```

---

## 5) EKS cluster creation or reuse

### 5.1 Check existing cluster

```bash
aws eks list-clusters --region ap-south-1 --output table
```

If your cluster already exists, connect to it:

```bash
aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks
kubectl get nodes
```

### 5.2 If cluster does not exist, create it

```bash
eksctl create cluster \
  --name iac-pipeline-dev-eks \
  --region ap-south-1 \
  --nodegroup-name standard-workers \
  --node-type t3.small \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed
```

Wait until the cluster and nodes are active.

Verify:

```bash
kubectl get nodes
```

---

## 6) EKS access for your IAM principal

This is the exact verified flow for the AWS principal used in this project.

### 6.1 Get your current ARN

```bash
aws sts get-caller-identity --query Arn --output text
```

Example output:

```bash
arn:aws:iam::567752770098:user/policy_005
```

> If your user is different, replace `policy_005` with your actual ARN in all commands below.

### 6.2 Create access entry

```bash
aws eks create-access-entry \
  --cluster-name iac-pipeline-dev-eks \
  --region ap-south-1 \
  --principal-arn arn:aws:iam::567752770098:user/policy_005 \
  --type STANDARD
```

### 6.3 Attach cluster admin policy

```bash
aws eks associate-access-policy \
  --cluster-name iac-pipeline-dev-eks \
  --region ap-south-1 \
  --principal-arn arn:aws:iam::567752770098:user/policy_005 \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

### 6.4 Update kubeconfig

```bash
aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks
kubectl get nodes
kubectl get pods -A
```

Expected result: node names shown with `Ready` status.

---

## 7) Important note about authentication mode

The earlier message:

```bash
Unsupported authentication mode update from API_AND_CONFIG_MAP to API_AND_CONFIG_MAP
```

means the cluster is already using the correct mode and the command is trying to apply the same value again. That is not the real issue.

The real solution is the successful access entry and cluster admin policy created for your IAM principal.

---

## 8) If EKS nodegroup is missing, create it

Check if nodegroups exist:

```bash
aws eks list-nodegroups --cluster-name iac-pipeline-dev-eks --region ap-south-1
```

If list is empty, create nodegroup:

```bash
aws eks create-nodegroup \
  --cluster-name iac-pipeline-dev-eks \
  --nodegroup-name iac-pipeline-dev-ng \
  --node-role arn:aws:iam::567752770098:role/iac-pipeline-dev-eks-node-role \
  --subnets subnet-078600e19f5422a1f subnet-0d90776c8e2195e67 \
  --instance-types t3.small \
  --scaling-config minSize=2,maxSize=5,desiredSize=2 \
  --region ap-south-1
```

Wait for it to become active:

```bash
aws eks wait nodegroup-active \
  --cluster-name iac-pipeline-dev-eks \
  --nodegroup-name iac-pipeline-dev-ng \
  --region ap-south-1
```

Then verify:

```bash
kubectl get nodes
kubectl get pods -A
```

Expected: 2 Ready worker nodes.

---

## 9) Run Terraform on the EC2 instance

Go to Terraform folder:

```bash
cd ~/iac-quality-gate-pipeline/terraform
terraform init
terraform plan
terraform apply -auto-approve
```

If the cluster and AWS resources already exist, do not repeatedly recreate everything unless it is truly needed. Use the existing cluster and continue with app deployment.

---

## 10) Deploy app to Kubernetes

From the repo root:

```bash
cd ~/iac-quality-gate-pipeline
bash scripts/bootstrap.sh dev
bash scripts/setup.sh dev
bash scripts/deploy.sh dev latest
```

Check status:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
```

---

## 11) Fix the app image issue (`ImagePullBackOff`)

This is the main application issue seen in the project. It means the pod cannot pull the image.

### 11.1 Check actual deployment image

```bash
kubectl get deployment iac-quality-gate-app -n dev -o jsonpath='{.spec.template.spec.containers[*].image}{"\n"}'
```

### 11.2 Check ECR repo and tags

```bash
aws ecr describe-repositories --repository-names iac-pipeline-app-dev --region ap-south-1
aws ecr list-images --repository-name iac-pipeline-app-dev --region ap-south-1 --query 'imageIds[*].imageTag' --output table
```

### 11.3 Build and push image to ECR

```bash
cd ~/iac-quality-gate-pipeline

# Build the app image locally
# If Dockerfile exists in the repo root or app folder, use the correct path

docker build -t iac-quality-gate-app:latest .

aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin 567752770098.dkr.ecr.ap-south-1.amazonaws.com

docker tag iac-quality-gate-app:latest \
  567752770098.dkr.ecr.ap-south-1.amazonaws.com/iac-pipeline-app-dev:latest

docker push 567752770098.dkr.ecr.ap-south-1.amazonaws.com/iac-pipeline-app-dev:latest
```

### 11.4 Update the deployment to the ECR image

```bash
kubectl set image deployment/iac-quality-gate-app \
  bash-microservice=567752770098.dkr.ecr.ap-south-1.amazonaws.com/iac-pipeline-app-dev:latest \
  -n dev

kubectl rollout status deployment/iac-quality-gate-app -n dev
kubectl get pods -n dev
```

If the deployment still fails, inspect the pod events:

```bash
kubectl describe pod -n dev <pod-name>
kubectl get events -n dev --sort-by='.lastTimestamp' | tail -30
```

---

## 12) Install and access monitoring tools

### 12.1 Install Prometheus and Grafana

```bash
cd ~/iac-quality-gate-pipeline
bash scripts/monitoring.sh install
bash scripts/monitoring.sh status
```

### 12.2 Get Grafana admin password

```bash
bash scripts/monitoring.sh password
```

### 12.3 Port-forward for local access

```bash
bash scripts/monitoring.sh port-forward grafana
```

Then open in browser:

- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090

If you want access through EC2 public IP instead of port-forward:

- Grafana: `http://<EC2_PUBLIC_IP>:3000`
- Prometheus: `http://<EC2_PUBLIC_IP>:9090`

---

## 13) Jenkins

Jenkins is usually exposed on port `8080`.

Access:

```bash
http://<EC2_PUBLIC_IP>:8080
```

If Jenkins is not running, check the pipeline or install it via the project Jenkins configuration as needed.

---

## 14) Final verification checklist

Run all of these on the EC2 instance:

```bash
aws sts get-caller-identity
aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A

bash scripts/monitoring.sh status
bash scripts/monitoring.sh password

kubectl get pods -n dev
kubectl get deployment iac-quality-gate-app -n dev
kubectl rollout status deployment/iac-quality-gate-app -n dev
```

You should see:
- nodes ready
- app running
- Grafana pod running
- Prometheus stack running
- service and ingress present

---

## 15) One single final command block

If you want the shortest copy-paste summary for a new EC2 instance, use this:

```bash
sudo apt-get update -y && \
sudo apt-get install -y curl unzip git jq ca-certificates gnupg lsb-release software-properties-common docker.io && \
sudo systemctl enable docker && sudo systemctl start docker && sudo usermod -aG docker "$USER" && \
newgrp docker || true && \
if ! command -v aws >/dev/null 2>&1; then curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip -q awscliv2.zip && sudo ./aws/install; fi && \
if ! command -v terraform >/dev/null 2>&1; then wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null && sudo apt-get update -y && sudo apt-get install -y terraform; fi && \
if ! command -v kubectl >/dev/null 2>&1; then curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; fi && \
if ! command -v helm >/dev/null 2>&1; then curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; fi && \
if ! command -v eksctl >/dev/null 2>&1; then curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin; fi && \
export AWS_REGION=ap-south-1 && aws configure set region ap-south-1 && aws sts get-caller-identity && \
cd ~ && if [ ! -d "iac-quality-gate-pipeline" ]; then git clone https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git; fi && \
cd iac-quality-gate-pipeline && \
aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks && \
aws eks create-access-entry --cluster-name iac-pipeline-dev-eks --region ap-south-1 --principal-arn arn:aws:iam::567752770098:user/policy_005 --type STANDARD || true && \
aws eks associate-access-policy --cluster-name iac-pipeline-dev-eks --region ap-south-1 --principal-arn arn:aws:iam::567752770098:user/policy_005 --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster || true && \
kubectl get nodes && \
cd terraform && terraform init && terraform plan && terraform apply -auto-approve && \
cd .. && bash scripts/monitoring.sh install && bash scripts/deploy.sh dev latest && \
kubectl get pods -A
```

---

## 16) Important practical note

The exact issue we identified is not a general cluster failure. The cluster is already running and healthy. The app was failing due to image pull problems. Once the image is built and pushed correctly to ECR and the deployment uses the ECR image, the app will come up properly.

The main targets are:
- correct AWS principal ARN
- EKS access entry created
- cluster admin policy attached
- kubeconfig updated
- nodegroup present and ready
- ECR image built and pushed
- deployment image corrected
- Prometheus/Grafana installed
- Jenkins reachable

At that point, the project is fully operational and the next EC2 instance can be set up using the same path without confusion.

---

## 17) GitHub save note

This file is created locally in the repository and is ready to be committed and pushed when Git is available in the terminal.

The local repo path is:

```bash
~/iac-quality-gate-pipeline
```

To save it on GitHub later, use:

```bash
git add README-FINAL-SETUP.md
git commit -m "docs: add final EC2 setup guide"
git push origin main
```

---

## 18) Final summary

This project can be set up on a fresh EC2 instance by:
1. attaching the correct IAM role
2. installing AWS CLI, Terraform, kubectl, Helm, eksctl
3. creating or reusing the EKS cluster
4. adding the current AWS principal to the cluster access entry
5. ensuring nodes are ready
6. running Terraform
7. installing monitoring
8. deploying the application with a valid ECR image
9. verifying Grafana, Prometheus, and Jenkins access

This is the final, tested setup pattern for a clean new EC2 machine.
