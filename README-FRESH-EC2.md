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

Example output:

```bash
{
  "UserId": "AIDAYIMFTYIZA3ZDVJUY2",
  "Account": "567752770098",
  "Arn": "arn:aws:iam::567752770098:user/access_001"
}
```

---

## 3) Install all required tools

Run this entire block on the EC2:

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

## 5) Fix EKS authentication for the EC2 identity

Your cluster is active, but the EC2 principal must be allowed to access it.

First switch the cluster auth mode to API_AND_CONFIG_MAP:

```bash
aws eks update-cluster-config \
  --name iac-pipeline-dev-eks \
  --region ap-south-1 \
  --access-config '{"authenticationMode":"API_AND_CONFIG_MAP"}'
```

Then wait for the cluster to be active:

```bash
aws eks wait cluster-active --name iac-pipeline-dev-eks --region ap-south-1
```

Now add the current EC2 identity to the cluster:

```bash
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
```

Then update kubeconfig:

```bash
aws eks update-kubeconfig --region ap-south-1 --name iac-pipeline-dev-eks
kubectl get nodes
```

If kubectl still fails, check the ARN from:

```bash
aws sts get-caller-identity
```

and use the exact ARN in the commands above.

---

## 6) Create the EKS nodegroup if it is missing

Your cluster may exist but have no worker nodes. This is the main issue causing `Pending` pods.

Check:

```bash
aws eks list-nodegroups --cluster-name iac-pipeline-dev-eks --region ap-south-1
```

If it returns an empty list, create the nodegroup:

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

Wait until the nodegroup is active:

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

If nodes are ready, the cluster is finally usable.

---

## 7) Terraform usage

Use Terraform only when the required AWS resources are missing. If you already have an active cluster and IAM roles, do not repeatedly run a full create for everything because AWS will return already-exists errors.

For a fresh environment, run:

```bash
cd ~/iac-quality-gate-pipeline/terraform
terraform init
terraform plan
terraform apply -auto-approve
```

If resources already exist, the faster path is simply to create the missing nodegroup and continue with the app deployment.

---

## 8) Run the project bootstrap and deployment

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
