# Fresh EC2 Setup Guide for ap-south-1

This is the final setup flow for running this project on a brand-new EC2 instance in AWS region ap-south-1.

It includes:
- EC2 security group ports
- IAM role setup
- Terraform installation
- Docker installation
- AWS CLI configuration
- kubectl, Helm, eksctl installation
- EKS cluster auth fix
- EKS nodegroup creation
- project bootstrap and deployment
- Prometheus, Grafana, and Jenkins access

---

## 1) EC2 security group inbound rules

Allow only these inbound ports on the EC2 instance security group:

- 22 → SSH
- 80 → HTTP
- 443 → HTTPS
- 3000 → Grafana
- 8080 → Jenkins
- 9090 → Prometheus
- 9093 → Alertmanager

Do not expose the EKS control plane directly to the internet.

---

## 2) IAM role for the EC2 instance

Attach an IAM role with at least these permissions:

- AmazonEKSClusterPolicy
- AmazonEKSWorkerNodePolicy
- AmazonEKS_CNI_Policy
- AmazonEC2ContainerRegistryReadOnly
- AmazonSSMManagedInstanceCore
- AdministratorAccess (recommended for first setup)

Then verify AWS login:

```bash
aws sts get-caller-identity
```

For this project, the verified AWS principal is:

```bash
arn:aws:iam::567752770098:user/policy_005
```

This is the exact ARN that was used successfully for EKS Access Entry and cluster admin policy association.

> If your username is different, replace `policy_005` with your own ARN in every command below.

---

## 3) Install all required tools

Run this entire block on the EC2:

```bash
sudo apt-get update -y
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
sudo apt-get update -y
sudo apt-get install -y terraform
terraform version

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
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

---

## 4) Clone the repository

```bash
cd ~
git clone https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git
cd iac-quality-gate-pipeline
```

If the repo already exists, remove and clone again:

```bash
cd ~
rm -rf iac-quality-gate-pipeline
git clone https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git
cd iac-quality-gate-pipeline
```

---

## 5) EKS access configuration for your AWS identity

This is the exact working flow that was confirmed with the actual principal:

```bash
arn:aws:iam::567752770098:user/policy_005
```

### 5.1) Check the current AWS identity

```bash
aws sts get-caller-identity --query Arn --output text
```

Expected output:

```bash
arn:aws:iam::567752770098:user/policy_005
```

### 5.2) Update kubeconfig for the cluster

```bash
aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks
```

### 5.3) Create access entry for your AWS principal

Use your exact ARN. For this project, it is:

```bash
aws eks create-access-entry \
  --cluster-name iac-pipeline-dev-eks \
  --region ap-south-1 \
  --principal-arn arn:aws:iam::567752770098:user/policy_005 \
  --type STANDARD
```

### 5.4) Associate the cluster admin policy

```bash
aws eks associate-access-policy \
  --cluster-name iac-pipeline-dev-eks \
  --region ap-south-1 \
  --principal-arn arn:aws:iam::567752770098:user/policy_005 \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

### 5.5) Verify access

```bash
kubectl get nodes
kubectl get pods -A
```

If the command works and returns node names in `Ready` state, the EKS access configuration is successfully completed.

---

## 6) Important note about authentication mode

The earlier error:

```bash
Unsupported authentication mode update from API_AND_CONFIG_MAP to API_AND_CONFIG_MAP
```

means the system is already on the correct authentication mode and is trying to reapply the same value.

Do not keep changing it again. For this project, the working setup is already valid with `API_AND_CONFIG_MAP` and access entries.

You do not need to force-update the cluster config again unless you are intentionally changing the EKS auth mode for a different reason.

---

## 7) Create the EKS nodegroup if it is missing

A cluster can exist and still have no worker nodes. This is a very common reason for `Pending` pods.

Check nodegroups:

```bash
aws eks list-nodegroups --cluster-name iac-pipeline-dev-eks --region ap-south-1
```

If the result is empty, create the nodegroup:

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

Wait until it is active:

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

The expected result is 2 Ready nodes.

---

## 8) Terraform usage on a fresh EC2

Terraform is required only after the cluster is reachable and ready. If the cluster already exists and the EKS nodes are `Ready`, do not re-run a full Terraform create unless you truly need to recreate resources.

Install Terraform if it is missing:

```bash
sudo apt-get update -y
sudo apt-get install -y gnupg software-properties-common curl

wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update -y
sudo apt-get install -y terraform
terraform version
```

Then run:

```bash
cd ~/iac-quality-gate-pipeline/terraform
terraform init
terraform plan
terraform apply -auto-approve
```

If the cluster and AWS resources already exist, the safer flow is:

1. `kubectl get nodes` to confirm EKS is accessible.
2. Create missing nodegroup if necessary.
3. Continue with project bootstrap and deployment.

---

## 9) Run the project bootstrap and deployment

Once the cluster is active and nodes are ready:

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

## 10) Monitoring access

Grafana and Prometheus are expected to be installed and exposed using the configured ports.

Access them using:

- Grafana: `http://<EC2_PUBLIC_IP>:3000`
- Prometheus: `http://<EC2_PUBLIC_IP>:9090`
- Jenkins: `http://<EC2_PUBLIC_IP>:8080`

---

## 11) Final working principle for this project

The correct AWS identity flow is:

```text
AWS IAM user / principal
      │
      ▼
arn:aws:iam::567752770098:user/policy_005
      │
      ▼
EKS Access Entry
      │
      ▼
AmazonEKSClusterAdminPolicy
      │
      ▼
kubectl access to the cluster
      │
      ▼
EKS nodes become Ready
```

This is the key fact to remember when setting up a new EC2 instance:

- Check your AWS ARN.
- Use that exact ARN in `create-access-entry`.
- Attach `AmazonEKSClusterAdminPolicy`.
- Run `aws eks update-kubeconfig`.
- Verify with `kubectl get nodes`.
- If nodegroup is missing, create it.
- Only then proceed with Terraform and project deployment.

This is the stable, verified setup for a fresh EC2 environment in ap-south-1.

---

## 9) Access Grafana and Prometheus

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

---

## 10) Access Jenkins

```bash
kubectl port-forward -n dev svc/jenkins 8080:8080
```

Open:

```text
http://<EC2_PUBLIC_IP>:8080
```

---

## 11) Final full copy-paste sequence for a new EC2

Use this if you want a single clean startup block:

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

aws eks update-cluster-config \
  --name iac-pipeline-dev-eks \
  --region ap-south-1 \
  --access-config '{"authenticationMode":"API_AND_CONFIG_MAP"}'

aws eks wait cluster-active --name iac-pipeline-dev-eks --region ap-south-1

aws eks create-access-entry \
  --cluster-name iac-pipeline-dev-eks \
  --region ap-south-1 \
  --principal-arn $(aws sts get-caller-identity --query Arn --output text) \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name iac-pipeline-dev-eks \
  --region ap-south-1 \
  --principal-arn $(aws sts get-caller-identity --query Arn --output text) \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster

aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks

aws eks create-nodegroup \
  --cluster-name iac-pipeline-dev-eks \
  --nodegroup-name iac-pipeline-dev-ng \
  --node-role arn:aws:iam::567752770098:role/iac-pipeline-dev-eks-node-role \
  --subnets subnet-078600e19f5422a1f subnet-0d90776c8e2195e67 \
  --instance-types t3.small \
  --scaling-config minSize=2,maxSize=5,desiredSize=2 \
  --region ap-south-1

aws eks wait nodegroup-active \
  --cluster-name iac-pipeline-dev-eks \
  --nodegroup-name iac-pipeline-dev-ng \
  --region ap-south-1

kubectl get nodes
kubectl get pods -A

bash scripts/bootstrap.sh dev
bash scripts/setup.sh dev
bash scripts/deploy.sh dev latest
```

---

## 12) Final note

For this project, the exact flow is:

1. attach IAM role to EC2
2. allow required inbound ports
3. install Terraform, Docker, kubectl, Helm, eksctl
4. set AWS region to ap-south-1
5. fix EKS auth for the EC2 principal
6. create the missing nodegroup
7. bootstrap the project
8. deploy app
9. access Grafana, Prometheus, and Jenkins

This is the reliable fresh-instance path for this repo.
