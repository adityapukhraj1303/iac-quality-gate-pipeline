output "vpc_id" {
  description = "The VPC ID"
  value       = module.vpc.vpc_id
}

output "cluster_name" {
  description = "The EKS Cluster Name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The EKS Cluster API Endpoint"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "The ECR Repository URL"
  value       = module.ecr.repository_url
}

output "ssm_parameters_path" {
  description = "SSM Parameter Store prefix for fetching outputs on any AWS instance"
  value       = "/iac-pipeline/${var.environment}"
}

output "ssm_fetch_command" {
  description = "Command to fetch all configuration parameters from any AWS instance"
  value       = "aws ssm get-parameters-by-path --path '/iac-pipeline/${var.environment}' --recursive --query 'Parameters[*].[Name,Value]' --output table"
}

output "kubeconfig_command" {
  description = "Command to configure kubectl on any AWS instance with proper IAM role"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
