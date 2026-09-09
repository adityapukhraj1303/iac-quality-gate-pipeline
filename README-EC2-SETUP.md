# Fresh EC2 Setup Guide for iac-quality-gate-pipeline

This is the final copy-paste setup guide for a brand-new Ubuntu EC2 instance.
It covers:
- Terraform
- Docker
- AWS CLI
- kubectl
- Helm
- eksctl
- EKS cluster access
- Jenkins / Prometheus / Grafana setup
- project bootstrap and deployment

> Important: attach an IAM role to the EC2 instance before running these commands.

## 1) Required inbound ports on the EC2 security group

Allow only these inbound ports:

- 22 → SSH
- 80 → HTTP
- 443 → HTTPS
- 3000 → Grafana
- 8080 → Jenkins
- 9090 → Prometheus
- 9093 → Alertmanager

Do not expose the EKS control plane directly to the internet. EKS networking is managed internally by AWS and Terraform.

## 2) IAM role for the EC2 instance

Attach a role with these permissions (minimum practical set):

- AmazonEKSClusterPolicy
- AmazonEKSWorkerNodePolicy
- AmazonEKS_CNI_Policy
- AmazonEC2ContainerRegistryReadOnly
- AmazonSSMManagedInstanceCore
- AdministratorAccess (easiest for first setup)

After attaching the role, run:

```bash
aws sts get-caller-identity
```

You should see an ARN like:

```bash
arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
```

## 3) Install required tools on the EC2 instance

Run this whole block:

```bash
sudo apt-get update
sudo apt-get install -y \
  curl unzip git jq ca-certificates \
  apt-transport-https software-properties-common \
  docker.io

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform
terraform version

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

export AWS_REGION=ap-south-1
aws configure set region ap-south-1
aws sts get-caller-identity
```

## 4) Clone the project

```bash
cd ~
git clone https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git
cd iac-quality-gate-pipeline
```

If the folder already exists, use:

```bash
cd ~
rm -rf iac-quality-gate-pipeline
git clone https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git
cd iac-quality-gate-pipeline
```

## 5) Bootstrap and run the project

### If the cluster already exists

```bash
bash scripts/bootstrap.sh dev
bash scripts/setup.sh dev
bash scripts/deploy.sh dev latest
```

### If the cluster was deleted or does not exist

Run the same commands below. The bootstrap logic can reconnect to the cluster if it exists or rebuild infrastructure when it is missing:

```bash
bash scripts/bootstrap.sh dev
bash scripts/setup.sh dev
bash scripts/deploy.sh dev latest
```

## 6) Check core resources

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
```

## 7) Fix EKS auth on a fresh EC2 instance

If you see this error:

```bash
error: You must be logged in to the server (the server has asked for the client to provide credentials)
```

then the EC2 IAM role or user is not allowed by the cluster. Fix it with:

```bash
aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks
kubectl get nodes
```

If it still fails, map your current IAM principal to the cluster:

```bash
eksctl create iamidentitymapping \
  --cluster iac-pipeline-dev-eks \
  --region ap-south-1 \
  --arn $(aws sts get-caller-identity --query Arn --output text) \
  --username admin \
  --group system:masters
```

Then test again:

```bash
kubectl get nodes
kubectl get pods -A
```

## 8) Access Grafana, Prometheus, and Jenkins

### Grafana

```bash
bash scripts/monitoring.sh status
bash scripts/monitoring.sh password
bash scripts/monitoring.sh port-forward grafana
```

Open:

```text
http://<EC2_PUBLIC_IP>:3000
```

### Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Open:

```text
http://<EC2_PUBLIC_IP>:9090
```

### Jenkins

```bash
kubectl port-forward -n dev svc/jenkins 8080:8080
```

Open:

```text
http://<EC2_PUBLIC_IP>:8080
```

## 9) Final full copy-paste script for a brand-new EC2

Use this if you want a single clean setup block:

```bash
sudo apt-get update
sudo apt-get install -y \
  curl unzip git jq ca-certificates \
  apt-transport-https software-properties-common \
  docker.io

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

export AWS_REGION=ap-south-1
aws configure set region ap-south-1
aws sts get-caller-identity

cd ~
git clone https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git
cd iac-quality-gate-pipeline

bash scripts/bootstrap.sh dev
bash scripts/setup.sh dev
bash scripts/deploy.sh dev latest

aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks
kubectl get nodes

eksctl create iamidentitymapping \
  --cluster iac-pipeline-dev-eks \
  --region ap-south-1 \
  --arn $(aws sts get-caller-identity --query Arn --output text) \
  --username admin \
  --group system:masters

kubectl get nodes
kubectl get pods -A
```

## 10) GitHub save commands

From your local machine, run:

```bash
cd /c/Users/ADITYA\ PUKHRAJ/OneDrive/Desktop/DevOps\ 2.0/iac-quality-gate-pipeline
git status
git add .
git commit -m "docs: add fresh EC2 setup guide"
git push origin main
```

If the remote is not configured:

```bash
git remote add origin https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git
git branch -M main
git push -u origin main
```

## 11) Final note

This setup is correct for a clean EC2 reset:
- new instance
- IAM role attached
- required ports opened
- required tools installed
- AWS login validated
- cluster auth mapped
- project deployed

If any step fails, the most common problem is not Terraform or Docker — it is EKS IAM authorization. The fix is the `eksctl create iamidentitymapping` step above.
