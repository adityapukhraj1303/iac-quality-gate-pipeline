# EC2 Setup Guide for iac-quality-gate-pipeline

This file contains the copy-paste commands to run this project on a fresh EC2 instance.

## 1) Install required tools

```bash
sudo apt-get update -y
sudo apt-get install -y git curl unzip jq ca-certificates software-properties-common gnupg wget
```

## 2) Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

## 3) Install AWS CLI v2

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

## 4) Install Terraform

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
sudo apt-get update -y
sudo apt-get install -y terraform
terraform version
```

## 5) Install kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

## 6) Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

## 7) Configure AWS access and region

```bash
export AWS_REGION=ap-south-1
aws configure set region ap-south-1
aws sts get-caller-identity
```

> Attach an EC2 IAM role with AWS permissions before running this, or use your AWS credentials.

## 8) Clone the repository

```bash
cd ~
git clone https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git
cd iac-quality-gate-pipeline
```

## 9) Bootstrap the project on the EC2 instance

```bash
bash scripts/bootstrap.sh dev
```

This script will:
- install missing tools
- check AWS identity
- look for the cluster in SSM and AWS EKS
- reconnect to the existing cluster if found
- create the Terraform infrastructure automatically if the cluster is missing

## 10) Setup the cluster and monitoring

```bash
bash scripts/setup.sh dev
```

This will:
- update kubeconfig
- wait for the cluster to be active
- verify nodes
- install/repair Prometheus and Grafana

## 11) Deploy the application

```bash
bash scripts/deploy.sh dev latest
```

## 12) Verify the pods and cluster

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pods -n dev
kubectl get svc -n dev
```

## 13) Access Prometheus and Grafana

```bash
bash scripts/monitoring.sh status
bash scripts/monitoring.sh password
bash scripts/monitoring.sh port-forward grafana
```

Open:
- http://localhost:3000

Then:

```bash
bash scripts/monitoring.sh port-forward prometheus
```

Open:
- http://localhost:9090

## 14) Run Jenkins and SonarQube locally

```bash
docker compose -f docker/docker-compose.yml up -d
docker compose -f docker/docker-compose.yml ps
```

Then access:
- Jenkins: http://<EC2_PUBLIC_IP>:8085
- SonarQube: http://<EC2_PUBLIC_IP>:9000

## 15) Full one-shot setup block

```bash
sudo apt-get update -y && \
sudo apt-get install -y git curl unzip jq ca-certificates software-properties-common gnupg wget && \
curl -fsSL https://get.docker.com | sh && \
sudo systemctl enable --now docker && \
sudo usermod -aG docker $USER && \
newgrp docker && \
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
unzip awscliv2.zip && \
sudo ./aws/install && \
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null && \
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null && \
sudo apt-get update -y && \
sudo apt-get install -y terraform && \
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
chmod +x kubectl && sudo mv kubectl /usr/local/bin/ && \
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
cd ~ && \
git clone https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git && \
cd iac-quality-gate-pipeline && \
export AWS_REGION=ap-south-1 && \
aws configure set region ap-south-1 && \
aws sts get-caller-identity && \
bash scripts/bootstrap.sh dev && \
bash scripts/setup.sh dev && \
bash scripts/deploy.sh dev latest
```

## 16) Git Bash commands to save changes to GitHub

From your local machine, run:

```bash
cd /c/Users/ADITYA\ PUKHRAJ/OneDrive/Desktop/DevOps\ 2.0/iac-quality-gate-pipeline
git status
git add .
git commit -m "feat: add EC2 quick setup guide"
git push origin main
```

If the repo is not yet connected, run:

```bash
git remote add origin https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git
git branch -M main
git push -u origin main
```
