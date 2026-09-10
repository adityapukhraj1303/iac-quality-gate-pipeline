variable "project_name" {
  description = "Project name identifier"
  type        = string
  default     = "iac-pipeline"
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region used for the project"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_arn" {
  description = "ARN of the EKS cluster used by the CI runner"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository used by the CI runner"
  type        = string
}
