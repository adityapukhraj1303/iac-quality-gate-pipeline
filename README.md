# iac-quality-gate-pipeline

This repository provisions the AWS platform and deploys a containerized Bash microservice through Terraform, Kubernetes, Jenkins, and SonarQube. The project is configured for the AWS region `ap-south-1` and expects all infrastructure and deployment steps to run in that region.

## Project purpose

The repository automates the following:
- AWS networking, IAM, ECR, and EKS provisioning with Terraform
- publishing infrastructure metadata to AWS SSM Parameter Store
- bootstrap of EC2 instances with the required CLI and cluster tools
- Kubernetes deployment of the application with rollout checks and smoke tests
- Jenkins pipeline execution with SonarQube quality gate enforcement
- monitoring with Prometheus and Grafana

## Required AWS region

This project is intentionally pinned to `ap-south-1`.

- Terraform provider region: `ap-south-1`
- Terraform dev tfvars: `ap-south-1`
- Jenkins environment: `AWS_REGION = 'ap-south-1'`
- bootstrap/deploy scripts default AWS region: `AWS_REGION:-ap-south-1`

No region references in the current repo should be set to `us-east-1`.

## Required setup order

This is the correct startup sequence and it must be followed in this exact order:

1. Run `terraform apply` in the Terraform directory.
2. Verify the 5 SSM parameter names exist under `/iac-pipeline/<env>`.
3. Only after that, run `bootstrap.sh` and `deploy.sh`.
4. Trigger the Jenkins build only after the cluster, ECR repo, and SSM parameters are present.

This order is required because `scripts/deploy.sh` reads `/iac-pipeline/${ENV}/cluster_name` and exits if it is missing.

## Verify the five SSM parameters

The Terraform root module publishes these exact names:

```bash
aws ssm get-parameters-by-path \
  --path "/iac-pipeline/dev" \
  --recursive \
  --query "Parameters[*].[Name,Value]" \
  --output table
```

Expected values include:
- `/iac-pipeline/dev/cluster_name`
- `/iac-pipeline/dev/cluster_endpoint`
- `/iac-pipeline/dev/ecr_repository_url`
- `/iac-pipeline/dev/vpc_id`
- `/iac-pipeline/dev/grafana_url`

Do not run `bootstrap.sh` or `deploy.sh` before these values exist.

## Terraform workflow

From the repository root:

```bash
cd terraform
terraform init
terraform apply -var-file="environments/dev/terraform.tfvars"
```

After `terraform apply` succeeds, verify SSM:

```bash
aws ssm get-parameters-by-path --path "/iac-pipeline/dev" --recursive --query "Parameters[*].[Name,Value]" --output table
```

Then proceed to cluster bootstrap and deployment:

```bash
cd ..
bash scripts/bootstrap.sh dev
bash scripts/deploy.sh dev latest
```

## Bootstrap and deployment scripts

The bootstrap flow performs environment detection, AWS login validation, package installation, and kubeconfig setup. It also checks for the cluster metadata under `/iac-pipeline/${ENV}` and can create infrastructure when the cluster is missing.

The deploy flow expects the cluster metadata to already exist and exits cleanly if the parameter is absent.

### Required preflight behavior

The deploy script must do this before any `kubectl` or EKS action:

```bash
aws ssm get-parameter --name "/iac-pipeline/${ENV}/cluster_name" --query 'Parameter.Value' --output text
```

If that parameter is missing, the script must fail with a clear message telling the operator to run:

```bash
cd terraform
terraform apply -var-file="environments/dev/terraform.tfvars"
```

## Jenkins setup

A real Jenkins installation is required before the first pipeline build.

### What is configured in this repo
- The pipeline does not declare any explicit Jenkins credential IDs.
- Authentication for AWS is expected to come from the Jenkins agent's IAM instance profile / EC2 role.
- The SonarQube integration name is exactly `SonarQube-Server`.

### Required Jenkins configuration before the first build

In Jenkins, go to `Manage Jenkins` > `System` and configure:

1. A SonarQube server named exactly: `SonarQube-Server`
2. The Jenkins agent must have these tools installed:
   - AWS CLI
   - Docker
   - kubectl
   - Terraform
   - sonar-scanner
3. The Jenkins agent must have AWS permissions via IAM instance profile or equivalent configured credentials.

The pipeline references the SonarQube server by `withSonarQubeEnv('SonarQube-Server')` and calls `waitForQualityGate()`.

## Jenkins pipeline parameters

The Jenkins pipeline defines four parameters:

- `ENVIRONMENT` — target environment (`dev` or `prod`)
- `IMAGE_TAG` — Docker image tag to build and deploy, default is `build-${BUILD_NUMBER}`
- `SKIP_QUALITY_GATE` — emergency override to skip the SonarQube quality gate when set to `true`
- `AUTO_ROLLBACK` — if `true`, attempts to roll back the Kubernetes deployment after a smoke-test failure

Example build parameters:

```bash
ENVIRONMENT=dev
IMAGE_TAG=build-42
SKIP_QUALITY_GATE=false
AUTO_ROLLBACK=true
```

## IAM policy behavior

The IAM policy is now narrowed and uses specific ARNs instead of wildcard broad access.

Post-fix behavior:
- ECR permissions are scoped to the specific repository ARN
- EKS `DescribeCluster` access is scoped to the specific cluster ARN
- SSM access is narrowed to the exact five SSM parameter ARNs used by the project
- wildcard access is not used for the project-specific actions that are required by Jenkins and CI runners

This is the intended least-privilege model for the runner and deployment pipeline.

## Application and Kubernetes details

The deployment manifest defines the container name as `bash-microservice` and the deploy script updates that container image using:

```bash
kubectl set image deployment/iac-quality-gate-app bash-microservice=${IMAGE_TARGET} -n ${NAMESPACE}
```

The application health check is served at `/health` and the post-deploy smoke test checks it before declaring success.

## Repository structure

```text
.
├── app/
├── terraform/
│   ├── backend.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── variables.tf
│   └── environments/
│       ├── dev/
│       └── prod/
├── scripts/
│   ├── bootstrap.sh
│   ├── deploy.sh
│   └── ...
├── k8s/
├── jenkins/
│   ├── Jenkinsfile
│   └── sonar-project.properties
├── docker/
├── monitoring/
├── docs/
├── README.md
└── LICENSE
```

## TODO(review)

- Confirm the exact ECR repository ARN and EKS cluster ARN used at runtime in your AWS account before you attach the final IAM policy in a production environment.
- Validate whether your AWS IAM model permits `eks:ListClusters` to be narrowed beyond `*`; AWS semantics may require `ListClusters` to remain wildcard-scoped.
- Validate the full pipeline in a real AWS environment because this session could not run Terraform or shell validation tools here: the local environment used for this review does not have `terraform` or a Unix `bash` runtime installed.

## Summary

The supported pattern for this project is:

```bash
cd terraform
terraform apply -var-file="environments/dev/terraform.tfvars"
aws ssm get-parameters-by-path --path "/iac-pipeline/dev" --recursive --query "Parameters[*].[Name,Value]" --output table
cd ..
bash scripts/bootstrap.sh dev
bash scripts/deploy.sh dev latest
```

This sequence ensures the required SSM parameters exist before the deployment and bootstrap scripts run, which is the safe and supported path for a first successful deployment.
