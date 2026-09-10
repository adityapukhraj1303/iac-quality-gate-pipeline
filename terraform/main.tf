# ==============================================================================
# Root Terraform Orchestration: Modules + AWS SSM Parameter Store Registry
# ==============================================================================

locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
  ecr_name     = "${var.project_name}-app-${var.environment}"
}

# 1. VPC Module
module "vpc" {
  source               = "./modules/vpc"
  project_name         = var.project_name
  environment          = var.environment
  cluster_name         = local.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# 2. IAM Roles & Instance Profiles Module
module "iam" {
  source             = "./modules/iam"
  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  cluster_arn        = module.eks.cluster_arn
  ecr_repository_arn = module.ecr.repository_arn
}

# 3. ECR Repository Module
module "ecr" {
  source          = "./modules/ecr"
  repository_name = local.ecr_name
  environment     = var.environment
}

# 4. EKS Cluster & Managed Node Group Module
module "eks" {
  source             = "./modules/eks"
  cluster_name       = local.cluster_name
  cluster_version    = var.cluster_version
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  cluster_role_arn   = module.iam.eks_cluster_role_arn
  node_role_arn      = module.iam.eks_node_role_arn
  node_instance_type = var.node_instance_type
  desired_node_count = var.desired_nodes
  min_node_count     = var.min_nodes
  max_node_count     = var.max_nodes
}

# 5. Dedicated EC2 CI Runner / Bastion Module (Optional)
module "ec2" {
  count                 = var.enable_ec2_runner ? 1 : 0
  source                = "./modules/ec2"
  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  subnet_id             = module.vpc.private_subnet_ids[0]
  instance_profile_name = module.iam.ci_runner_profile_name
}

# ==============================================================================
# AWS SSM Parameter Store: Cross-Instance Dynamic Parameter Publication
# Any AWS EC2 instance can query these without local state files!
# ==============================================================================

resource "aws_ssm_parameter" "cluster_name" {
  name        = "/iac-pipeline/${var.environment}/cluster_name"
  description = "EKS Cluster Name for ${var.environment}"
  type        = "String"
  value       = module.eks.cluster_name
  overwrite   = true
}

resource "aws_ssm_parameter" "cluster_endpoint" {
  name        = "/iac-pipeline/${var.environment}/cluster_endpoint"
  description = "EKS API Server Endpoint for ${var.environment}"
  type        = "String"
  value       = module.eks.cluster_endpoint
  overwrite   = true
}

resource "aws_ssm_parameter" "ecr_repository_url" {
  name        = "/iac-pipeline/${var.environment}/ecr_repository_url"
  description = "ECR Repository URL for ${var.environment}"
  type        = "String"
  value       = module.ecr.repository_url
  overwrite   = true
}

resource "aws_ssm_parameter" "vpc_id" {
  name        = "/iac-pipeline/${var.environment}/vpc_id"
  description = "VPC ID for ${var.environment}"
  type        = "String"
  value       = module.vpc.vpc_id
  overwrite   = true
}

resource "aws_ssm_parameter" "grafana_url" {
  name        = "/iac-pipeline/${var.environment}/grafana_url"
  description = "Internal monitoring Grafana URL for ${var.environment}"
  type        = "String"
  value       = "http://grafana.${var.environment}.internal:3000"
  overwrite   = true
}
