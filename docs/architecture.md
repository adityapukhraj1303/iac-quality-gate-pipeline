# Architecture Specification

## Overview

The **Infrastructure-as-Code Quality Gate & Auto-Deployment Pipeline** is an enterprise-grade platform built without application frameworks or heavyweight runtimes. It orchestrates infrastructure provisioning, static analysis, containerization, deployment, and monitoring using **strictly Bash, HCL, Groovy, and YAML**.

```mermaid
graph TD
    DEV["DevOps Engineer / SRE"] -->|Trigger| CLI["scripts/cli.sh<br/>(Interactive Bash Menu)"]
    DEV -->|Push Code| SCM["GitHub Repository"]

    subgraph CI_CD ["Jenkins Automated 8-Stage Pipeline"]
        S1["1. Checkout & Discovery"] --> S2["2. Terraform Plan/Apply"]
        S2 --> S3["3. Docker Build (Alpine + Bash)"]
        S3 --> S4["4. SonarQube Quality Gate (ShellCheck)"]
        S4 --> S5["5. Push to AWS ECR"]
        S5 --> S6["6. Deploy to Kubernetes (EKS)"]
        S6 --> S7["7. Post-Deploy Smoke Test (/health)"]
        S7 --> S8["8. Telemetry & Metrics Notification"]
    end

    SCM --> S1

    subgraph AWS_INFRA ["AWS Cloud Infrastructure"]
        TF["Terraform State (S3 + DynamoDB)"]
        VPC["AWS VPC (Public/Private Subnets + NAT)"]
        EKS["Amazon EKS Cluster (v1.29)"]
        ECR["Amazon ECR Registry"]
        SSM["AWS SSM Parameter Store (/iac-pipeline/*)"]
    end

    S2 --> TF
    S2 --> VPC
    S2 --> EKS
    S2 --> ECR
    S2 --> SSM

    subgraph K8S_WORKLOADS ["Kubernetes Workloads"]
        APP["iac-quality-gate-app Pods<br/>(socat Bash daemon)"]
        SVC["ClusterIP Service"]
        ING["ALB Ingress Controller"]
        HPA["Horizontal Pod Autoscaler"]
    end

    S6 --> APP
    APP --> SVC --> ING
    APP --> HPA

    subgraph OBSERVABILITY ["Observability & Metrics"]
        PROM["Prometheus"]
        GRAF["Grafana (pipeline-overview.json)"]
        ALRT["Alertmanager"]
    end

    PROM --> APP
    PROM --> S1
    GRAF --> PROM
    PROM --> ALRT
```

## Security & Architecture Highlights

1. **Zero Static Credentials**: All nodes, instances, and pipeline runners authenticate using IAM roles and AWS Systems Manager (SSM). No access keys or secrets are stored in Git.
2. **Decoupled State Discovery**: Terraform exports cluster endpoints, ECR URLs, and VPC details directly into AWS SSM Parameter Store. Any instance with an IAM role can run `bootstrap.sh` and immediately interact with the cluster.
3. **Automated Quality Gate Enforcement**: The pipeline executes static ShellCheck rules in SonarQube and triggers `waitForQualityGate abortPipeline: true` to prevent flawed configurations from ever reaching production.
4. **Resilient Rolling Deployments**: Kubernetes deployments enforce active liveness and readiness probes against `/health` with automated rollbacks on smoke test failure.
